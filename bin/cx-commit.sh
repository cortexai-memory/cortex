#!/usr/bin/env bash
# cx-commit — Quick commit + enrich + context update
# Usage: cx-commit "commit message" [files...]
# If no files specified, commits all tracked changes (git add -u)

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

if ! _cortex_is_git_repo "$PROJECT_DIR"; then
  _cortex_log error "Not in a git repository"
  exit 1
fi

cd "$PROJECT_DIR"

# ─── Parse Arguments ──────────────────────────────────────────────────

if [[ $# -lt 1 ]]; then
  echo "Usage: cx-commit <message> [files...]"
  echo ""
  echo "Quick commit with automatic enrichment and context update"
  echo ""
  echo "Examples:"
  echo "  cx-commit 'feat: add login page'"
  echo "  cx-commit 'fix: auth bug' src/auth.js"
  echo "  cx-commit 'refactor: cleanup' src/"
  exit 1
fi

COMMIT_MSG="$1"
shift

# ─── Stage Files ──────────────────────────────────────────────────────

if [[ $# -gt 0 ]]; then
  # Files specified - add them
  _cortex_log info "Staging specified files..."
  git add "$@"
else
  # No files - add all tracked changes (git add -u)
  _cortex_log info "Staging all tracked changes..."
  git add -u
fi

# Check if anything is staged
if git diff --cached --quiet; then
  _cortex_log warn "No changes staged. Nothing to commit."
  exit 0
fi

# ─── Show What Will Be Committed ──────────────────────────────────────

echo ""
echo "Changes to be committed:"
git diff --cached --stat

echo ""
read -r -p "Commit with message: \"$COMMIT_MSG\"? [Y/n] " response
case "$response" in
  [nN][oO]|[nN])
    echo "Aborted"
    exit 0
    ;;
esac

# ─── Commit ───────────────────────────────────────────────────────────

_cortex_log info "Committing..."
if git commit -m "$COMMIT_MSG"; then
  COMMIT_HASH=$(git rev-parse --short HEAD)
  _cortex_log info "Committed: $COMMIT_HASH"
else
  _cortex_log error "Commit failed"
  exit 1
fi

# ─── Optional Enrichment ──────────────────────────────────────────────

if [[ "${CORTEX_ENRICH:-0}" == "1" ]]; then
  ENRICH_SCRIPT="$SCRIPT_DIR/cortex-enrich.sh"
  [[ ! -f "$ENRICH_SCRIPT" ]] && ENRICH_SCRIPT="$CORTEX_HOME/bin/cortex-enrich.sh"

  if [[ -f "$ENRICH_SCRIPT" ]]; then
    _cortex_log info "Enriching commit with AI summary..."
    "$ENRICH_SCRIPT" "$PROJECT_DIR" 2>/dev/null &
    disown 2>/dev/null || true
  fi
fi

# ─── Update Context ───────────────────────────────────────────────────

CONTEXT_SCRIPT="$SCRIPT_DIR/cortex-context.sh"
[[ ! -f "$CONTEXT_SCRIPT" ]] && CONTEXT_SCRIPT="$CORTEX_HOME/bin/cortex-context.sh"

if [[ -f "$CONTEXT_SCRIPT" ]]; then
  _cortex_log info "Updating session context..."
  "$CONTEXT_SCRIPT" "$PROJECT_DIR" 2>/dev/null || true
fi

# ─── Summary ──────────────────────────────────────────────────────────

echo ""
echo "✅ Done!"
echo "   • Commit: $COMMIT_HASH - $COMMIT_MSG"
[[ "${CORTEX_ENRICH:-0}" == "1" ]] && echo "   • AI summary: generating in background"
echo "   • Context: updated in SESSION_CONTEXT.md"
echo ""
