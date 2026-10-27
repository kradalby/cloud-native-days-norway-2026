# Cloud Native Days Norway 2026: headscale with OpenTofu

Gigahost gives us VMs and DNS (`demo.headscale.no`). The stock
`tailscale/tailscale` provider talks to headscale through its
Tailscale-compatible `/api/v2` (headscale, branch `kradalby/set-dns`).

Public names are on `demo.headscale.no`, tailnet (MagicDNS) names on
`demo.onpremise.no`: `k3s1.demo.headscale.no` is the VM, `k3s1.demo.onpremise.no`
the same VM on the tailnet.

- `live/`: the only place `tofu` runs. Holds what is up before the talk.
- `acts/`: one folder per demo slide, with its files and `commands.txt`, the
  run sheet. Move the act's `.tf` files into `live/`, apply.
- `guestbook/`: the app acts 6, 7 and 9 run.

One terminal in `live/`: `source ../demo.fish`, then `demo N` at each slide.
ctrl-g puts the act's next command (a line of its run sheet) on the prompt,
ctrl-o the one before. Enter runs it. A block under `# on <host>:` runs
in an ssh window on that host: copy those lines there. `fish ../demo_test.fish` checks the run
sheets.

Once per machine:
- `Include <repo>/ssh_config` at the top of `~/.ssh/config`: new demo hosts
  are taken without a prompt. Prep's second command must print `accept-new`.
- Prep's `tofu providers lock` adds this machine type's checksum for the
  flake-built gigahost provider: commit `live/.terraform.lock.hcl` if it changed.
- The 1Password SSH agent: approval remembered until 1Password quits, and
  1Password unlocked through the talk. tofu's ssh goes through it.

Prep builds the headscale .deb only when it is missing: delete it after a
branch change. The first guestbook image push needs its ghcr package set to
public.

| act                | slide                                 | what                                          |
| ------------------ | ------------------------------------- | --------------------------------------------- |
| `acts/0-prep`      | before the talk                       | `live/`: the VMs (k3s nodes without a key), the headscale .deb shipped; binaries |
| `acts/1-headscale` | Let us set up headscale               | install headscale, API key, policy; the laptop joins |
| `acts/2-server1`   | Let us add a server with an auth key  | server1 joins by hand, laptop SSH             |
| `acts/3-server2`   | Let us add server2 as code            | tofu mints server2's key and joins it, server to server SSH |
| `acts/4-k3s`       | Let us set up a Kubernetes cluster    | the nodes join, then k3s over the tailnet     |
| `acts/5-operator`  | Let us install the Kubernetes operator | operator, kubectl as system:masters          |
| `acts/6-guestbook` | Let us expose Kubernetes resources    | guestbook on k3s                              |
| `acts/7-tsnet`     | Let us embed Tailscale                | guestbook-tsnet on server1                    |
| `acts/8-ci`        | Let us try "ephemeral" nodes          | CI signs two guestbooks                       |
| `acts/9-rpi`       | Let us add this Raspberry Pi          | the Pi joins, CI signs three                  |

The policy (`live/policy.hujson`) is grants only, and ships with every act
closed. Each act uncomments the lines that end in `// act N`.

## Timings

| step                               | time |
| ---------------------------------- | ---- |
| Gigahost: VM running               | 40s-3m |
| VM running to SSH up               | ~1m  |
| Tailscale install                  | <10s |
| `build.sh`, the .deb               | 45s, 1m40s from a clean clone |
| headscale install, cert included   | ~10s |
| join, by hand or by tofu           | ~3s  |
| 3 NixOS VMs, in parallel           | ~6m  |
| k3s on, all nodes Ready            | 30s-75s |
| operator `helm install`            | ~10s |
| first kubectl, cert included       | ~10s |
| `tailscale cert`                   | ~7s  |
| guestbook proxy node on the tailnet | ~10s |
| guestbook-tsnet on server1         | ~10s |
| CI run, push to done               | ~25s |

## Reset

Keeps headscale. Undoes the acts' files and lines, and makes server1, server2
and the k3s nodes new: the acts joined and changed them (~10-20m). Then delete
the old nodes in headscale, the CI secret and the Pi variable. The Pi logs out
first, the laptop last.

```sh
ssh root@rpi4.demo.onpremise.no 'systemctl stop guestbook; tailscale logout'   # first: it needs the tailnet
cd live && git clean -f . && git checkout . ../acts
tofu apply -replace='gigahost_server.server1' -replace='gigahost_server.server2' -replace='gigahost_server.k3s["k3s1"]' -replace='gigahost_server.k3s["k3s2"]' -replace='gigahost_server.k3s["k3s3"]'
ssh root@vpn.demo.headscale.no headscale nodes list
ssh root@vpn.demo.headscale.no headscale nodes delete -i <id> --force
ssh root@vpn.demo.headscale.no headscale users destroy --name kradalby --force   # after its nodes
gh secret delete HEADSCALE_AUTHKEY
gh variable delete PI
tailscale logout && tailscale switch <own tailnet>
```

## Gotchas

- Gigahost reuses IPs. A new VM can get an IP your laptop has seen before,
  and `ssh` then refuses: "REMOTE HOST IDENTIFICATION HAS CHANGED". Fix:
  `ssh-keygen -R <name or ip>`.
- After a headscale rebuild, your laptop can keep the old IP for up to 60s.
  Wait a minute before `tofu apply`.
- A headscale rebuild gets a new certificate. Let's Encrypt allows 5 per week.
- Now and then a Gigahost VM never becomes ready. tofu gives up after 10m
  (`timeouts`), and the next `tofu apply` replaces it. Before that apply, save
  what Gigahost says, so the cause can be traced:
  `gigahost deploy status <order>` and `gigahost servers get <id>` (both are in
  the error).
- A destroyed VM still counts against the account's credit for ~2.5m after
  `tofu destroy` returns.
