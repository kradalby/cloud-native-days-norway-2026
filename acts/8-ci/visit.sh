#!/bin/sh
# Runs in GitHub Actions on the tailnet as tag:ci. Probes what CI may and may
# not reach, then signs each guestbook with what it found.
set -u

d=demo.onpremise.no
guestbooks="guestbook guestbook-tsnet"
# The Pi joins after CI's first run: act 9 sets the PI repo variable.
[ -n "${PI:-}" ] && guestbooks="$guestbooks rpi4"
results=$(mktemp)
fail=0

# probe TARGET WANT COMMAND...  WANT is reach or block.
probe() {
	target=$1 want=$2
	shift 2
	out=$("$@" 2>&1)
	rc=$?
	if [ $rc -eq 0 ]; then
		got=reached
	elif echo "$out" | grep -qi resolve; then
		got=hidden # not in CI's netmap: the policy gives it no path there
	else
		got=blocked # visible, but the packet filter drops it
	fi
	ok=✅
	if { [ "$want" = reach ] && [ $got != reached ]; } || { [ "$want" = block ] && [ $got = reached ]; }; then
		ok=❌
		fail=1
	fi
	printf '%s %-18s want %-5s got %-7s %s\n' "$ok" "$target" "$want" "$got" "$(echo "${out:-ok}" | tail -1)"
	jq -nc --arg t "$target" --arg w "$want" --arg g "$got" '{target: $t, want: $w, got: $g}' >>"$results"
	[ -n "${GITHUB_STEP_SUMMARY:-}" ] && echo "| $target | $want | $got | $ok |" >>"$GITHUB_STEP_SUMMARY"
}

http() { curl -sS -o /dev/null --fail --max-time "$1" "$2"; }
ssh_root() { ssh -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=no "root@$1" true; }

echo "== what CI sees"
tailscale status
echo

[ -n "${GITHUB_STEP_SUMMARY:-}" ] && printf '| target | want | got | |\n|---|---|---|---|\n' >>"$GITHUB_STEP_SUMMARY"

echo "== probes"
probe "guestbook k8s" reach http 10 "http://guestbook.$d/"
probe "guestbook tsnet" reach http 10 "http://guestbook-tsnet.$d/"
probe "k3s API" block http 5 "https://k3s1.$d:6443/"
probe "server1 SSH" block ssh_root "server1.$d"
probe "kubectl" block http 5 "https://tailscale-operator.$d/"
if [ -n "${PI:-}" ]; then
	probe "guestbook Pi" reach http 10 "http://rpi4.$d/"
	probe "Pi SSH" block ssh_root "rpi4.$d"
fi
echo

report=$(jq -n \
	--arg run "${RUN:-}" --arg url "${RUN_URL:-}" --arg actor "${ACTOR:-}" --arg sha "${SHA:-}" \
	--arg message "$(git log -1 --format=%s)" --slurpfile results "$results" \
	'{name: "GitHub Actions", run: $run, url: $url, actor: $actor, sha: $sha, message: $message, results: $results}')

echo "== signing the guestbooks"
for h in $guestbooks; do
	curl -sS --max-time 10 --json "$report" "http://$h.$d/visit" || fail=1
done

exit $fail
