#!/usr/bin/env bash
# Cortex Status — User-facing status dashboard
# Dependencies: bash, git, jq
# Usage: cortex-status.sh [--json]

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

JSON_OUTPUT=false
if [[ "${1:-}" == "--json" ]]; then
  JSON_OUTPUT=true
fi

# ─── Setup ────────────────────────────────────────────────────────────

PROJECT_DIR="$(_cortex_project_root)"
CORTEX_DIR="$PROJECT_DIR/.cortex"
COMMITS_FILE="$CORTEX_DIR/commits.jsonl"
SESSIONS_FILE="$CORTEX_DIR/sessions.jsonl"

# ─── Collect Data ─────────────────────────────────────────────────────

PROJECT_NAME=$(basename "$PROJECT_DIR")

# Git info
BRANCH="not a git repo"
LAST_COMMIT="no commits"
UNCOMMITTED=0

if _cortex_is_git_repo "$PROJECT_DIR"; then
  HAS_COMMITS=true
  cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1 || HAS_COMMITS=false

  if [[ "$HAS_COMMITS" == "true" ]]; then
    BRANCH=$(cd "$PROJECT_DIR" && git branch --show-current 2>/dev/null)
    if [[ -z "$BRANCH" ]]; then
      local_head=$(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
      BRANCH="DETACHED@$local_head"
    fi
    LAST_COMMIT=$(cd "$PROJECT_DIR" && git log -1 --format='%h %s (%ar)' 2>/dev/null || echo "no commits")
  else
    BRANCH=$(cd "$PROJECT_DIR" && git branch --show-current 2>/dev/null || echo "main")
    LAST_COMMIT="no commits yet"
  fi

  UNCOMMITTED=$(cd "$PROJECT_DIR" && git status --porcelain 2>/dev/null | wc -l | tr -d ' ')
fi

# Recent commits (last 5)
RECENT_COMMITS=""
if [[ -f "$COMMITS_FILE" ]]; then
  RECENT_COMMITS=$(jq -r '"  \(.h) \(.m) (+\(.i)/-\(.d)) \(.t // "" | split("T")[0])"' "$COMMITS_FILE" 2>/dev/null | tail -5 || true)
elif _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1; then
  RECENT_COMMITS=$(cd "$PROJECT_DIR" && git log --oneline -5 2>/dev/null | sed 's/^/  /' || true)
fi
[[ -z "$RECENT_COMMITS" ]] && RECENT_COMMITS="  No commits tracked yet"

# Memory usage
COMMIT_COUNT=0
SESSION_COUNT=0
STORAGE_SIZE="0 KB"
OLDEST_COMMIT="N/A"

if [[ -d "$CORTEX_DIR" ]]; then
  STORAGE_SIZE=$(du -sh "$CORTEX_DIR" 2>/dev/null | awk '{print $1}' || echo "0 KB")

  if [[ -f "$COMMITS_FILE" ]]; then
    COMMIT_COUNT=$(wc -l < "$COMMITS_FILE" 2>/dev/null | tr -d ' ' || echo 0)
    if [[ "$COMMIT_COUNT" -gt 0 ]]; then
      OLDEST_COMMIT=$(head -1 "$COMMITS_FILE" 2>/dev/null | jq -r '.t // "N/A"' 2>/dev/null | cut -d'T' -f1 || echo "N/A")
    fi
  fi

  if [[ -f "$SESSIONS_FILE" ]]; then
    SESSION_COUNT=$(grep -c '"type":"start"' "$SESSIONS_FILE" 2>/dev/null || echo 0)
  fi
fi

# Current task
CURRENT_TASK="No task tracker found"
if [[ -f "$PROJECT_DIR/PROJECT_STATE.md" ]]; then
  CURRENT_TASK=$(grep -A2 -E 'Current|In Progress|Active' "$PROJECT_DIR/PROJECT_STATE.md" 2>/dev/null | head -3 | sed 's/^/  /' || echo "  See PROJECT_STATE.md")
elif [[ -f "$PROJECT_DIR/features.json" ]]; then
  TASK_NAME=$(jq -r '[.. | objects | select(.status=="pending" or .passes==false)] | first | .name // "No pending tasks"' "$PROJECT_DIR/features.json" 2>/dev/null || echo "See features.json")
  CURRENT_TASK="  $TASK_NAME"
fi

# Health status
HEALTH="UNKNOWN"
HEALTH_AGE="never checked"
if command -v cortex-doctor.sh >/dev/null 2>&1 || [[ -f "$SCRIPT_DIR/cortex-doctor.sh" ]]; then
  # Check if cortex-doctor was run recently (look for SESSION_CONTEXT.md as proxy)
  if [[ -f "$PROJECT_DIR/SESSION_CONTEXT.md" ]]; then
    AGE_SECONDS=$(( $(date +%s) - $(stat -f %m "$PROJECT_DIR/SESSION_CONTEXT.md" 2>/dev/null || stat -c %Y "$PROJECT_DIR/SESSION_CONTEXT.md" 2>/dev/null || echo 0) ))
    if [[ "$AGE_SECONDS" -lt 3600 ]]; then
      HEALTH="GOOD"
      HEALTH_AGE="$((AGE_SECONDS / 60)) min ago"
    elif [[ "$AGE_SECONDS" -lt 86400 ]]; then
      HEALTH="GOOD"
      HEALTH_AGE="$((AGE_SECONDS / 3600))h ago"
    else
      HEALTH="STALE"
      HEALTH_AGE="$((AGE_SECONDS / 86400)) days ago"
    fi
  fi
fi

# ─── Output ───────────────────────────────────────────────────────────

if [[ "$JSON_OUTPUT" == "true" ]]; then
  # JSON output for programmatic use
  jq -n \
    --arg project "$PROJECT_NAME" \
    --arg path "$PROJECT_DIR" \
    --arg branch "$BRANCH" \
    --arg last_commit "$LAST_COMMIT" \
    --argjson uncommitted "$UNCOMMITTED" \
    --argjson commits "$COMMIT_COUNT" \
    --argjson sessions "$SESSION_COUNT" \
    --arg storage "$STORAGE_SIZE" \
    --arg oldest "$OLDEST_COMMIT" \
    --arg task "$CURRENT_TASK" \
    --arg health "$HEALTH" \
    --arg health_age "$HEALTH_AGE" \
    '{
      project: $project,
      path: $path,
      git: {
        branch: $branch,
        last_commit: $last_commit,
        uncommitted: $uncommitted
      },
      memory: {
        commits_tracked: $commits,
        sessions: $sessions,
        storage: $storage,
        oldest_commit: $oldest
      },
      current_task: $task,
      health: {
        status: $health,
        last_check: $health_age
      }
    }'
else
  # Human-readable output
  echo "Cortex Status — $PROJECT_NAME"
  echo "══════════════════════════════════════"
  echo "📊 Project: $PROJECT_DIR"
  echo "🌿 Branch: $BRANCH"
  echo "📝 Last Commit: $LAST_COMMIT"
  echo "💾 Uncommitted: $UNCOMMITTED files"
  echo ""
  echo "📚 Recent Commits (last 5):"
  echo "$RECENT_COMMITS"
  echo ""
  echo "🧠 Memory Usage:"
  echo "  Commits tracked: $COMMIT_COUNT"
  echo "  Sessions: $SESSION_COUNT"
  echo "  Storage: $STORAGE_SIZE"
  echo "  Oldest commit: $OLDEST_COMMIT"
  echo ""
  echo "🎯 Current Task:"
  echo "$CURRENT_TASK"
  echo ""
  echo "✅ Health: $HEALTH (last check: $HEALTH_AGE)"
fi
