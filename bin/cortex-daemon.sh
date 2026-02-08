#!/usr/bin/env bash
# Cortex Daemon — Background service manager
# Functions: start, stop, status, restart, logs
# Usage: cortex-daemon.sh {start|stop|status|restart|logs}

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/_cortex-utils.sh
source "$SCRIPT_DIR/_cortex-utils.sh" 2>/dev/null || \
  source "$CORTEX_HOME/bin/_cortex-utils.sh" 2>/dev/null || {
    echo "[Cortex] Error: Cannot find _cortex-utils.sh" >&2
    exit 1
  }

# ─── Configuration ────────────────────────────────────────────────────

CORTEX_HOME="${CORTEX_HOME:-$HOME/.cortex}"
DAEMON_LOG="$CORTEX_HOME/daemon.log"
DAEMON_PID="$CORTEX_HOME/daemon.pid"
MAX_LOG_SIZE=$((10 * 1024 * 1024))  # 10MB

# ─── Helper Functions ─────────────────────────────────────────────────

is_running() {
  if [[ ! -f "$DAEMON_PID" ]]; then
    return 1
  fi

  local pid
  pid=$(cat "$DAEMON_PID" 2>/dev/null || echo "")

  if [[ -z "$pid" ]]; then
    return 1
  fi

  if kill -0 "$pid" 2>/dev/null; then
    return 0
  else
    # Stale PID file
    rm -f "$DAEMON_PID"
    return 1
  fi
}

get_pid() {
  if [[ -f "$DAEMON_PID" ]]; then
    cat "$DAEMON_PID" 2>/dev/null || echo ""
  fi
}

rotate_logs() {
  if [[ -f "$DAEMON_LOG" ]]; then
    local log_size
    log_size=$(stat -f %z "$DAEMON_LOG" 2>/dev/null || stat -c %s "$DAEMON_LOG" 2>/dev/null || echo 0)

    if [[ "$log_size" -gt "$MAX_LOG_SIZE" ]]; then
      mv "$DAEMON_LOG" "$DAEMON_LOG.old"
      echo "[$(date -u +%FT%TZ)] Log rotated (size: $log_size bytes)" > "$DAEMON_LOG"
    fi
  fi
}

log_daemon() {
  local level="$1"
  shift
  local message="$*"
  echo "[$(date -u +%FT%TZ)] [$level] $message" >> "$DAEMON_LOG"
}

# ─── Daemon Background Process ────────────────────────────────────────

run_daemon() {
  # Setup
  echo $$ > "$DAEMON_PID"
  log_daemon "INFO" "Daemon started (PID: $$)"

  # Cleanup on exit
  trap 'log_daemon "INFO" "Daemon stopped"; rm -f "$DAEMON_PID"; exit 0' SIGINT SIGTERM EXIT

  # Load config
  local compact_interval=86400  # 24 hours
  local doctor_interval=604800  # 7 days
  local last_compact=0
  local last_doctor=0

  if [[ -f "$CORTEX_HOME/config" ]]; then
    while IFS='=' read -r key value; do
      [[ "$key" =~ ^[[:space:]]*# || -z "$key" ]] && continue
      key=$(echo "$key" | xargs)
      value=$(echo "$value" | xargs)
      case "$key" in
        daemon_compact_interval) compact_interval="$value" ;;
        daemon_doctor_interval)  doctor_interval="$value" ;;
      esac
    done < "$CORTEX_HOME/config"
  fi

  log_daemon "INFO" "Config: compact every ${compact_interval}s, doctor every ${doctor_interval}s"

  # Main loop
  while true; do
    local now
    now=$(date +%s)

    # Rotate logs if needed
    rotate_logs

    # Run periodic compaction
    if [[ $((now - last_compact)) -gt "$compact_interval" ]]; then
      log_daemon "INFO" "Running periodic compaction"
      if "$CORTEX_HOME/bin/cortex-compact.sh" >> "$DAEMON_LOG" 2>&1; then
        log_daemon "INFO" "Compaction completed"
      else
        log_daemon "WARN" "Compaction failed"
      fi
      last_compact="$now"
    fi

    # Run periodic health check
    if [[ $((now - last_doctor)) -gt "$doctor_interval" ]]; then
      log_daemon "INFO" "Running periodic health check"
      if "$CORTEX_HOME/bin/cortex-doctor.sh" >> "$DAEMON_LOG" 2>&1; then
        log_daemon "INFO" "Health check passed"
      else
        log_daemon "WARN" "Health check failed"
      fi
      last_doctor="$now"
    fi

    # Sleep for 1 hour before next check
    sleep 3600
  done
}

# ─── Commands ─────────────────────────────────────────────────────────

cmd_start() {
  if is_running; then
    _cortex_log error "Daemon already running (PID: $(get_pid))"
    exit 1
  fi

  # Start daemon in background
  nohup bash -c "
    source '$SCRIPT_DIR/_cortex-utils.sh' 2>/dev/null || source '$CORTEX_HOME/bin/_cortex-utils.sh'
    $(declare -f run_daemon)
    $(declare -f rotate_logs)
    $(declare -f log_daemon)
    CORTEX_HOME='$CORTEX_HOME'
    DAEMON_LOG='$DAEMON_LOG'
    DAEMON_PID='$DAEMON_PID'
    MAX_LOG_SIZE=$MAX_LOG_SIZE
    run_daemon
  " >> "$DAEMON_LOG" 2>&1 &

  # Wait a moment to verify it started
  sleep 1

  if is_running; then
    _cortex_log info "Daemon started (PID: $(get_pid))"
    _cortex_log info "Logs: $DAEMON_LOG"
  else
    _cortex_log error "Failed to start daemon. Check logs: $DAEMON_LOG"
    exit 1
  fi
}

cmd_stop() {
  if ! is_running; then
    _cortex_log warn "Daemon not running"
    exit 0
  fi

  local pid
  pid=$(get_pid)

  _cortex_log info "Stopping daemon (PID: $pid)..."

  # Send TERM signal
  kill -TERM "$pid" 2>/dev/null || true

  # Wait up to 5 seconds for graceful shutdown
  for i in {1..10}; do
    if ! is_running; then
      _cortex_log info "Daemon stopped"
      return 0
    fi
    sleep 0.5
  done

  # Force kill if still running
  if is_running; then
    _cortex_log warn "Forcing daemon shutdown..."
    kill -KILL "$pid" 2>/dev/null || true
    rm -f "$DAEMON_PID"
    _cortex_log info "Daemon killed"
  fi
}

cmd_status() {
  if is_running; then
    local pid uptime=""
    pid=$(get_pid)

    # Try to get process start time (macOS and Linux compatible)
    if ps -p "$pid" -o etime= >/dev/null 2>&1; then
      uptime=$(ps -p "$pid" -o etime= | xargs)
    fi

    echo "Cortex Daemon: RUNNING"
    echo "  PID: $pid"
    [[ -n "$uptime" ]] && echo "  Uptime: $uptime"
    echo "  Logs: $DAEMON_LOG"

    if [[ -f "$DAEMON_LOG" ]]; then
      local log_size
      log_size=$(stat -f %z "$DAEMON_LOG" 2>/dev/null || stat -c %s "$DAEMON_LOG" 2>/dev/null || echo 0)
      echo "  Log size: $(echo "scale=1; $log_size / 1024" | bc 2>/dev/null || echo $((log_size / 1024)))KB"
    fi
  else
    echo "Cortex Daemon: STOPPED"
    exit 1
  fi
}

cmd_restart() {
  if is_running; then
    cmd_stop
    sleep 1
  fi
  cmd_start
}

cmd_logs() {
  if [[ ! -f "$DAEMON_LOG" ]]; then
    _cortex_log warn "No log file found: $DAEMON_LOG"
    exit 1
  fi

  # Follow logs (like tail -f)
  if [[ "${1:-}" == "-f" ]] || [[ "${1:-}" == "--follow" ]]; then
    tail -f "$DAEMON_LOG"
  else
    # Show last 50 lines
    tail -50 "$DAEMON_LOG"
  fi
}

# ─── Main ─────────────────────────────────────────────────────────────

COMMAND="${1:-}"

case "$COMMAND" in
  start)
    cmd_start
    ;;
  stop)
    cmd_stop
    ;;
  status)
    cmd_status
    ;;
  restart)
    cmd_restart
    ;;
  logs)
    shift
    cmd_logs "$@"
    ;;
  *)
    echo "Cortex Daemon Manager"
    echo ""
    echo "Usage: cortex-daemon.sh {start|stop|status|restart|logs}"
    echo ""
    echo "Commands:"
    echo "  start    - Start the daemon"
    echo "  stop     - Stop the daemon"
    echo "  status   - Check daemon status"
    echo "  restart  - Restart the daemon"
    echo "  logs     - Show daemon logs (use -f to follow)"
    echo ""
    exit 1
    ;;
esac
