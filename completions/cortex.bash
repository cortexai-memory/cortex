# Bash completion for Cortex commands
# Source this file or install to /etc/bash_completion.d/

_cortex_daemon_completion() {
    local cur prev commands
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    prev="${COMP_WORDS[COMP_CWORD-1]}"
    commands="start stop status restart logs"

    if [ $COMP_CWORD -eq 2 ]; then
        COMPREPLY=( $(compgen -W "${commands}" -- ${cur}) )
        return 0
    fi

    if [ "$prev" = "logs" ]; then
        COMPREPLY=( $(compgen -W "-f --follow" -- ${cur}) )
        return 0
    fi
}

_cortex_status_completion() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"

    if [ $COMP_CWORD -eq 2 ]; then
        COMPREPLY=( $(compgen -W "--json" -- ${cur}) )
        return 0
    fi
}

_cortex_watch_completion() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"

    if [ $COMP_CWORD -ge 2 ]; then
        COMPREPLY=( $(compgen -W "--daemon" -- ${cur}) )
        return 0
    fi
}

_cortex_doctor_completion() {
    local cur
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"

    if [ $COMP_CWORD -eq 2 ]; then
        COMPREPLY=( $(compgen -W "--fix" -- ${cur}) )
        return 0
    fi
}

# Main completion dispatcher
_cortex_completion() {
    local cur prev script
    COMPREPLY=()
    cur="${COMP_WORDS[COMP_CWORD]}"
    script="${COMP_WORDS[0]}"

    case "$script" in
        *cortex-daemon.sh)
            _cortex_daemon_completion
            ;;
        *cortex-status.sh)
            _cortex_status_completion
            ;;
        *cortex-watch.sh)
            _cortex_watch_completion
            ;;
        *cortex-doctor.sh)
            _cortex_doctor_completion
            ;;
        *)
            # Default: offer common cortex commands
            local cortex_scripts="cortex-daemon.sh cortex-status.sh cortex-watch.sh cortex-doctor.sh cortex-session.sh cortex-compact.sh"
            COMPREPLY=( $(compgen -W "${cortex_scripts}" -- ${cur}) )
            ;;
    esac

    return 0
}

# Register completions for all cortex scripts
complete -F _cortex_completion cortex-daemon.sh
complete -F _cortex_completion cortex-status.sh
complete -F _cortex_completion cortex-watch.sh
complete -F _cortex_completion cortex-doctor.sh

# Also register for common invocation paths
if [ -d "$HOME/.cortex/bin" ]; then
    complete -F _cortex_daemon_completion "$HOME/.cortex/bin/cortex-daemon.sh"
    complete -F _cortex_status_completion "$HOME/.cortex/bin/cortex-status.sh"
    complete -F _cortex_watch_completion "$HOME/.cortex/bin/cortex-watch.sh"
    complete -F _cortex_doctor_completion "$HOME/.cortex/bin/cortex-doctor.sh"
fi
