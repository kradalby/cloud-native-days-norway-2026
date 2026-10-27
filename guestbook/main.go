// Command guestbook is a visit wall. CI signs it with what it could reach on
// the tailnet, and the page shows each visit as it lands.
package main

import (
	"context"
	"embed"
	"encoding/json"
	"flag"
	"fmt"
	"log"
	"net"
	"net/http"
	"net/netip"
	"os"
	"runtime"
	"slices"
	"strings"
	"sync"
	"time"

	"tailscale.com/client/local"
	"tailscale.com/tsnet"
	"tailscale.com/types/views"
)

//go:embed index.html logo.svg
var assets embed.FS

const maxVisits = 50

type Result struct {
	Target string `json:"target"`
	Want   string `json:"want"` // reach or block
	Got    string `json:"got"`  // reached, hidden or blocked
}

// Who is what the tailnet says about a caller. Only tsnet can ask.
type Who struct {
	Node    string   `json:"node"`
	Tags    []string `json:"tags,omitempty"`
	User    string   `json:"user,omitempty"`
	OS      string   `json:"os,omitempty"`
	Version string   `json:"version,omitempty"`
}

type Visit struct {
	Time    time.Time `json:"time"`
	From    string    `json:"from"`
	Who     *Who      `json:"who,omitempty"`
	Name    string    `json:"name"`
	Run     string    `json:"run,omitempty"`
	URL     string    `json:"url,omitempty"`
	Actor   string    `json:"actor,omitempty"`
	Message string    `json:"message,omitempty"`
	SHA     string    `json:"sha,omitempty"`
	Results []Result  `json:"results,omitempty"`
}

type Peer struct {
	Name   string   `json:"name"`
	IP     string   `json:"ip,omitempty"`
	OS     string   `json:"os,omitempty"`
	Tags   []string `json:"tags,omitempty"`
	Online bool     `json:"online"`
}

type server struct {
	instance string
	host     string
	lc       *local.Client // nil unless on tsnet

	mu     sync.Mutex
	visits []Visit
}

func (s *server) routes() http.Handler {
	mux := http.NewServeMux()
	mux.HandleFunc("POST /visit", s.visit)
	mux.HandleFunc("GET /visits", s.list)
	mux.Handle("GET /{$}", http.FileServerFS(assets))
	mux.Handle("GET /logo.svg", http.FileServerFS(assets))
	return mux
}

func (s *server) visit(w http.ResponseWriter, r *http.Request) {
	// The body comes from anyone who can reach the port.
	r.Body = http.MaxBytesReader(w, r.Body, 64<<10)
	var v Visit
	if err := json.NewDecoder(r.Body).Decode(&v); err != nil {
		http.Error(w, err.Error(), http.StatusBadRequest)
		return
	}
	v.Time = time.Now()
	v.From, _, _ = net.SplitHostPort(r.RemoteAddr)
	if s.lc != nil {
		v.Who = s.whois(r.Context(), r.RemoteAddr)
	}
	if v.Name == "" {
		v.Name = "someone"
	}

	s.mu.Lock()
	s.visits = append([]Visit{v}, s.visits[:min(len(s.visits), maxVisits-1)]...)
	s.mu.Unlock()

	name := v.Name
	if v.Run != "" {
		name += " run #" + v.Run
	}
	fmt.Fprintf(w, "👋 %s, you reached guestbook on %s (%s, %s/%s).", name, s.instance, s.host, runtime.GOOS, runtime.GOARCH)
	if v.Who != nil {
		fmt.Fprintf(w, " Tailscale says you are %s", v.Who.Node)
		if len(v.Who.Tags) > 0 {
			fmt.Fprintf(w, ", %s", strings.Join(v.Who.Tags, ","))
		} else if v.Who.User != "" {
			fmt.Fprintf(w, ", %s", v.Who.User)
		}
		fmt.Fprint(w, ".")
	}
	fmt.Fprintln(w)
}

func (s *server) whois(ctx context.Context, addr string) *Who {
	wr, err := s.lc.WhoIs(ctx, addr)
	if err != nil {
		log.Printf("whois %s: %v", addr, err)
		return nil
	}
	who := &Who{
		Node:    wr.Node.ComputedName,
		Tags:    wr.Node.Tags,
		OS:      wr.Node.Hostinfo.OS(),
		Version: wr.Node.Hostinfo.IPNVersion(),
	}
	// Tagged nodes all belong to the same placeholder user.
	if len(who.Tags) == 0 && wr.UserProfile != nil {
		who.User = wr.UserProfile.LoginName
	}
	return who
}

func (s *server) list(w http.ResponseWriter, r *http.Request) {
	s.mu.Lock()
	out := map[string]any{
		"instance": s.instance,
		"host":     s.host,
		"arch":     runtime.GOOS + "/" + runtime.GOARCH,
		"visits":   slices.Clone(s.visits),
	}
	s.mu.Unlock()

	if s.lc != nil {
		if st, err := s.lc.Status(r.Context()); err == nil {
			out["self"] = peerOf(st.Self.DNSName, st.Self.TailscaleIPs, st.Self.OS, st.Self.Tags, true)
			var peers []Peer
			for _, p := range st.Peer {
				peers = append(peers, peerOf(p.DNSName, p.TailscaleIPs, p.OS, p.Tags, p.Online))
			}
			slices.SortFunc(peers, func(a, b Peer) int { return strings.Compare(a.Name, b.Name) })
			out["peers"] = peers
		}
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(out)
}

func peerOf(dnsName string, ips []netip.Addr, osName string, tags *views.Slice[string], online bool) Peer {
	p := Peer{Name: strings.Split(dnsName, ".")[0], OS: osName, Online: online}
	if len(ips) > 0 {
		p.IP = ips[0].String()
	}
	if tags != nil {
		p.Tags = tags.AsSlice()
	}
	return p
}

func main() {
	instance := flag.String("instance", "local", "name shown on the page: k8s, pi or tsnet")
	listen := flag.String("listen", ":8080", "address to serve on")
	tsName := flag.String("tsnet", "", "join the tailnet as this node with tsnet, instead of listening on the host")
	control := flag.String("control", "", "control server URL for -tsnet")
	state := flag.String("state", "", "state directory for -tsnet")
	flag.Parse()

	host, _ := os.Hostname()
	s := &server{instance: *instance, host: host}

	var ln net.Listener
	var err error
	if *tsName != "" {
		// The auth key comes from TS_AUTHKEY, which tsnet reads itself.
		ts := &tsnet.Server{
			Hostname:   *tsName,
			ControlURL: *control,
			Dir:        *state,
			Logf:       func(string, ...any) {},
		}
		defer ts.Close()
		if _, err := ts.Up(context.Background()); err != nil {
			log.Fatalf("tsnet up: %v", err)
		}
		if s.lc, err = ts.LocalClient(); err != nil {
			log.Fatal(err)
		}
		ln, err = ts.Listen("tcp", *listen)
	} else {
		ln, err = net.Listen("tcp", *listen)
	}
	if err != nil {
		log.Fatal(err)
	}

	log.Printf("guestbook on %s, serving %s", *instance, ln.Addr())
	srv := &http.Server{Handler: s.routes(), ReadHeaderTimeout: 10 * time.Second}
	log.Fatal(srv.Serve(ln))
}
