#!/usr/bin/env bash
# Cortex Session Manager — aliased to 'cx'
# Usage: cx [any claude arguments]
# Lifecycle: init → generate context → log start → launch claude → log end

set -uo pipefail

# Source shared utilities
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/_cortex-utils.sh
source "$SCRIPT_DIR/_cortex-utils.sh" 2>/dev/null || \
  source "$CORTEX_HOME/bin/_cortex-utils.sh" 2>/dev/null || {
    echo "[Cortex] Error: Cannot find _cortex-utils.sh" >&2
    exit 1
  }

# ─── Detect Project ──────────────────────────────────────────────────

PROJECT_DIR="$(_cortex_project_root)"
CORTEX_DIR="$PROJECT_DIR/.cortex"
PROJECT_NAME=$(basename "$PROJECT_DIR")

# ─── Auto-Initialize for New Projects ────────────────────────────────

if [[ ! -d "$CORTEX_DIR" ]]; then
  _cortex_log info "First time in $PROJECT_NAME. Initializing..."
  mkdir -p "$CORTEX_DIR"

  # Install git hook (append, never replace)
  if _cortex_is_git_repo "$PROJECT_DIR"; then
    HOOK="$PROJECT_DIR/.git/hooks/post-commit"
    MARKER="# --- cortex-hook-v1 ---"
    TEMPLATE="$CORTEX_HOME/templates/post-commit.sh"

    if [[ -f "$TEMPLATE" ]]; then
      if [[ ! -f "$HOOK" ]] || ! grep -q "$MARKER" "$HOOK" 2>/dev/null; then
        # Append cortex hook (preserve existing hooks)
        # shellcheck disable=SC2094
        [[ -f "$HOOK" ]] && printf '\n' >> "$HOOK"
        cat "$TEMPLATE" >> "$HOOK"
        chmod +x "$HOOK"
        _cortex_log info "Git hook installed."
      fi
    fi
  fi

  # Add .cortex/ to .gitignore (idempotent)
  GITIGNORE="$PROJECT_DIR/.gitignore"
  if [[ -f "$GITIGNORE" ]]; then
    if ! grep -q '\.cortex/' "$GITIGNORE" 2>/dev/null; then
      {
        echo ""
        echo "# Cortex (local AI memory)"
        echo ".cortex/"
        echo "SESSION_CONTEXT.md"
      } >> "$GITIGNORE"
    fi
  else
    cat > "$GITIGNORE" << 'EOF'
# Cortex (local AI memory)
.cortex/
SESSION_CONTEXT.md
EOF
  fi

  # Register project globally
  mkdir -p "$CORTEX_HOME"
  local_ts=$(_cortex_date_iso)
  if command -v jq >/dev/null 2>&1; then
    REG_LINE=$(jq -n -c \
      --arg name "$PROJECT_NAME" \
      --arg path "$PROJECT_DIR" \
      --arg init "$local_ts" \
      '{name:$name,path:$path,init:$init}')
  else
    REG_LINE="{\"name\":\"$PROJECT_NAME\",\"path\":\"$PROJECT_DIR\",\"init\":\"$local_ts\"}"
  fi

  # Don't duplicate registrations
  if [[ ! -f "$CORTEX_HOME/registry.jsonl" ]] || ! grep -q "\"$PROJECT_DIR\"" "$CORTEX_HOME/registry.jsonl" 2>/dev/null; then
    echo "$REG_LINE" >> "$CORTEX_HOME/registry.jsonl"
  fi

  _cortex_log info "Initialized in $PROJECT_NAME."
fi

# ─── Auto-Restore Prompt (B3.1) ───────────────────────────────────────

# Check for uncommitted snapshot from previous session
SNAPSHOTS_DIR="$CORTEX_DIR/snapshots"
LATEST_SNAPSHOT="$SNAPSHOTS_DIR/latest.snapshot"

if [[ -f "$LATEST_SNAPSHOT" ]]; then
  # Read snapshot metadata
  if command -v jq >/dev/null 2>&1; then
    SNAPSHOT_FILES=$(jq -r '.uncommitted_files // 0' "$LATEST_SNAPSHOT" 2>/dev/null || echo "0")
    SNAPSHOT_TS=$(jq -r '.timestamp // ""' "$LATEST_SNAPSHOT" 2>/dev/null || echo "")
    SNAPSHOT_ID=$(jq -r '.session_id // "unknown"' "$LATEST_SNAPSHOT" 2>/dev/null || echo "unknown")

    if [[ "$SNAPSHOT_FILES" -gt 0 ]]; then
      echo ""
      echo "📦 Previous session snapshot detected"
      echo "   Session: $SNAPSHOT_ID"
      echo "   Files: $SNAPSHOT_FILES uncommitted"
      echo "   Time: $SNAPSHOT_TS"
      echo ""

      # Prompt user
      if [[ -t 0 ]]; then
        read -r -p "Continue from previous session? [y/N] " response
      else
        response="n"
      fi
      case "$response" in
        [yY][eE][sS]|[yY])
          _cortex_log info "Restoring snapshot..."
          SNAPSHOT_SCRIPT="$SCRIPT_DIR/cortex-snapshot.sh"
          [[ ! -f "$SNAPSHOT_SCRIPT" ]] && SNAPSHOT_SCRIPT="$CORTEX_HOME/bin/cortex-snapshot.sh"

          if [[ -f "$SNAPSHOT_SCRIPT" ]]; then
            "$SNAPSHOT_SCRIPT" restore "$SNAPSHOT_ID" 2>/dev/null || {
              _cortex_log warn "Snapshot restore failed. Continuing with current state."
            }
          else
            _cortex_log warn "cortex-snapshot.sh not found. Continuing with current state."
          fi

          # Clear the snapshot after restore so we don't prompt again
          rm -f "$LATEST_SNAPSHOT" 2>/dev/null || true
          _cortex_log info "Snapshot restored. Previous work is now in your working directory."
          echo ""
          ;;
        *)
          _cortex_log info "Starting fresh session (snapshot preserved)"
          echo ""
          ;;
      esac
    fi
  fi
fi

# ─── Generate Fresh Context ──────────────────────────────────────────

CONTEXT_SCRIPT="$SCRIPT_DIR/cortex-context.sh"
[[ ! -f "$CONTEXT_SCRIPT" ]] && CONTEXT_SCRIPT="$CORTEX_HOME/bin/cortex-context.sh"

if [[ -f "$CONTEXT_SCRIPT" ]]; then
  "$CONTEXT_SCRIPT" "$PROJECT_DIR" 2>/dev/null || {
    _cortex_log warn "Context generation failed. Launching without context."
  }
else
  _cortex_log warn "cortex-context.sh not found. Launching without context."
fi

# ─── Session Summary Generator (B2.1) ────────────────────────────────

generate_session_summary() {
  # Generate AI summary of what was accomplished in this session

  if ! command -v jq >/dev/null 2>&1; then
    return 0  # Skip if jq not available
  fi

  # Calculate session duration
  local duration_sec=0
  if [[ -n "${START_TS:-}" ]]; then
    local now_epoch
    now_epoch=$(date +%s)
    local start_epoch
    if date -j -f "%Y-%m-%dT%H:%M:%SZ" "$START_TS" +%s >/dev/null 2>&1; then
      # macOS
      start_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$START_TS" +%s 2>/dev/null || echo "$now_epoch")
    else
      # Linux
      start_epoch=$(date -d "$START_TS" +%s 2>/dev/null || echo "$now_epoch")
    fi
    duration_sec=$((now_epoch - start_epoch))
  fi

  local duration_min=$((duration_sec / 60))

  # Gather session data
  local commits_made=""
  if _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR"; then
    commits_made=$(git log --oneline --since="$START_TS" 2>/dev/null | head -10)
  fi

  local files_changed=""
  if _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR"; then
    files_changed=$(git diff --name-only "$START_TS" 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')
  fi

  local notes_taken=""
  if [[ -f "$CORTEX_DIR/notes.jsonl" ]]; then
    notes_taken=$(tail -5 "$CORTEX_DIR/notes.jsonl" | jq -r '.note // ""' 2>/dev/null | tr '\n' ' ' || true)
  fi

  # Create summary
  echo ""
  echo "📊 Session Summary"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "   Duration: ${duration_min} minutes"

  if [[ -n "$commits_made" ]]; then
    local commit_count
    commit_count=$(echo "$commits_made" | wc -l | tr -d ' ')
    echo "   Commits: $commit_count"
    echo "$commits_made" | sed 's/^/      /'
  else
    echo "   Commits: 0"
  fi

  if [[ -n "$notes_taken" ]]; then
    echo "   Notes: Yes"
  fi

  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo ""

  # Save session summary to file for future reference
  local summary_file="$CORTEX_DIR/summaries/sessions/${SESSION_ID}.md"
  mkdir -p "$CORTEX_DIR/summaries/sessions"

  cat > "$summary_file" << SUMMEOF
# Session Summary

**Session ID:** $SESSION_ID
**Started:** $START_TS
**Duration:** ${duration_min} minutes

## What Was Accomplished

${commits_made:-No commits made}

## Files Changed

${files_changed:-No files changed}

## Notes

${notes_taken:-No notes taken}

SUMMEOF

  _cortex_log info "Session summary saved to .cortex/summaries/sessions/${SESSION_ID}.md"
}

# ─── Session Tracking ────────────────────────────────────────────────

SESSION_ID=$(_cortex_uuid)
START_TS=$(_cortex_date_iso)

# Log session start (append-only, never modify existing lines)
if command -v jq >/dev/null 2>&1; then
  START_EVENT=$(jq -n -c \
    --arg type "start" \
    --arg sid "$SESSION_ID" \
    --arg ts "$START_TS" \
    --arg project "$PROJECT_NAME" \
    '{type:$type,sid:$sid,ts:$ts,project:$project}')
else
  START_EVENT="{\"type\":\"start\",\"sid\":\"$SESSION_ID\",\"ts\":\"$START_TS\",\"project\":\"$PROJECT_NAME\"}"
fi
_cortex_safe_jsonl_append "$CORTEX_DIR/sessions.jsonl" "$START_EVENT"

# ─── Signal Handling (Ctrl+C, kill, normal exit) ─────────────────────

cleanup() {
  local exit_code=$?
  local END_TS
  END_TS=$(_cortex_date_iso)

  # Log session end
  if command -v jq >/dev/null 2>&1; then
    END_EVENT=$(jq -n -c \
      --arg type "end" \
      --arg sid "$SESSION_ID" \
      --arg ts "$END_TS" \
      '{type:$type,sid:$sid,ts:$ts}')
  else
    END_EVENT="{\"type\":\"end\",\"sid\":\"$SESSION_ID\",\"ts\":\"$END_TS\"}"
  fi
  _cortex_safe_jsonl_append "$CORTEX_DIR/sessions.jsonl" "$END_EVENT"

  # Optional async enrichment
  if [[ "${CORTEX_ENRICH:-0}" == "1" ]] && [[ -f "$CORTEX_HOME/bin/cortex-enrich.sh" ]]; then
    nohup "$CORTEX_HOME/bin/cortex-enrich.sh" "$PROJECT_DIR" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi

  # Check for uncommitted work and create snapshot
  if _cortex_is_git_repo "$PROJECT_DIR"; then
    cd "$PROJECT_DIR" || return
    local uncommitted
    uncommitted=$(git status --porcelain 2>/dev/null | wc -l | tr -d ' ')

    if [[ "$uncommitted" -gt 0 ]]; then
      echo ""
      _cortex_log warn "You have $uncommitted uncommitted file(s)"

      # Auto-capture snapshot
      if command -v cortex-snapshot.sh >/dev/null 2>&1 || [[ -f "$SCRIPT_DIR/cortex-snapshot.sh" ]]; then
        _cortex_log info "Saving session snapshot..."
        "$SCRIPT_DIR/cortex-snapshot.sh" capture "$SESSION_ID" 2>/dev/null || \
          "$CORTEX_HOME/bin/cortex-snapshot.sh" capture "$SESSION_ID" 2>/dev/null || true

        echo ""
        echo "💡 Your work is saved in a snapshot"
        echo "   • Continue next session: Just run 'cx' again"
        echo "   • Commit changes: git add . && git commit -m \"...\""
        echo "   • View snapshots: cortex-snapshot.sh list"
      fi
    fi
  fi

  # Generate AI session summary (B2.1) if enrichment enabled
  if [[ "${CORTEX_ENRICH:-0}" == "1" ]]; then
    generate_session_summary
  fi

  _cortex_log info "Session ended. Context saved."
  return $exit_code
}
trap cleanup EXIT INT TERM

# ─── Launch Claude Code ──────────────────────────────────────────────

if ! command -v claude >/dev/null 2>&1; then
  _cortex_log error "'claude' command not found. Install Claude Code CLI first."
  _cortex_log error "  See: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi

claude "$@"
