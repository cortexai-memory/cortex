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

# Validate git repository (allow non-git for basic context)
if ! _cortex_is_git_repo "$PROJECT_DIR"; then
  _cortex_log warn "not a git repo - Limited context available"
  # Create basic context anyway for non-git projects
fi

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

# ─── Check for Uncommitted Work Snapshot ─────────────────────────────

UNCOMMITTED_SECTION=""
SNAPSHOTS_DIR="$CORTEX_DIR/snapshots"
LATEST_SNAPSHOT="$SNAPSHOTS_DIR/latest.snapshot"

if [[ -f "$LATEST_SNAPSHOT" ]]; then
  SNAPSHOT_TS=$(jq -r '.timestamp' "$LATEST_SNAPSHOT" 2>/dev/null || echo "")
  SNAPSHOT_FILES=$(jq -r '.uncommitted_files' "$LATEST_SNAPSHOT" 2>/dev/null || echo "0")
  SNAPSHOT_SUMMARY=$(jq -r '.summary' "$LATEST_SNAPSHOT" 2>/dev/null || echo "Uncommitted work")

  if [[ -n "$SNAPSHOT_TS" ]] && [[ "$SNAPSHOT_FILES" -gt 0 ]]; then
    # Calculate time ago (simple version)
    TIME_AGO="some time ago"

    UNCOMMITTED_SECTION="
## PREVIOUS SESSION (uncommitted work)

⚠️  You have uncommitted work from last session:

$SNAPSHOT_SUMMARY

Actions:
  • Continue working: Just start coding
  • Commit changes: git add . && git commit -m \"...\"
  • View details: cortex-snapshot.sh show latest
  • List snapshots: cortex-snapshot.sh list

"
  fi
fi

# ─── Since Last Session ──────────────────────────────────────────────

SINCE_LAST=""
if [[ -f "$SESSIONS_FILE" ]]; then
  # Find the last session end time
  LAST_END=$(grep '"type":"end"' "$SESSIONS_FILE" 2>/dev/null | tail -1 | jq -r '.ts // empty' 2>/dev/null || true)
fi

if _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1; then
  if [[ -n "${LAST_END:-}" ]]; then
    SINCE_LAST=$(cd "$PROJECT_DIR" && git log --oneline --since="$LAST_END" 2>/dev/null | head -10 || echo "")
  fi
  # Fallback: show last 5 commits
  if [[ -z "${SINCE_LAST:-}" ]]; then
    SINCE_LAST=$(cd "$PROJECT_DIR" && git log --oneline -5 2>/dev/null || echo "")
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
  RECENT=$(cd "$PROJECT_DIR" && git log --oneline --since='24 hours ago' 2>/dev/null | head -10 || echo "")
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
  (cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1) || HAS_COMMITS=false

  if [[ "$HAS_COMMITS" == "true" ]]; then
    # Branch (handle detached HEAD)
    BRANCH=$(cd "$PROJECT_DIR" && git branch --show-current 2>/dev/null || echo "")
    if [[ -z "$BRANCH" ]]; then
      local_head=$(cd "$PROJECT_DIR" && git rev-parse --short HEAD 2>/dev/null || echo "unknown")
      BRANCH="DETACHED@$local_head"
    fi
    LAST_COMMIT=$(cd "$PROJECT_DIR" && git log -1 --format='%h %s (%ar)' 2>/dev/null || echo "no commits")
  else
    BRANCH=$(cd "$PROJECT_DIR" && git branch --show-current 2>/dev/null || echo "main")
    LAST_COMMIT="no commits yet"
  fi

  UNCOMMITTED=$(cd "$PROJECT_DIR" && git status --porcelain 2>/dev/null | wc -l | tr -d ' \n' || echo "0")
fi

# ─── Smart Context Prioritization (B2.2) ─────────────────────────────

HOT_FILES=""
FOCUS_AREAS=""

if _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1; then
  # Find most frequently changed files in last 7 days
  hot_files_list=$(cd "$PROJECT_DIR" && \
    git log --since='7 days ago' --name-only --format='' 2>/dev/null | \
    grep -v '^$' | \
    sort | uniq -c | sort -rn | head -5 | \
    awk '{print $2" ("$1" changes)"}' || true)

  if [[ -n "$hot_files_list" ]]; then
    HOT_FILES="
## FOCUS AREAS (most active files, last 7 days)
$hot_files_list
"
  fi

  # Identify file types being worked on
  file_types=$(cd "$PROJECT_DIR" && \
    git log --since='7 days ago' --name-only --format='' 2>/dev/null | \
    grep -v '^$' | \
    sed 's/.*\.//' | \
    sort | uniq -c | sort -rn | head -3 | \
    awk '{print $2" ("$1" files)"}' | \
    tr '\n' ', ' | sed 's/,$//' || true)

  if [[ -n "$file_types" ]]; then
    FOCUS_AREAS="File types: $file_types"
  fi
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

# ─── Session Notes (B6.2) ────────────────────────────────────────────

NOTES_SECTION=""
NOTES_FILE="$CORTEX_DIR/notes.jsonl"

if [[ -f "$NOTES_FILE" ]] && [[ -s "$NOTES_FILE" ]]; then
  # Read last 5 notes
  NOTES_LIST=$(tail -5 "$NOTES_FILE" | while IFS= read -r line; do
    if command -v jq >/dev/null 2>&1; then
      note=$(echo "$line" | jq -r '.note // ""' 2>/dev/null || echo "")
      if [[ -n "$note" ]]; then
        echo "- $note"
      fi
    fi
  done)

  if [[ -n "$NOTES_LIST" ]]; then
    NOTES_SECTION="

## SESSION NOTES (last 5)
$NOTES_LIST
"
  fi
fi

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
${UNCOMMITTED_SECTION}
## SINCE LAST SESSION
$SINCE_LAST

## RECENT COMMITS (24h)
$RECENT

## CURRENT TASK
$TASK

## GIT STATUS
Branch: $BRANCH | Uncommitted: $UNCOMMITTED files
Last: $LAST_COMMIT
${FOCUS_AREAS}
${HOT_FILES}
## WARNINGS
$(printf '%b' "$WARNINGS")
${NOTES_SECTION}${ENRICHMENT}${DECISIONS}
CTXEOF

mv "$OUTPUT_TMP" "$OUTPUT"

# Report
WORD_COUNT=$(wc -w < "$OUTPUT" | tr -d ' ')
_cortex_log info "Session #$SESSION_NUM context ready ($WORD_COUNT words)"

# Output key context info for debugging/testing
[[ "$RECENT" == "No commits in last 24 hours." ]] && echo "[Context] No commits in last 24 hours" >&2
[[ "$TASK" == *"No task tracker"* ]] && echo "[Context] No task tracker found" >&2
[[ "$BRANCH" == DETACHED@* ]] && echo "[Context] DETACHED HEAD at ${BRANCH#DETACHED@}" >&2
[[ -n "$WARNINGS" ]] && [[ "$WARNINGS" != "None." ]] && echo "[Context] Warnings: $(echo "$WARNINGS" | tr '\n' ' ')" >&2

# ─── Generate PROGRESS.md (optional) ──────────────────────────────────

generate_progress() {
  local PROGRESS_FILE="$PROJECT_DIR/PROGRESS.md"
  local PROGRESS_TMP="$PROGRESS_FILE.tmp.$$"

  # What's Been Done (last 7 days)
  local DONE=""
  if _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1; then
    # Get commits from last 7 days with stats
    DONE=$(cd "$PROJECT_DIR" && git log --since='7 days ago' --format='%h|%s' --shortstat 2>/dev/null | \
      awk '
        /^\|/ {
          split($0, a, "|")
          hash = a[1]
          msg = a[2]
          getline stats
          if (stats ~ /[0-9]+ files? changed/) {
            # Extract insertions/deletions
            ins = 0; del = 0
            if (match(stats, /([0-9]+) insertion/, arr)) ins = arr[1]
            if (match(stats, /([0-9]+) deletion/, arr)) del = arr[1]
            lines = ins + del
            print "- ✅ " msg " (" hash ", " lines " lines)"
          }
        }
      ' | head -10)
  fi
  [[ -z "$DONE" ]] && DONE="- No commits in last 7 days"

  # What's In Progress (feature branches)
  local IN_PROGRESS=""
  if _cortex_is_git_repo "$PROJECT_DIR"; then
    IN_PROGRESS=$(cd "$PROJECT_DIR" && git branch 2>/dev/null | grep -E '^\s+(feature/|fix/|wip/)' | sed 's/^[* ]*/- 🔨 /' | head -5)
  fi
  [[ -z "$IN_PROGRESS" ]] && IN_PROGRESS="- No feature branches"

  # What's Next (from PROJECT_STATE.md or features.json)
  local NEXT=""
  if [[ -f "$PROJECT_DIR/PROJECT_STATE.md" ]]; then
    NEXT=$(grep -E '^\s*-\s*\[[ ]\]' "$PROJECT_DIR/PROJECT_STATE.md" 2>/dev/null | head -5 | sed 's/\[[ ]\]/⏳/')
  elif [[ -f "$PROJECT_DIR/features.json" ]]; then
    NEXT=$(jq -r '[.. | objects | select(.status=="pending")] | .[:5] | .[] | "- ⏳ \(.name)"' "$PROJECT_DIR/features.json" 2>/dev/null)
  fi
  [[ -z "$NEXT" ]] && NEXT="- No pending tasks tracked"

  # Velocity (last 7 days)
  local COMMIT_COUNT=0
  local LINES_ADDED=0
  if _cortex_is_git_repo "$PROJECT_DIR" && cd "$PROJECT_DIR" && git rev-parse HEAD >/dev/null 2>&1; then
    COMMIT_COUNT=$(cd "$PROJECT_DIR" && git log --since='7 days ago' --oneline 2>/dev/null | wc -l | tr -d ' ')
    LINES_ADDED=$(cd "$PROJECT_DIR" && git log --since='7 days ago' --numstat --format='' 2>/dev/null | \
      awk '{add+=$1; del+=$2} END {print add+0}')
  fi
  local AVG_COMMITS="0.0"
  if [[ "$COMMIT_COUNT" -gt 0 ]]; then
    AVG_COMMITS=$(echo "scale=1; $COMMIT_COUNT / 7" | bc 2>/dev/null || echo "0.0")
  fi

  # Write PROGRESS.md
  cat > "$PROGRESS_TMP" << PROGEOF
# Project Progress

**Generated:** $(_cortex_date_iso) | **Project:** $(basename "$PROJECT_DIR")

---

## What's Been Done (Last 7 Days)

$DONE

## What's In Progress

$IN_PROGRESS

## What's Next

$NEXT

## Velocity

- Last 7 days: **$COMMIT_COUNT commits**, **$LINES_ADDED lines** added
- Average: **$AVG_COMMITS commits/day**

---

*Auto-generated by Cortex. To track tasks, add PROJECT_STATE.md or features.json to your repo.*
PROGEOF

  mv "$PROGRESS_TMP" "$PROGRESS_FILE"
  _cortex_log info "PROGRESS.md generated"
}

# Generate progress file (optional, based on config or environment)
if [[ "${CORTEX_GENERATE_PROGRESS:-1}" == "1" ]]; then
  generate_progress 2>/dev/null || true
fi
