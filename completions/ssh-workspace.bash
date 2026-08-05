# Bash completion for ssh-workspace.
# Source from ~/.bashrc:  . /path/to/completions/ssh-workspace.bash

_ssh_workspace() {
    local cur prev hosts
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD - 1]}"

    case "$prev" in
        -m)
            COMPREPLY=($(compgen -W "auto tmux screen" -- "$cur"))
            return
            ;;
        -i)
            COMPREPLY=($(compgen -f -- "$cur"))
            return
            ;;
        -u | -s | -p | -o | -e | -c)
            return
            ;;
    esac

    if [[ "$cur" == -* ]]; then
        COMPREPLY=($(compgen -W "-u -s -m -p -i -o -e -c -l -n -h" -- "$cur"))
        return
    fi

    hosts=$(awk 'tolower($1) == "host" {
        for (i = 2; i <= NF; i++) if ($i !~ /[*?!]/) print $i
    }' ~/.ssh/config 2>/dev/null)
    COMPREPLY=($(compgen -W "$hosts" -- "$cur"))
}

complete -F _ssh_workspace ssh-workspace
