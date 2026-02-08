#!/usr/bin/env bash
# cx-note — Quick session notes for AI context
# Usage: cx-note [add|list|show|clear] [note text]
# Notes are stored in .cortex/notes.jsonl and included in SESSION_CONTEXT.md

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
NOTES_FILE="$CORTEX_DIR/notes.jsonl"

mkdir -p "$CORTEX_DIR"

# ─── Commands ─────────────────────────────────────────────────────────

cmd_add() {
  local note_text="$*"

  # Validate note is not empty or whitespace-only
  if [[ -z "$note_text" ]] || [[ -z "${note_text// /}" ]]; then
    echo "Usage: cx-note add <note text>"
    echo "Example: cx-note add 'Remember to test the auth flow'"
    echo "Error: Note cannot be empty"
    exit 1
  fi

  # Create note entry
  local ts
  ts=$(_cortex_date_iso)

  if command -v jq >/dev/null 2>&1; then
    local note_json
    note_json=$(jq -n -c \
      --arg ts "$ts" \
      --arg note "$note_text" \
      '{timestamp:$ts,note:$note}')
    echo "$note_json" >> "$NOTES_FILE"
  else
    # Fallback: simple JSON without jq
    echo "{\"timestamp\":\"$ts\",\"note\":\"$note_text\"}" >> "$NOTES_FILE"
  fi

  _cortex_log info "Note added"
  echo "📝 Note saved: $note_text"
}

cmd_list() {
  if [[ ! -f "$NOTES_FILE" ]] || [[ ! -s "$NOTES_FILE" ]]; then
    echo "No notes yet. Add one with: cx-note add '<text>'"
    return 0
  fi

  echo "📝 Session Notes:"
  echo ""

  local count=1
  while IFS= read -r line; do
    if command -v jq >/dev/null 2>&1; then
      local ts
      ts=$(echo "$line" | jq -r '.timestamp // "unknown"' 2>/dev/null || echo "unknown")
      local note
      note=$(echo "$line" | jq -r '.note // ""' 2>/dev/null || echo "")

      if [[ -n "$note" ]]; then
        echo "$count. [$ts]"
        echo "   $note"
        echo ""
        count=$((count + 1))
      fi
    else
      echo "$count. $line"
      count=$((count + 1))
    fi
  done < "$NOTES_FILE"
}

cmd_show() {
  local note_num="${1:-}"

  if [[ -z "$note_num" ]]; then
    echo "Usage: cx-note show <number>"
    echo "See note numbers with: cx-note list"
    exit 1
  fi

  if [[ ! -f "$NOTES_FILE" ]]; then
    echo "No notes yet"
    exit 1
  fi

  local line
  line=$(sed -n "${note_num}p" "$NOTES_FILE" 2>/dev/null)

  if [[ -z "$line" ]]; then
    echo "Note #$note_num not found"
    exit 1
  fi

  if command -v jq >/dev/null 2>&1; then
    local ts
    ts=$(echo "$line" | jq -r '.timestamp // "unknown"')
    local note
    note=$(echo "$line" | jq -r '.note // ""')

    echo "📝 Note #$note_num"
    echo "Time: $ts"
    echo ""
    echo "$note"
  else
    echo "$line"
  fi
}

cmd_clear() {
  if [[ ! -f "$NOTES_FILE" ]]; then
    echo "No notes to clear"
    return 0
  fi

  local count
  count=$(wc -l < "$NOTES_FILE" | tr -d ' ')

  read -r -p "Delete all $count notes? [y/N] " response
  case "$response" in
    [yY][eE][sS]|[yY])
      rm -f "$NOTES_FILE"
      _cortex_log info "All notes cleared"
      echo "🗑️  Cleared $count notes"
      ;;
    *)
      echo "Cancelled"
      ;;
  esac
}

cmd_export() {
  if [[ ! -f "$NOTES_FILE" ]] || [[ ! -s "$NOTES_FILE" ]]; then
    echo "No notes to export"
    return 0
  fi

  local export_file="$PROJECT_DIR/SESSION_NOTES.md"

  {
    echo "# Session Notes"
    echo ""
    echo "**Generated:** $(_cortex_date_iso)"
    echo ""

    while IFS= read -r line; do
      if command -v jq >/dev/null 2>&1; then
        local ts
        ts=$(echo "$line" | jq -r '.timestamp // "unknown"' 2>/dev/null || echo "unknown")
        local note
        note=$(echo "$line" | jq -r '.note // ""' 2>/dev/null || echo "")

        if [[ -n "$note" ]]; then
          echo "- **$ts**: $note"
        fi
      fi
    done < "$NOTES_FILE"
  } > "$export_file"

  echo "📄 Notes exported to SESSION_NOTES.md"
}

# ─── Main ─────────────────────────────────────────────────────────────

COMMAND="${1:-list}"
shift || true

case "$COMMAND" in
  add|a)
    cmd_add "$@"
    ;;
  list|ls|l)
    cmd_list
    ;;
  show|s)
    cmd_show "$@"
    ;;
  clear|c)
    cmd_clear
    ;;
  export|e)
    cmd_export
    ;;
  *)
    echo "cx-note — Quick session notes for AI context"
    echo ""
    echo "Usage: cx-note {add|list|show|clear|export} [args]"
    echo ""
    echo "Commands:"
    echo "  add <text>    - Add a new note"
    echo "  list          - List all notes (default)"
    echo "  show <number> - Show specific note"
    echo "  clear         - Delete all notes"
    echo "  export        - Export notes to SESSION_NOTES.md"
    echo ""
    echo "Examples:"
    echo "  cx-note add 'Test the login flow with edge cases'"
    echo "  cx-note list"
    echo "  cx-note show 1"
    echo "  cx-note export"
    exit 1
    ;;
esac
