# fish demo_test.fish: exits non-zero on the first failure.
set -l root (path dirname (path resolve (status filename)))
source $root/demo.fish

set -g failed 0
function check -a name
    if test $status -ne 0
        echo "FAIL $name"
        set -g failed 1
    end
end

set -l tmp (mktemp -d)
mkdir -p $tmp/acts/1-test
printf '%s\n' 'tofu apply' '' '# on x:' 'ssh root@x hostname' >$tmp/acts/1-test/commands.txt

# test_extract
set -l got (__demo_commands $tmp/acts/1-test/commands.txt)
test (count $got) -eq 2 -a "$got[1]" = 'tofu apply' -a "$got[2]" = 'ssh root@x hostname'
check test_extract

# test_no_act
set -e __demo_cmds
set -l out (__demo_step 1 2>&1)
test $status -eq 1; and string match -q '*demo N first*' -- $out
check test_no_act

# test_bounds
set -g __demo_root $tmp
demo 1 >/dev/null
__demo_step -1 >/dev/null 2>&1
test $status -eq 1
check test_bounds_start
test (__demo_step 1) = 'tofu apply'
check test_bounds_first
test (__demo_step 1) = 'ssh root@x hostname'
check test_bounds_second
__demo_step 1 >/dev/null 2>&1
test $status -eq 1 -a $__demo_i -eq 2
check test_bounds_end
test (__demo_status) = 'act 1 · 2/2'
check test_status

rm -r $tmp
set -g __demo_root $root

# The real run sheets: what goes wrong on stage if they are wrong.
for n in (seq 0 9)
    set -l file $root/acts/$n-*/commands.txt
    test (count $file) -eq 1
    check "test_every_act_has_commands act $n: one commands.txt"
    test (count $file) -eq 1; or continue
    set -l cmds (__demo_commands $file)
    test (count $cmds) -ge 1
    check "test_every_act_has_commands act $n"
    for c in $cmds
        fish --no-config --no-execute -c $c 2>/dev/null
        check "test_commands_parse act $n: $c"
        not string match -rq '<[a-z_]+>' -- $c
        check "test_no_placeholders act $n: $c"
        # A secret on the projector: tofu output -raw only inside (…) or into pbcopy.
        not string replace -ra '\(tofu output -raw \w+[^)]*\)|tofu output -raw \w+ \| pbcopy' '' -- $c | string match -q '*tofu output -raw*'
        check "test_no_bare_outputs act $n: $c"
    end
end

# The sheets are commands only: copyable as they stand.
for f in $root/acts/*/commands.txt
    not string match -q -r '^\s*\$ |^\s*[0-9]+\. |^ACT ' <$f
    check "test_sheet_is_commands_only $f"
end

# Server-side commands are plain lines under "# on <host>:", pasted in that
# host's ssh window; ssh one-liners only where a value comes from the laptop.
for f in $root/acts/*/commands.txt
    set -l under 0
    for l in (string collect <$f | string split \n)
        if string match -q '# on *:' -- $l
            set under 1
        else if test -z "$l"
            set under 0
        else if string match -rq '^(headscale |helm |systemd-run |apt-get |dpkg |systemctl |tailscale up |kubectl create namespace|kubectl auth whoami|kubectl get nodes -o wide)' -- $l
            test $under -eq 1
            check "test_server_command_under_headline $f: $l"
        end
        if string match -rq '^ssh (-\S+ )*root@\S+ \S' -- $l; and not string match -q '*(tofu output*' -- $l; and not string match -q '* hostname' -- $l
            false
            check "test_no_ssh_one_liner $f: $l"
        end
    end
end

# Order inside the sheets.
function first_index -a pattern
    set -l i 0
    for c in $argv[2..]
        set i (math $i + 1)
        string match -rq -- $pattern $c; and echo $i; and return
    end
    echo 999
end
set -l prep (__demo_commands $root/acts/0-prep/commands.txt)
# scp to host: ends in a colon too, and is a command, not a headline.
contains -- 'scp ../acts/1-headscale/headscale.deb ../acts/1-headscale/config.yaml root@vpn.demo.headscale.no:' $prep
check test_scp_is_not_a_headline
# A stale host key fails the first ssh; cleared after it, the fresh key goes.
test (first_index 'ssh-keygen -R' $prep) -lt (first_index '^(ssh|scp) ' $prep)
check test_prep_clears_keys_first
string match -q '*vpn*' -- $prep[(first_index 'ssh-keygen -R' $prep)]
check test_prep_clears_vpn_key
test (first_index '^tofu init' $prep) -lt (first_index '^tofu apply' $prep)
check test_prep_inits_before_apply
# The flake-built provider has one checksum per build platform; init refuses an unknown one.
test (first_index '^tofu providers lock -fs-mirror=' $prep) -lt (first_index '^tofu init' $prep)
check test_prep_locks_provider_before_init
for n in 6 7
    set -l cmds (__demo_commands $root/acts/$n-*/commands.txt)
    test (first_index 'headscale nodes list' $cmds) -lt (first_index '^open ' $cmds)
    check "test_nodes_list_before_open act $n"
end

# k3s on adds ~550 MB to the laptop's store; on venue Wi-Fi that is minutes.
string match -q '*nix build*pkgs.k3s*pkgs.kubernetes-helm*' -- $prep
check test_prep_fetches_k3s
# The operator, proxy and tsnet nodes join seconds after the command that starts them.
set -l waits 5 'configure kubeconfig' 6 'headscale nodes list' 7 'headscale nodes list'
for i in 1 3 5
    set -l cmds (__demo_commands $root/acts/$waits[$i]-*/commands.txt)
    test (first_index '^while not tailscale status' $cmds) -lt (first_index $waits[(math $i + 1)] $cmds)
    check "test_waits_for_node act $waits[$i]"
end

# The branch is frozen: a rebuild costs prep minutes and a memory spike for the same .deb.
contains -- 'test -e ../acts/1-headscale/headscale.deb; or ../acts/1-headscale/build.sh' $prep
check test_prep_builds_only_when_missing

# headscale is installed in act 1, so nothing in prep may need it running.
not string match -q -r 'dpkg -i|apikeys create|TAILSCALE_API_KEY' -- $prep
check test_prep_needs_no_headscale
set -l a1 (__demo_commands $root/acts/1-headscale/commands.txt)
test (first_index '^dpkg -i --force-confold headscale.deb$' $a1) -lt (first_index 'TAILSCALE_API_KEY' $a1)
check test_act1_installs_headscale_first
# Pasted line by line into an ssh window on the VM: one command per line.
not string match -q '*&&*' -- $a1
check test_act1_one_command_per_line
string match -q '*# on vpn.demo.headscale.no:
dpkg -i --force-confold headscale.deb*' -- (string collect <$root/acts/1-headscale/commands.txt)
check test_act1_server_block_has_headline
# The tailscale provider needs the API key the new headscale mints.
test (first_index 'TAILSCALE_API_KEY' $a1) -lt (first_index '^tofu apply' $a1)
check test_act1_api_key_before_apply
# The laptop logs in on the web page, like a person; the register line takes the pasted ID.
contains -- 'tailscale login --login-server=https://vpn.demo.headscale.no' $a1
check test_act1_laptop_web_login
string match -q 'headscale auth register --user kradalby --auth-id*' -- $a1
check test_act1_registers_laptop

# live/ is what is up before the talk: prep applies it, the acts only join.
for f in server1.tf server2-vm.tf k3s.tf
    test -e $root/live/$f
    check "test_live_holds_prep_vms $f"
end
not string match -q -r '^mv ' -- $prep
check test_prep_moves_nothing
# The k3s nodes join in act 4, not on first boot.
not string match -q '*tailscale_*' <$root/live/k3s.tf
check test_k3s_prep_has_no_tailnet_resources
set -l a4 (__demo_commands $root/acts/4-k3s/commands.txt)
test (first_index 'k3s-join.tf' $a4) -lt (first_index 'configuration.nix' $a4)
check test_act4_joins_before_k3s_on
not string match -q '*resource "gigahost_server"*' <$root/acts/3-server2/server2.tf
check test_stage_server2_only_joins

# An unpinned chart can name an image ghcr does not have yet; upgrade --install can rerun.
set -l op (__demo_commands $root/acts/5-operator/commands.txt)
string match -q '*helm*upgrade --install tailscale-operator*--version *' -- $op
check test_operator_chart_pinned

# Option composes characters on a Mac (on a Norwegian layout it types @).
fish --no-config -ic "source $root/demo.fish; bind ctrl-o" 2>/dev/null | string match -q '*__demo_key -1*'
check test_back_key_without_option

# Reset leaves headscale up: act 1 creates kradalby, act 9 starts the Pi unit.
string match -q '*users destroy --name kradalby --force*' <$root/README.md
check test_reset_destroys_user
string match -q '*systemctl stop guestbook*' <$root/README.md
check test_reset_stops_pi_guestbook
# The prep VMs stay in live/, joined and changed by the acts: the reset makes them new.
for r in 'gigahost_server.server1' 'gigahost_server.server2' 'gigahost_server.k3s["k3s1"]'
    string match -q -- "*-replace='$r'*" <$root/README.md
    check "test_reset_replaces_prep_vms $r"
end

exit $failed
