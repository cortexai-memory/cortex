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

  _cortex_log info "Session ended. Context saved."
  return $exit_code
}
trap cleanup EXIT

# ─── Launch Claude Code ──────────────────────────────────────────────

if ! command -v claude >/dev/null 2>&1; then
  _cortex_log error "'claude' command not found. Install Claude Code CLI first."
  _cortex_log error "  See: https://docs.anthropic.com/en/docs/claude-code"
  exit 1
fi

claude "$@"
