#!/usr/bin/env bash
# Cortex LLM Enrichment — Optional, async, never blocks
# Supports: ollama (local), openrouter (cloud), gemini (free)
# Usage: cortex-enrich.sh /path/to/project [prompt-type]
#   prompt-type: commit (default) | session | decisions

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

# ─── Determine Prompt Type ────────────────────────────────────────────

PROMPT_TYPE="${2:-commit}"  # commit | session | decisions

# ─── Load Config ──────────────────────────────────────────────────────

CONFIG_FILE="${CORTEX_HOME:-$HOME/.cortex}/config"
[[ ! -f "$CONFIG_FILE" ]] && exit 0

LLM_PROVIDER=""
LLM_MODEL="qwen2.5-coder:7b"
OPENROUTER_KEY=""
GEMINI_KEY=""
ENRICHMENT_PROMPTS="commit"  # Default: only commit summaries

while IFS='=' read -r key value; do
  [[ "$key" =~ ^[[:space:]]*# || -z "$key" ]] && continue
  key=$(echo "$key" | xargs)
  value=$(echo "$value" | xargs)
  case "$key" in
    llm_provider)         LLM_PROVIDER="$value" ;;
    llm_model)            LLM_MODEL="$value" ;;
    openrouter_key)       OPENROUTER_KEY="$value" ;;
    gemini_key)           GEMINI_KEY="$value" ;;
    enrichment_prompts)   ENRICHMENT_PROMPTS="$value" ;;
  esac
done < "$CONFIG_FILE"

[[ -z "$LLM_PROVIDER" || "$LLM_PROVIDER" == "none" ]] && exit 0

# Check if requested prompt type is enabled
if ! echo "$ENRICHMENT_PROMPTS" | grep -q "$PROMPT_TYPE"; then
  exit 0
fi

# ─── Get Commit Data ──────────────────────────────────────────────────

# Handle first commit (no HEAD~1)
if ! git rev-parse HEAD~1 &>/dev/null; then
  DIFF=$(git diff --stat --root HEAD 2>/dev/null; git diff --root HEAD 2>/dev/null | head -300)
else
  DIFF=$(git diff --stat HEAD~1..HEAD 2>/dev/null; git diff HEAD~1..HEAD 2>/dev/null | head -300)
fi

COMMIT_MSG=$(git log -1 --format='%s' 2>/dev/null)
COMMIT_HASH=$(git rev-parse --short HEAD 2>/dev/null)
FILES_CHANGED=$(git diff --name-only HEAD~1..HEAD 2>/dev/null || git diff --name-only --root HEAD 2>/dev/null || echo "")

[[ -z "$DIFF" || -z "$COMMIT_MSG" ]] && exit 0

# ─── Load Prompt Template ─────────────────────────────────────────────

TEMPLATE_DIR="${CORTEX_HOME:-$HOME/.cortex}/templates/prompts"
PROMPT_TEMPLATE=""

case "$PROMPT_TYPE" in
  commit)
    [[ -f "$TEMPLATE_DIR/summarize-commit.txt" ]] && PROMPT_TEMPLATE=$(cat "$TEMPLATE_DIR/summarize-commit.txt")
    ;;
  session)
    [[ -f "$TEMPLATE_DIR/summarize-session.txt" ]] && PROMPT_TEMPLATE=$(cat "$TEMPLATE_DIR/summarize-session.txt")
    ;;
  decisions)
    [[ -f "$TEMPLATE_DIR/extract-decisions.txt" ]] && PROMPT_TEMPLATE=$(cat "$TEMPLATE_DIR/extract-decisions.txt")
    ;;
esac

# Fallback to simple prompt if template not found
if [[ -z "$PROMPT_TEMPLATE" ]]; then
  PROMPT_TEMPLATE="Summarize this git commit in 2-3 sentences. Focus on WHAT changed and WHY."
fi

# ─── Build Full Prompt ────────────────────────────────────────────────

PROMPT="$PROMPT_TEMPLATE

Commit Message: $COMMIT_MSG
Commit Hash: $COMMIT_HASH
Files Changed: ${FILES_CHANGED//$'\n'/, }

Diff:
$DIFF"

# ─── Call LLM Provider ────────────────────────────────────────────────

SUMMARY=""

case "$LLM_PROVIDER" in
  ollama)
    command -v ollama &>/dev/null || exit 0
    SUMMARY=$(echo "$PROMPT" | timeout 30 ollama run "$LLM_MODEL" 2>/dev/null)
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

    RESPONSE=$(timeout 30 curl -sS \
      "https://openrouter.ai/api/v1/chat/completions" \
      -H "Authorization: Bearer $OPENROUTER_KEY" \
      -H "Content-Type: application/json" \
      -d "$BODY" 2>/dev/null)

    [[ -n "$RESPONSE" ]] && SUMMARY=$(echo "$RESPONSE" | jq -r '.choices[0].message.content // empty' 2>/dev/null)
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

    RESPONSE=$(timeout 30 curl -sS \
      "https://generativelanguage.googleapis.com/v1beta/models/gemini-2.0-flash:generateContent?key=$GEMINI_KEY" \
      -H "Content-Type: application/json" \
      -d "$BODY" 2>/dev/null)

    [[ -n "$RESPONSE" ]] && SUMMARY=$(echo "$RESPONSE" | jq -r '.candidates[0].content.parts[0].text // empty' 2>/dev/null)
    ;;

  *)
    exit 0
    ;;
esac

# ─── Store Summary ────────────────────────────────────────────────────

[[ -z "$SUMMARY" || "$SUMMARY" == "null" ]] && exit 0

# Create output directories based on prompt type
case "$PROMPT_TYPE" in
  commit)
    OUTPUT_DIR="$PROJECT_DIR/.cortex/summaries/commits"
    mkdir -p "$OUTPUT_DIR" 2>/dev/null || exit 0
    OUTPUT_FILE="$OUTPUT_DIR/$COMMIT_HASH.md"
    LATEST_LINK="$PROJECT_DIR/.cortex/summaries/latest.md"
    ;;
  session)
    OUTPUT_DIR="$PROJECT_DIR/.cortex/summaries/sessions"
    mkdir -p "$OUTPUT_DIR" 2>/dev/null || exit 0
    SESSION_ID=$(date +%Y%m%d-%H%M%S)
    OUTPUT_FILE="$OUTPUT_DIR/$SESSION_ID.md"
    LATEST_LINK=""
    ;;
  decisions)
    # Skip if no decisions found
    if echo "$SUMMARY" | grep -qi "NO_DECISIONS"; then
      exit 0
    fi
    OUTPUT_DIR="$PROJECT_DIR/.cortex/decisions"
    mkdir -p "$OUTPUT_DIR" 2>/dev/null || exit 0
    TODAY=$(date +%F)
    OUTPUT_FILE="$OUTPUT_DIR/$TODAY.md"
    LATEST_LINK=""
    ;;
esac

# Write summary with metadata
{
  echo "# $(echo "$PROMPT_TYPE" | tr '[:lower:]' '[:upper:]') Summary"
  echo ""
  echo "**Generated:** $(date -u +%FT%TZ)"
  echo "**Commit:** \`$COMMIT_HASH\` — $COMMIT_MSG"
  echo "**Model:** $LLM_MODEL ($LLM_PROVIDER)"
  echo ""
  echo "---"
  echo ""
  echo "$SUMMARY"
  echo ""
} > "$OUTPUT_FILE" 2>/dev/null

# Update latest link for commit summaries
if [[ -n "$LATEST_LINK" ]]; then
  cp "$OUTPUT_FILE" "$LATEST_LINK" 2>/dev/null || true
fi

exit 0
