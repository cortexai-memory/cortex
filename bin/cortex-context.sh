#!/usr/bin/env bash
# Cortex Context Generator — Writes SESSION_CONTEXT.md from git data
# Dependencies: bash, git, jq
# Execution: <100ms
# Usage: cortex-context.sh [project-dir]

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

PROJECT_DIR="$(_cortex_project_root "${1:-}")"
CORTEX_DIR="$PROJECT_DIR/.cortex"
OUTPUT="$PROJECT_DIR/SESSION_CONTEXT.md"
OUTPUT_TMP="$OUTPUT.tmp.$$"
SESSIONS_FILE="$CORTEX_DIR/sessions.jsonl"
COMMITS_FILE="$CORTEX_DIR/commits.jsonl"

mkdir -p "$CORTEX_DIR"

# Ensure cleanup on exit
trap 'rm -f "$OUTPUT_TMP"' EXIT

# ─── Session Counter ──────────────────────────────────────────────────

SESSION_NUM=0
if [[ -f "$SESSIONS_FILE" ]]; then
  # Count start events (not end events)
  SESSION_NUM=$(grep -c '"type":"start"' "$SESSIONS_FILE" 2>/dev/null || echo 0)
fi
SESSION_NUM=$((SESSION_NUM + 1))

# ─── Since Last Session ──────────────────────────────────────────────

SINCE_LAST=""
if [[ -f "$SESSIONS_FILE" ]]; then
  # Find the last session end time
  LAST_END=$(grep '"type":"end"' "$SESSIONS_FILE" 2>/dev/null | tail -1 | jq -r '.ts // empty' 2>/dev/null || true)
fi

if _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1; then
  if [[ -n "${LAST_END:-}" ]]; then
    SINCE_LAST=$(cd "$PROJECT_DIR" && git log --oneline --since="$LAST_END" 2>/dev/null | head -10)
  fi
  # Fallback: show last 5 commits
  if [[ -z "${SINCE_LAST:-}" ]]; then
    SINCE_LAST=$(cd "$PROJECT_DIR" && git log --oneline -5 2>/dev/null)
  fi
fi
[[ -z "${SINCE_LAST:-}" ]] && SINCE_LAST="No commits found."

# ─── Recent Commits (24h) ────────────────────────────────────────────

RECENT=""
if [[ -f "$COMMITS_FILE" ]]; then
  CUTOFF=$(_cortex_date_ago "24H" 2>/dev/null || echo "2000-01-01T00:00:00Z")
  # Read enriched commits, skip corrupted lines
  RECENT=$(jq -r --arg cutoff "$CUTOFF" \
    'select(.t > $cutoff) | "- \(.h) \(.m) [+\(.i)/-\(.d)] \(.f // "")"' \
    "$COMMITS_FILE" 2>/dev/null | tail -15 || true)
fi

# Fallback to raw git log
if [[ -z "${RECENT:-}" ]] && _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1; then
  RECENT=$(cd "$PROJECT_DIR" && git log --oneline --since='24 hours ago' 2>/dev/null | head -10)
fi
[[ -z "${RECENT:-}" ]] && RECENT="No commits in last 24 hours."

# ─── Current Task ─────────────────────────────────────────────────────

TASK="No task tracker found. Add PROJECT_STATE.md or features.json to track progress."
if [[ -f "$PROJECT_DIR/PROJECT_STATE.md" ]]; then
  TASK=$(grep -A2 -E 'Current|In Progress|Active' "$PROJECT_DIR/PROJECT_STATE.md" 2>/dev/null | head -3 || echo "See PROJECT_STATE.md")
elif [[ -f "$PROJECT_DIR/features.json" ]]; then
  TASK=$(jq -r '[.. | objects | select(.status=="pending" or .passes==false)] | first | .name // "No pending tasks"' "$PROJECT_DIR/features.json" 2>/dev/null || echo "See features.json")
fi

# ─── Git Status ───────────────────────────────────────────────────────

BRANCH="not a git repo"
UNCOMMITTED="0"
LAST_COMMIT="no commits"

if _cortex_is_git_repo "$PROJECT_DIR"; then
  HAS_COMMITS=true
  cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1 || HAS_COMMITS=false

  if [[ "$HAS_COMMITS" == "true" ]]; then
    # Branch (handle detached HEAD)
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

# ─── Warnings ─────────────────────────────────────────────────────────

WARNINGS=""

# Too many uncommitted files
if [[ "$UNCOMMITTED" -gt 5 ]]; then
  WARNINGS="${WARNINGS}- $UNCOMMITTED uncommitted files — consider committing or stashing\n"
fi

# Merge conflicts (search ALL tracked files, not just src/)
if _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1; then
  CONFLICTS=$(cd "$PROJECT_DIR" && git grep -l '<<<<<<' 2>/dev/null | head -3 || true)
  if [[ -n "$CONFLICTS" ]]; then
    WARNINGS="${WARNINGS}- MERGE CONFLICTS detected in: $(echo "$CONFLICTS" | tr '\n' ', ' | sed 's/,$//')\n"
  fi

  # Stale branch (>3 days since last commit)
  LAST_COMMIT_TS=$(cd "$PROJECT_DIR" && git log -1 --format='%ct' 2>/dev/null || echo 0)
  NOW_TS=$(date +%s)
  STALE_THRESHOLD=$((3 * 24 * 60 * 60))  # 3 days in seconds
  if [[ $((NOW_TS - LAST_COMMIT_TS)) -gt $STALE_THRESHOLD ]] && [[ "$LAST_COMMIT_TS" -gt 0 ]]; then
    DAYS_STALE=$(( (NOW_TS - LAST_COMMIT_TS) / 86400 ))
    WARNINGS="${WARNINGS}- Branch is ${DAYS_STALE} days stale (last commit: $(cd "$PROJECT_DIR" && git log -1 --format='%ar' 2>/dev/null))\n"
  fi

  # Detached HEAD warning
  if [[ "$BRANCH" == DETACHED@* ]]; then
    WARNINGS="${WARNINGS}- HEAD is detached. Consider checking out a branch.\n"
  fi
fi

[[ -z "$WARNINGS" ]] && WARNINGS="None."

# ─── LLM Enrichment (optional) ───────────────────────────────────────

ENRICHMENT=""
DECISIONS=""

# Include commit summaries
if [[ -f "$CORTEX_DIR/summaries/latest.md" ]]; then
  SUMMARY_CONTENT=$(tail -20 "$CORTEX_DIR/summaries/latest.md" 2>/dev/null || true)
  if [[ -n "$SUMMARY_CONTENT" ]]; then
    ENRICHMENT="
## AI SUMMARY (auto-generated, verify accuracy)
$SUMMARY_CONTENT"
  fi
fi

# Include architectural decisions (if any exist from today)
TODAY=$(date +%F)
if [[ -f "$CORTEX_DIR/decisions/$TODAY.md" ]]; then
  DECISIONS_CONTENT=$(cat "$CORTEX_DIR/decisions/$TODAY.md" 2>/dev/null || true)
  if [[ -n "$DECISIONS_CONTENT" ]]; then
    DECISIONS="
## ARCHITECTURAL DECISIONS (today)
$DECISIONS_CONTENT"
  fi
fi

# ─── Write SESSION_CONTEXT.md (atomic: write to tmp then move) ────────

cat > "$OUTPUT_TMP" << CTXEOF
# SESSION_CONTEXT.md (auto-generated by Cortex — DO NOT EDIT)
# Generated: $(_cortex_date_iso) | Session #$SESSION_NUM | Project: $(basename "$PROJECT_DIR")

## SINCE LAST SESSION
$SINCE_LAST

## RECENT COMMITS (24h)
$RECENT

## CURRENT TASK
$TASK

## GIT STATUS
Branch: $BRANCH | Uncommitted: $UNCOMMITTED files
Last: $LAST_COMMIT

## WARNINGS
$(printf '%b' "$WARNINGS")
${ENRICHMENT}${DECISIONS}
CTXEOF

mv "$OUTPUT_TMP" "$OUTPUT"

# Report
WORD_COUNT=$(wc -w < "$OUTPUT" | tr -d ' ')
_cortex_log info "Session #$SESSION_NUM context ready ($WORD_COUNT words)"
