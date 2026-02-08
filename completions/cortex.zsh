#compdef cortex-daemon.sh cortex-status.sh cortex-watch.sh cortex-doctor.sh

# Zsh completion for Cortex commands

_cortex_daemon() {
    local -a commands
    commands=(
        'start:Start the daemon'
        'stop:Stop the daemon'
        'status:Check daemon status'
        'restart:Restart the daemon'
        'logs:Show daemon logs (use -f to follow)'
    )

    _arguments -C \
        '1: :->command' \
        '*:: :->args'

    case $state in
        command)
            _describe 'cortex daemon command' commands
            ;;
        args)
            case $words[1] in
                logs)
                    _arguments \
                        '(-f --follow)'{-f,--follow}'[Follow log output]'
                    ;;
            esac
            ;;
    esac
}

_cortex_status() {
    _arguments \
        '--json[Output in JSON format]'
}

_cortex_watch() {
    _arguments \
        '--daemon[Run in daemon mode]' \
        '1:project directory:_files -/'
}

_cortex_doctor() {
    _arguments \
        '--fix[Attempt to fix detected issues]'
}

# Main dispatcher based on script name
case "$service" in
    cortex-daemon.sh)
        _cortex_daemon
        ;;
    cortex-status.sh)
        _cortex_status
        ;;
    cortex-watch.sh)
        _cortex_watch
        ;;
    cortex-doctor.sh)
        _cortex_doctor
        ;;
esac

# Register for common paths
compdef _cortex_daemon "$HOME/.cortex/bin/cortex-daemon.sh"
compdef _cortex_status "$HOME/.cortex/bin/cortex-status.sh"
compdef _cortex_watch "$HOME/.cortex/bin/cortex-watch.sh"
compdef _cortex_doctor "$HOME/.cortex/bin/cortex-doctor.sh"
