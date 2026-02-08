#!/usr/bin/env bash
# cortex-preview — Preview SESSION_CONTEXT.md without launching Claude
# Usage: cortex-preview.sh [project-dir]
# Generates and displays context, then cleans up

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

echo "🔍 Cortex Context Preview"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# Validate project directory
if ! _cortex_is_git_repo "$PROJECT_DIR"; then
  echo "❌ Not in a git repository"
  echo "Cortex requires a git repository to generate context."
  exit 1
fi

CONTEXT_FILE="$PROJECT_DIR/SESSION_CONTEXT.md"

# ─── Generate Context ─────────────────────────────────────────────────

CONTEXT_SCRIPT="$SCRIPT_DIR/cortex-context.sh"
[[ ! -f "$CONTEXT_SCRIPT" ]] && CONTEXT_SCRIPT="$CORTEX_HOME/bin/cortex-context.sh"

if [[ ! -f "$CONTEXT_SCRIPT" ]]; then
  echo "❌ cortex-context.sh not found"
  exit 1
fi

# Generate fresh context
"$CONTEXT_SCRIPT" "$PROJECT_DIR" 2>/dev/null || {
  echo "❌ Context generation failed"
  exit 1
}

# ─── Display Context ──────────────────────────────────────────────────

if [[ ! -f "$CONTEXT_FILE" ]]; then
  echo "❌ SESSION_CONTEXT.md not found"
  exit 1
fi

# Display with syntax highlighting if available
if command -v bat >/dev/null 2>&1; then
  bat --language markdown --paging=always --style=plain "$CONTEXT_FILE"
elif command -v glow >/dev/null 2>&1; then
  glow "$CONTEXT_FILE"
else
  cat "$CONTEXT_FILE"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

# ─── Statistics ───────────────────────────────────────────────────────

WORD_COUNT=$(wc -w < "$CONTEXT_FILE" | tr -d ' ')
LINE_COUNT=$(wc -l < "$CONTEXT_FILE" | tr -d ' ')
CHAR_COUNT=$(wc -c < "$CONTEXT_FILE" | tr -d ' ')

# Rough token estimate (1 token ≈ 4 characters)
TOKEN_ESTIMATE=$((CHAR_COUNT / 4))

echo "📊 Context Statistics:"
echo "   • Lines: $LINE_COUNT"
echo "   • Words: $WORD_COUNT"
echo "   • Characters: $CHAR_COUNT"
echo "   • Estimated tokens: ~$TOKEN_ESTIMATE"
echo ""
echo "💡 This context will be available to Claude when you run 'cx'"
echo ""
