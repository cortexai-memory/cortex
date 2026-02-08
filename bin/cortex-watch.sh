#!/usr/bin/env bash
# Cortex File Watcher — Monitor file system events
# Dependencies: fswatch (macOS) or inotifywait (Linux)
# Usage: cortex-watch.sh [project-dir] [--daemon]

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/_cortex-utils.sh
source "$SCRIPT_DIR/_cortex-utils.sh" 2>/dev/null || \
  source "$CORTEX_HOME/bin/_cortex-utils.sh" 2>/dev/null || {
    echo "[Cortex] Error: Cannot find _cortex-utils.sh" >&2
    exit 1
  }

# ─── Parse Arguments ──────────────────────────────────────────────────

PROJECT_DIR="$(_cortex_project_root "${1:-}")"
DAEMON_MODE=false

for arg in "$@"; do
  if [[ "$arg" == "--daemon" ]]; then
    DAEMON_MODE=true
  fi
done

# ─── Setup ────────────────────────────────────────────────────────────

CORTEX_DIR="$PROJECT_DIR/.cortex"
EVENTS_FILE="$CORTEX_DIR/events.jsonl"
PID_FILE="$CORTEX_DIR/watch.pid"

mkdir -p "$CORTEX_DIR"

# ─── Check for Running Instance ───────────────────────────────────────

if [[ -f "$PID_FILE" ]]; then
  OLD_PID=$(cat "$PID_FILE" 2>/dev/null || echo "")
  if [[ -n "$OLD_PID" ]] && kill -0 "$OLD_PID" 2>/dev/null; then
    _cortex_log error "Watcher already running (PID: $OLD_PID)"
    exit 1
  else
    # Stale PID file
    rm -f "$PID_FILE"
  fi
fi

# ─── Detect File Watcher Tool ─────────────────────────────────────────

WATCHER=""
if command -v fswatch >/dev/null 2>&1; then
  WATCHER="fswatch"
elif command -v inotifywait >/dev/null 2>&1; then
  WATCHER="inotifywait"
else
  _cortex_log error "No file watcher found. Install fswatch (macOS) or inotify-tools (Linux)"
  echo ""
  echo "Installation:"
  if [[ "$(uname -s)" == "Darwin" ]]; then
    echo "  brew install fswatch"
  else
    echo "  sudo apt-get install -y inotify-tools"
  fi
  exit 1
fi

# ─── Exclusion Patterns ───────────────────────────────────────────────

# Directories to exclude (configurable)
EXCLUDE_DIRS=(
  ".git"
  ".cortex"
  "node_modules"
  ".next"
  "dist"
  "build"
  "target"
  ".venv"
  "venv"
  "__pycache__"
  ".cache"
  "tmp"
  "temp"
)

# File patterns to exclude
EXCLUDE_FILES=(
  "*.log"
  "*.lock"
  ".DS_Store"
  "*.swp"
  "*.tmp"
  "*~"
  ".*.swp"
)

# ─── Log Event ────────────────────────────────────────────────────────

log_event() {
  local event_type="$1"
  local file_path="$2"

  # Normalize path (relative to project)
  local rel_path="${file_path#"$PROJECT_DIR"/}"

  # Skip if file matches exclusion patterns (glob matching intentional)
  for pattern in "${EXCLUDE_FILES[@]}"; do
    # shellcheck disable=SC2053
    if [[ "$rel_path" == $pattern ]]; then
      return 0
    fi
  done

  # Skip if file is in excluded directory
  for dir in "${EXCLUDE_DIRS[@]}"; do
    if [[ "$rel_path" == "$dir"/* ]] || [[ "$rel_path" == "$dir" ]]; then
      return 0
    fi
  done

  # Create JSON event
  local ts
  ts=$(_cortex_date_iso)

  local event_json
  event_json=$(jq -n \
    --arg type "$event_type" \
    --arg path "$rel_path" \
    --arg ts "$ts" \
    '{type:$type,path:$path,ts:$ts}')

  # Append to events file (thread-safe)
  _cortex_safe_jsonl_append "$EVENTS_FILE" "$event_json"
}

# ─── Cleanup on Exit ──────────────────────────────────────────────────

cleanup() {
  rm -f "$PID_FILE"
  _cortex_log info "File watcher stopped"
  exit 0
}

trap cleanup SIGINT SIGTERM EXIT

# ─── Start Watching ───────────────────────────────────────────────────

# Save PID
echo $$ > "$PID_FILE"

_cortex_log info "File watcher started for $(basename "$PROJECT_DIR")"
_cortex_log info "Events logged to: $EVENTS_FILE"
_cortex_log info "Press Ctrl+C to stop"

if [[ "$DAEMON_MODE" == "true" ]]; then
  # Redirect output in daemon mode
  exec >/dev/null 2>&1
fi

# Build exclusion arguments
EXCLUDE_ARGS=()
for dir in "${EXCLUDE_DIRS[@]}"; do
  if [[ "$WATCHER" == "fswatch" ]]; then
    EXCLUDE_ARGS+=(--exclude "$PROJECT_DIR/$dir")
  else
    # inotifywait uses different syntax
    EXCLUDE_ARGS+=(--exclude "^$PROJECT_DIR/$dir(/.*)?$")
  fi
done

# Watch files
if [[ "$WATCHER" == "fswatch" ]]; then
  # macOS: fswatch
  fswatch \
    --recursive \
    --event Created \
    --event Updated \
    --event Removed \
    --event Renamed \
    --event MovedFrom \
    --event MovedTo \
    --exclude '\.git/' \
    --exclude '\.cortex/' \
    --exclude 'node_modules/' \
    --exclude '\.DS_Store$' \
    --exclude '\.swp$' \
    --exclude '\.log$' \
    "${EXCLUDE_ARGS[@]}" \
    "$PROJECT_DIR" | while read -r filepath; do
      # Determine event type based on file existence
      if [[ -f "$filepath" ]]; then
        log_event "modify" "$filepath"
      elif [[ -d "$filepath" ]]; then
        log_event "create" "$filepath"
      else
        log_event "delete" "$filepath"
      fi
    done
else
  # Linux: inotifywait
  inotifywait \
    --monitor \
    --recursive \
    --event create,modify,delete,move \
    --exclude '(\.git|\.cortex|node_modules|\.DS_Store|\.swp|\.log)' \
    --format '%e %w%f' \
    "$PROJECT_DIR" | while read -r event filepath; do
      case "$event" in
        CREATE*)    log_event "create" "$filepath" ;;
        MODIFY*)    log_event "modify" "$filepath" ;;
        DELETE*)    log_event "delete" "$filepath" ;;
        MOVED_TO*)  log_event "create" "$filepath" ;;
        MOVED_FROM*) log_event "delete" "$filepath" ;;
        *)          log_event "modify" "$filepath" ;;
      esac
    done
fi
