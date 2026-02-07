#!/usr/bin/env bash
# Cortex LLM Enrichment — Optional, async, never blocks
# Supports: ollama (local), openrouter (cloud), gemini (free)
# Usage: cortex-enrich.sh /path/to/project

set -uo pipefail

# Suppress all errors — this script must NEVER interrupt the user
exec 2>/dev/null

# ─── Source Utilities ─────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=/dev/null
source "$SCRIPT_DIR/_cortex-utils.sh" 2>/dev/null || \
  source "${CORTEX_HOME:-$HOME/.cortex}/bin/_cortex-utils.sh" 2>/dev/null || exit 0

# ─── Validate Project ─────────────────────────────────────────────────

PROJECT_DIR="${1:-}"
[[ -z "$PROJECT_DIR" || ! -d "$PROJECT_DIR" ]] && exit 0
cd "$PROJECT_DIR" || exit 0
git rev-parse --git-dir &>/dev/null || exit 0

# ─── Load Config ──────────────────────────────────────────────────────

CONFIG_FILE="${CORTEX_HOME:-$HOME/.cortex}/config"
[[ ! -f "$CONFIG_FILE" ]] && exit 0

LLM_PROVIDER=""
LLM_MODEL="qwen2.5-coder:7b"
OPENROUTER_KEY=""
GEMINI_KEY=""

while IFS='=' read -r key value; do
  [[ "$key" =~ ^[[:space:]]*# || -z "$key" ]] && continue
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)
  case "$key" in
    llm_provider)    LLM_PROVIDER="$value" ;;
    llm_model)       LLM_MODEL="$value" ;;
    openrouter_key)  OPENROUTER_KEY="$value" ;;
    gemini_key)      GEMINI_KEY="$value" ;;
  esac
done < "$CONFIG_FILE"

[[ -z "$LLM_PROVIDER" || "$LLM_PROVIDER" == "none" ]] && exit 0

# ─── Get Commit Data ─────────────────────────────────────────────────

# Handle first commit (no HEAD~1)
if ! git rev-parse HEAD~1 &>/dev/null; then
  DIFF=$(git diff --root HEAD 2>/dev/null | head -300)
else
  DIFF=$(git diff HEAD~1..HEAD 2>/dev/null | head -300)
fi

COMMIT_MSG=$(git log -1 --format='%s' 2>/dev/null)
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null)

[[ -z "$DIFF" || -z "$COMMIT_MSG" ]] && exit 0

# ─── Build Prompt ─────────────────────────────────────────────────────

PROMPT="Summarize this git commit in 2-3 sentences. Focus on WHAT changed and WHY.

Commit: $COMMIT_MSG

Diff:
$DIFF"

# ─── Call LLM Provider ────────────────────────────────────────────────

SUMMARY=""

case "$LLM_PROVIDER" in
  ollama)
    command -v ollama &>/dev/null || exit 0
    SUMMARY=$(echo "$PROMPT" | timeout 15 ollama run "$LLM_MODEL" 2>/dev/null | head -5)
    ;;

  openrouter)
    [[ -z "$OPENROUTER_KEY" ]] && exit 0
    command -v curl &>/dev/null || exit 0

    if command -v jq &>/dev/null; then
      BODY=$(jq -n --arg p "$PROMPT" \
        '{"model":"meta-llama/llama-3.1-8b-instruct:free","messages":[{"role":"user","content":$p}]}')
    else
      exit 0  # Need jq for safe JSON construction
    fi

    RESPONSE=$(timeout 15 curl -sS \
      "https://openrouter.ai/api/v1/chat/completions" \
      -H "Authorization: Bearer $OPENROUTER_KEY" \
      -H "Content-Type: application/json" \
      -d "$BODY" 2>/dev/null)

    [[ -n "$RESPONSE" ]] && SUMMARY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null | head -5)
    ;;

  gemini)
    [[ -z "$GEMINI_KEY" ]] && exit 0
    command -v curl &>/dev/null || exit 0

    if command -v jq &>/dev/null; then
      BODY=$(jq -n --arg p "$PROMPT" \
        '{"contents":[{"parts":[{"text":$p}]}]}')
    else
      exit 0
    fi

    RESPONSE=$(timeout 15 curl -sS \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_KEY" \
      -H "Content-Type: application/json" \
      -d "$BODY" 2>/dev/null)

    [[ -n "$RESPONSE" ]] && SUMMARY=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null | head -5)
    ;;

  *)
    exit 0
    ;;
esac

# ─── Store Summary ────────────────────────────────────────────────────

[[ -z "$SUMMARY" || "$SUMMARY" == "null" ]] && exit 0

SUMMARIES_DIR="$PROJECT_DIR/.cortex/summaries"
mkdir -p "$SUMMARIES_DIR" 2>/dev/null || exit 0

TODAY=$(date +%F)
SUMMARY_FILE="$SUMMARIES_DIR/$TODAY.md"

{
  echo ""
  echo "### $(date +%H:%M) | $COMMIT_MSG"
  echo ""
  echo "**Commit:** \`$COMMIT_HASH\`"
  echo ""
  echo "$SUMMARY"
  echo ""
  echo "---"
} >> "$SUMMARY_FILE" 2>/dev/null

cp "$SUMMARY_FILE" "$SUMMARIES_DIR/latest.md" 2>/dev/null || true

exit 0
