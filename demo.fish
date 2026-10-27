# source ../demo.fish in the stage terminal, then `demo N` per slide.
# ctrl-g puts the act's next command on the prompt, ctrl-o the one before.
# No Option keys: on a Mac, Option types characters (@ on a Norwegian layout).
# Nothing runs until Enter, so a command can be read or edited first.

set -g __demo_root (path dirname (path resolve (status filename)))

# Every line of a run sheet is a command, except blanks and "# on host:"
# headlines that say where the block below runs.
function __demo_commands -a file
    string match -rv '^\s*$|^\s*#' <$file
end

function demo -a n
    set -l file $__demo_root/acts/$n-*/commands.txt
    if test -z "$n" -o (count $file) -ne 1
        echo "demo N: pick act N (0-9). ctrl-g next command, ctrl-o back."
        return 1
    end
    set -g __demo_act $n
    set -g __demo_cmds (__demo_commands $file)
    set -g __demo_i 0
    echo "act $n: "(count $__demo_cmds)" commands, ctrl-g for the first"
end

function __demo_step -a d
    if not set -q __demo_cmds[1]
        echo "demo N first" >&2
        return 1
    end
    set -l j (math $__demo_i + $d)
    if test $j -lt 1 -o $j -gt (count $__demo_cmds)
        echo "act $__demo_act: no more commands this way" >&2
        return 1
    end
    set -g __demo_i $j
    echo $__demo_cmds[$j]
end

function __demo_status
    set -q __demo_cmds[1]; and echo "act $__demo_act · $__demo_i/"(count $__demo_cmds)
end

function __demo_key -a d
    set -l cmd (__demo_step $d)
    and commandline -r -- $cmd
    commandline -f repaint
end

if not functions -q __demo_orig_right_prompt
    functions -q fish_right_prompt; and functions -c fish_right_prompt __demo_orig_right_prompt
    or function __demo_orig_right_prompt
    end
    function fish_right_prompt
        set_color brblack
        __demo_status
        set_color normal
        __demo_orig_right_prompt
    end
end

if status is-interactive
    for mode in default insert
        bind -M $mode ctrl-g '__demo_key 1'
        bind -M $mode ctrl-o '__demo_key -1'
    end
end
