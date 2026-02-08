#!/usr/bin/env bash
# Cortex Snapshot — Capture and manage uncommitted work state
# Usage: cortex-snapshot.sh {capture|list|show|restore|clear} [args]

set -euo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/_cortex-utils.sh
source "$SCRIPT_DIR/_cortex-utils.sh" 2>/dev/null || \
  source "$CORTEX_HOME/bin/_cortex-utils.sh" 2>/dev/null || {
    echo "[Cortex] Error: Cannot find _cortex-utils.sh" >&2
    exit 1
  }

# ─── Setup ────────────────────────────────────────────────────────────

PROJECT_DIR="$(_cortex_project_root)"
CORTEX_DIR="$PROJECT_DIR/.cortex"
SNAPSHOTS_DIR="$CORTEX_DIR/snapshots"

mkdir -p "$SNAPSHOTS_DIR"

# ─── Helper Functions ─────────────────────────────────────────────────

calculate_time_ago() {
  local snapshot_ts="$1"
  local now_ts
  now_ts=$(date +%s)

  # Parse ISO timestamp to epoch (cross-platform)
  local snap_epoch
  if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$snapshot_ts" +%s >/dev/null 2>&1; then
    # macOS
    snap_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$snapshot_ts" +%s 2>/dev/null || echo "$now_ts")
  else
    # Linux
    snap_epoch=$(date -d "$snapshot_ts" +%s 2>/dev/null || echo "$now_ts")
  fi

  local diff=$((now_ts - snap_epoch))

  if [[ $diff -lt 60 ]]; then
    echo "${diff}s ago"
  elif [[ $diff -lt 3600 ]]; then
    echo "$((diff / 60))m ago"
  elif [[ $diff -lt 86400 ]]; then
    echo "$((diff / 3600))h ago"
  else
    echo "$((diff / 86400))d ago"
  fi
}

# ─── Commands ─────────────────────────────────────────────────────────

cmd_capture() {
  local session_id="${1:-$(date +%Y%m%d-%H%M%S)}"

  # Check if in git repo
  if ! _cortex_is_git_repo "$PROJECT_DIR"; then
    _cortex_log error "Not in a git repository"
    exit 1
  fi

  cd "$PROJECT_DIR"

  # Check for uncommitted work
  if [[ -z "$(git status --porcelain 2>/dev/null)" ]]; then
    _cortex_log info "No uncommitted work to snapshot"
    return 0
  fi

  # Generate snapshot ID
  local snapshot_id="$session_id"
  local snapshot_file="$SNAPSHOTS_DIR/${snapshot_id}.snapshot"
  local diff_file="$SNAPSHOTS_DIR/${snapshot_id}.diff"
  local files_file="$SNAPSHOTS_DIR/${snapshot_id}.files"

  # Capture diff
  git diff HEAD > "$diff_file" 2>/dev/null || true
  git diff --cached HEAD >> "$diff_file" 2>/dev/null || true

  # Capture file list
  git status --porcelain > "$files_file" 2>/dev/null || true

  # Count files
  local file_count
  file_count=$(wc -l < "$files_file" | tr -d ' ')

  # Generate summary (first 3 modified files)
  local summary
  summary=$(head -3 "$files_file" | sed 's/^...//; s/^/- /' | paste -sd '; ' -)
  if [[ "$file_count" -gt 3 ]]; then
    summary="$summary; and $((file_count - 3)) more"
  fi

  # Create metadata
  local metadata
  metadata=$(jq -n \
    --arg ts "$(_cortex_date_iso)" \
    --arg sid "$snapshot_id" \
    --argjson count "$file_count" \
    --arg summary "$summary" \
    '{
      timestamp: $ts,
      session_id: $sid,
      uncommitted_files: $count,
      summary: $summary,
      diff_file: "\($sid).diff",
      files_file: "\($sid).files"
    }')

  echo "$metadata" > "$snapshot_file"

  # Update latest symlink
  ln -sf "$snapshot_file" "$SNAPSHOTS_DIR/latest.snapshot"

  _cortex_log info "Snapshot saved: $snapshot_id ($file_count files)"
}

cmd_list() {
  if [[ ! -d "$SNAPSHOTS_DIR" ]] || [[ -z "$(ls -A "$SNAPSHOTS_DIR"/*.snapshot 2>/dev/null)" ]]; then
    echo "No snapshots found"
    return 0
  fi

  echo "Session Snapshots:"
  echo "──────────────────────────────────────────────────────────"

  for snapshot in "$SNAPSHOTS_DIR"/*.snapshot; do
    [[ "$snapshot" == *"latest.snapshot" ]] && continue
    [[ ! -f "$snapshot" ]] && continue

    local sid
    sid=$(basename "$snapshot" .snapshot)
    local ts files summary time_ago

    ts=$(jq -r '.timestamp' "$snapshot" 2>/dev/null || echo "unknown")
    files=$(jq -r '.uncommitted_files' "$snapshot" 2>/dev/null || echo "0")
    summary=$(jq -r '.summary' "$snapshot" 2>/dev/null || echo "")
    time_ago=$(calculate_time_ago "$ts")

    printf "%-20s  %6s  %-8s  %s\n" "$sid" "$files files" "$time_ago" "$summary"
  done
}

cmd_show() {
  local snapshot_id="${1:-latest}"
  local snapshot_file

  if [[ "$snapshot_id" == "latest" ]]; then
    snapshot_file="$SNAPSHOTS_DIR/latest.snapshot"
  else
    snapshot_file="$SNAPSHOTS_DIR/${snapshot_id}.snapshot"
  fi

  if [[ ! -f "$snapshot_file" ]]; then
    _cortex_log error "Snapshot not found: $snapshot_id"
    exit 1
  fi

  # Show metadata
  echo "Snapshot Details:"
  echo "──────────────────────────────────────────────────────────"
  jq -r '
    "Session ID:    \(.session_id)",
    "Timestamp:     \(.timestamp)",
    "Files:         \(.uncommitted_files)",
    "Summary:       \(.summary)"
  ' "$snapshot_file"

  echo ""
  echo "Modified Files:"
  echo "──────────────────────────────────────────────────────────"

  local files_file
  files_file=$(jq -r '.files_file' "$snapshot_file")

  if [[ -f "$SNAPSHOTS_DIR/$files_file" ]]; then
    cat "$SNAPSHOTS_DIR/$files_file"
  else
    echo "(file list not found)"
  fi

  echo ""
  echo "To see full diff: git diff or view $SNAPSHOTS_DIR/$(jq -r '.diff_file' "$snapshot_file")"
}

cmd_restore() {
  local snapshot_id="${1:-latest}"
  local snapshot_file

  if [[ "$snapshot_id" == "latest" ]]; then
    snapshot_file="$SNAPSHOTS_DIR/latest.snapshot"
  else
    snapshot_file="$SNAPSHOTS_DIR/${snapshot_id}.snapshot"
  fi

  if [[ ! -f "$snapshot_file" ]]; then
    _cortex_log error "Snapshot not found: $snapshot_id"
    exit 1
  fi

  local diff_file
  diff_file=$(jq -r '.diff_file' "$snapshot_file")

  if [[ ! -f "$SNAPSHOTS_DIR/$diff_file" ]]; then
    _cortex_log error "Diff file not found: $diff_file"
    exit 1
  fi

  _cortex_log warn "This will apply the snapshot diff. Current changes may be overwritten."
  read -p "Continue? [y/N] " -n 1 -r
  echo

  if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "Aborted"
    exit 0
  fi

  cd "$PROJECT_DIR"
  if git apply "$SNAPSHOTS_DIR/$diff_file" 2>&1; then
    _cortex_log info "Snapshot restored: $snapshot_id"
  else
    _cortex_log error "Failed to apply snapshot. Conflicts may exist."
    exit 1
  fi
}

cmd_clear() {
  local older_than_days="${1:-7}"

  if [[ ! -d "$SNAPSHOTS_DIR" ]]; then
    echo "No snapshots directory"
    return 0
  fi

  local cutoff_ts
  cutoff_ts=$(date -u -d "$older_than_days days ago" +%FT%TZ 2>/dev/null || date -u -v-"${older_than_days}d" +%FT%TZ 2>/dev/null || echo "")

  if [[ -z "$cutoff_ts" ]]; then
    _cortex_log error "Failed to calculate cutoff date"
    exit 1
  fi

  local removed=0

  for snapshot in "$SNAPSHOTS_DIR"/*.snapshot; do
    [[ "$snapshot" == *"latest.snapshot" ]] && continue
    [[ ! -f "$snapshot" ]] && continue

    local ts
    ts=$(jq -r '.timestamp' "$snapshot" 2>/dev/null || echo "")

    if [[ -n "$ts" ]] && [[ "$ts" < "$cutoff_ts" ]]; then
      local sid
      sid=$(jq -r '.session_id' "$snapshot")

      rm -f "$snapshot"
      rm -f "$SNAPSHOTS_DIR/${sid}.diff"
      rm -f "$SNAPSHOTS_DIR/${sid}.files"

      removed=$((removed + 1))
    fi
  done

  _cortex_log info "Removed $removed old snapshots (older than $older_than_days days)"
}

# ─── Main ─────────────────────────────────────────────────────────────

COMMAND="${1:-}"
shift || true

case "$COMMAND" in
  capture)
    cmd_capture "$@"
    ;;
  list|ls)
    cmd_list
    ;;
  show)
    cmd_show "$@"
    ;;
  restore)
    cmd_restore "$@"
    ;;
  clear)
    cmd_clear "$@"
    ;;
  *)
    echo "Cortex Snapshot Manager"
    echo ""
    echo "Usage: cortex-snapshot.sh {capture|list|show|restore|clear} [args]"
    echo ""
    echo "Commands:"
    echo "  capture [session-id]  - Capture current uncommitted work"
    echo "  list                  - List all snapshots"
    echo "  show [snapshot-id]    - Show snapshot details (default: latest)"
    echo "  restore [snapshot-id] - Restore snapshot to working tree"
    echo "  clear [days]          - Remove snapshots older than N days (default: 7)"
    echo ""
    echo "Examples:"
    echo "  cortex-snapshot.sh capture"
    echo "  cortex-snapshot.sh list"
    echo "  cortex-snapshot.sh show latest"
    echo "  cortex-snapshot.sh restore 20260208-1030"
    echo "  cortex-snapshot.sh clear 14"
    echo ""
    exit 1
    ;;
esac
