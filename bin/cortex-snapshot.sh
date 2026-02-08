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

cmd_undo() {
  # Remove the latest snapshot
  if [[ ! -L "$SNAPSHOTS_DIR/latest.snapshot" ]]; then
    _cortex_log error "No latest snapshot to undo"
    exit 1
  fi

  local target
  target=$(readlink "$SNAPSHOTS_DIR/latest.snapshot")
  local snapshot_id
  snapshot_id=$(basename "$target" .snapshot)

  read -r -p "Remove latest snapshot ($snapshot_id)? [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY])
      # Remove snapshot files
      rm -f "$SNAPSHOTS_DIR/${snapshot_id}.snapshot"
      rm -f "$SNAPSHOTS_DIR/${snapshot_id}.diff"
      rm -f "$SNAPSHOTS_DIR/${snapshot_id}.files"
      rm -f "$SNAPSHOTS_DIR/latest.snapshot"

      # Find previous snapshot and make it latest
      local prev_snapshot
      prev_snapshot=$(ls -t "$SNAPSHOTS_DIR"/*.snapshot 2>/dev/null | grep -v "latest.snapshot" | head -1)

      if [[ -n "$prev_snapshot" ]]; then
        ln -sf "$(basename "$prev_snapshot")" "$SNAPSHOTS_DIR/latest.snapshot"
        _cortex_log info "Removed $snapshot_id, reverted to $(basename "$prev_snapshot" .snapshot)"
      else
        _cortex_log info "Removed $snapshot_id (no more snapshots)"
      fi
      ;;
    *)
      echo "Cancelled"
      ;;
  esac
}

cmd_diff() {
  local snapshot_id="${1:-latest}"

  # Resolve "latest" to actual snapshot ID
  if [[ "$snapshot_id" == "latest" ]]; then
    if [[ -L "$SNAPSHOTS_DIR/latest.snapshot" ]]; then
      local target
      target=$(readlink "$SNAPSHOTS_DIR/latest.snapshot")
      snapshot_id=$(basename "$target" .snapshot)
    else
      _cortex_log error "No latest snapshot found"
      exit 1
    fi
  fi

  local snapshot_file="$SNAPSHOTS_DIR/${snapshot_id}.snapshot"

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

  # Display diff with color if possible
  if command -v bat >/dev/null 2>&1; then
    bat --language diff --paging=always "$SNAPSHOTS_DIR/$diff_file"
  elif command -v colordiff >/dev/null 2>&1; then
    colordiff < "$SNAPSHOTS_DIR/$diff_file" | less -R
  else
    cat "$SNAPSHOTS_DIR/$diff_file"
  fi
}

cmd_branch() {
  local snapshot_id="${1:-}"
  local branch_name="${2:-}"

  if [[ -z "$snapshot_id" ]] || [[ -z "$branch_name" ]]; then
    echo "Usage: cortex-snapshot.sh branch <snapshot-id> <branch-name>"
    exit 1
  fi

  # Resolve "latest" to actual snapshot ID
  if [[ "$snapshot_id" == "latest" ]]; then
    if [[ -L "$SNAPSHOTS_DIR/latest.snapshot" ]]; then
      local target
      target=$(readlink "$SNAPSHOTS_DIR/latest.snapshot")
      snapshot_id=$(basename "$target" .snapshot)
    else
      _cortex_log error "No latest snapshot found"
      exit 1
    fi
  fi

  local snapshot_file="$SNAPSHOTS_DIR/${snapshot_id}.snapshot"

  if [[ ! -f "$snapshot_file" ]]; then
    _cortex_log error "Snapshot not found: $snapshot_id"
    exit 1
  fi

  if ! _cortex_is_git_repo "$PROJECT_DIR"; then
    _cortex_log error "Not in a git repository"
    exit 1
  fi

  cd "$PROJECT_DIR"

  # Check if branch already exists
  if git show-ref --verify --quiet "refs/heads/$branch_name"; then
    _cortex_log error "Branch already exists: $branch_name"
    exit 1
  fi

  # Get current branch to restore later
  local current_branch
  current_branch=$(git branch --show-current 2>/dev/null || echo "")

  # Create new branch
  _cortex_log info "Creating branch: $branch_name"
  git checkout -b "$branch_name" 2>/dev/null || {
    _cortex_log error "Failed to create branch"
    exit 1
  }

  # Apply snapshot diff
  local diff_file
  diff_file=$(jq -r '.diff_file' "$snapshot_file")

  if [[ -f "$SNAPSHOTS_DIR/$diff_file" ]]; then
    if git apply "$SNAPSHOTS_DIR/$diff_file" 2>&1; then
      _cortex_log info "Snapshot applied to new branch: $branch_name"
      echo ""
      echo "📦 Snapshot restored to branch: $branch_name"
      echo "   • Commit changes: git add . && git commit -m '...'"
      echo "   • Return to previous branch: git checkout ${current_branch:-main}"
    else
      _cortex_log warn "Failed to apply snapshot. Conflicts may exist."
      echo "You're on branch $branch_name. Resolve conflicts manually or checkout back."
    fi
  else
    _cortex_log error "Diff file not found: $diff_file"
    [[ -n "$current_branch" ]] && git checkout "$current_branch" 2>/dev/null
    git branch -D "$branch_name" 2>/dev/null
    exit 1
  fi
}

cmd_search() {
  local query="${1:-}"

  if [[ -z "$query" ]]; then
    echo "Usage: cortex-snapshot.sh search <keyword>"
    echo "Search snapshots by content or file names"
    exit 1
  fi

  if [[ ! -d "$SNAPSHOTS_DIR" ]]; then
    echo "No snapshots directory"
    return 0
  fi

  echo "🔍 Searching snapshots for: $query"
  echo ""

  local found=0

  for snapshot in "$SNAPSHOTS_DIR"/*.snapshot; do
    [[ "$snapshot" == *"latest.snapshot" ]] && continue
    [[ ! -f "$snapshot" ]] && continue

    local sid
    sid=$(basename "$snapshot" .snapshot)

    # Search in metadata
    local metadata_match=false
    if grep -qi "$query" "$snapshot" 2>/dev/null; then
      metadata_match=true
    fi

    # Search in diff content
    local diff_file="$SNAPSHOTS_DIR/${sid}.diff"
    local diff_match=false
    if [[ -f "$diff_file" ]] && grep -qi "$query" "$diff_file" 2>/dev/null; then
      diff_match=true
    fi

    # Search in file list
    local files_file="$SNAPSHOTS_DIR/${sid}.files"
    local files_match=false
    if [[ -f "$files_file" ]] && grep -qi "$query" "$files_file" 2>/dev/null; then
      files_match=true
    fi

    # If any match, display snapshot
    if [[ "$metadata_match" == "true" ]] || [[ "$diff_match" == "true" ]] || [[ "$files_match" == "true" ]]; then
      found=$((found + 1))

      # Read snapshot metadata
      local ts
      ts=$(jq -r '.timestamp // "unknown"' "$snapshot" 2>/dev/null || echo "unknown")
      local files_count
      files_count=$(jq -r '.uncommitted_files // 0' "$snapshot" 2>/dev/null || echo "0")

      echo "📦 $sid"
      echo "   Time: $ts"
      echo "   Files: $files_count"

      # Show match context
      if [[ "$diff_match" == "true" ]]; then
        echo "   Match in: diff content"
        # Show a few lines of context
        grep -i -A 2 -B 2 "$query" "$diff_file" 2>/dev/null | head -10 | sed 's/^/      /'
      elif [[ "$files_match" == "true" ]]; then
        echo "   Match in: file names"
        grep -i "$query" "$files_file" 2>/dev/null | head -5 | sed 's/^/      /'
      fi
      echo ""
    fi
  done

  if [[ $found -eq 0 ]]; then
    echo "No snapshots found matching: $query"
  else
    echo "Found $found snapshot(s)"
  fi
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
  undo)
    cmd_undo
    ;;
  diff)
    cmd_diff "$@"
    ;;
  branch)
    cmd_branch "$@"
    ;;
  search)
    cmd_search "$@"
    ;;
  *)
    echo "Cortex Snapshot Manager"
    echo ""
    echo "Usage: cortex-snapshot.sh {capture|list|show|restore|clear|undo|diff|branch|search} [args]"
    echo ""
    echo "Commands:"
    echo "  capture [session-id]  - Capture current uncommitted work"
    echo "  list                  - List all snapshots"
    echo "  show [snapshot-id]    - Show snapshot details (default: latest)"
    echo "  restore [snapshot-id] - Restore snapshot to working tree"
    echo "  clear [days]          - Remove snapshots older than N days (default: 7)"
    echo "  undo                  - Remove latest snapshot"
    echo "  diff [snapshot-id]    - Show diff for a snapshot (default: latest)"
    echo "  branch <id> <name>    - Create new branch from snapshot"
    echo "  search <keyword>      - Search snapshots by content or file names"
    echo ""
    echo "Examples:"
    echo "  cortex-snapshot.sh capture"
    echo "  cortex-snapshot.sh list"
    echo "  cortex-snapshot.sh show latest"
    echo "  cortex-snapshot.sh restore 20260208-1030"
    echo "  cortex-snapshot.sh clear 14"
    echo "  cortex-snapshot.sh undo"
    echo "  cortex-snapshot.sh diff latest"
    echo "  cortex-snapshot.sh branch latest feature/new-ui"
    echo "  cortex-snapshot.sh search 'authentication'"
    echo ""
    exit 1
    ;;
esac
