# --- cortex-hook-v1 ---
# Cortex post-commit hook — captures commit metadata to .cortex/commits.jsonl
# Auto-installed by cx (cortex-session.sh). Safe to run alongside other hooks.
# Performance: <50ms. Never blocks git. Always exits 0.

# Skip in CI/CD environments
if [[ -n "${CI:-}" ]] || [[ -n "${GITHUB_ACTIONS:-}" ]] || \
   [[ -n "${GITLAB_CI:-}" ]] || [[ -n "${JENKINS_URL:-}" ]] || \
   [[ -n "${BUILDKITE:-}" ]] || [[ -n "${CIRCLECI:-}" ]] || \
   [[ -n "${TRAVIS:-}" ]] || [[ -n "${CODEBUILD_BUILD_ID:-}" ]]; then
  exit 0
fi

# All operations wrapped — never fail, never block
{
  CORTEX_DIR="$(git rev-parse --show-toplevel 2>/dev/null)/.cortex"
  [[ -z "$CORTEX_DIR" ]] && exit 0
  mkdir -p "$CORTEX_DIR"

  # Capture commit data
  HASH=$(git rev-parse --short HEAD 2>/dev/null || echo "unknown")
  MSG=$(git log -1 --format='%s' 2>/dev/null | head -c 200)
  BRANCH=$(git branch --show-current 2>/dev/null || echo "unknown")
  TS=$(date -u +%FT%TZ)

  # Changed files (max 20, comma-separated)
  FILES=$(git diff-tree --no-commit-id --name-only -r HEAD 2>/dev/null | head -20 | tr '\n' ',' | sed 's/,$//')

  # Parent count (1=normal, 2+=merge)
  PARENTS=$(git rev-list --parents -n 1 HEAD 2>/dev/null | wc -w | tr -d ' ')
  PARENTS=$((PARENTS - 1))  # Subtract the commit itself
  [[ "$PARENTS" -lt 1 ]] && PARENTS=1

  # Diff stats — handle first commit (no HEAD~1)
  COMMIT_COUNT=$(git rev-list --count HEAD 2>/dev/null || echo 1)
  if [[ "$COMMIT_COUNT" -le 1 ]]; then
    STATS=$(git diff --stat --root HEAD 2>/dev/null | tail -1)
  else
    STATS=$(git diff --stat HEAD~1..HEAD 2>/dev/null | tail -1)
  fi

  # Extract insertions/deletions from stats line
  INS=$(echo "$STATS" | grep -o '[0-9]\+ insertion' | grep -o '[0-9]\+' || echo 0)
  DEL=$(echo "$STATS" | grep -o '[0-9]\+ deletion' | grep -o '[0-9]\+' || echo 0)
  [[ -z "$INS" ]] && INS=0
  [[ -z "$DEL" ]] && DEL=0

  # Write JSON using jq (safe escaping) with fallback
  if command -v jq >/dev/null 2>&1; then
    jq -n -c \
      --arg h "$HASH" \
      --arg m "$MSG" \
      --arg f "$FILES" \
      --argjson i "${INS:-0}" \
      --argjson d "${DEL:-0}" \
      --arg b "$BRANCH" \
      --argjson p "${PARENTS:-1}" \
      --arg t "$TS" \
      '{h:$h,m:$m,f:$f,i:$i,d:$d,b:$b,p:$p,t:$t}' \
      >> "$CORTEX_DIR/commits.jsonl" 2>/dev/null
  else
    # Fallback without jq: basic escaping (handles quotes and backslashes)
    SAFE_MSG=$(printf '%s' "$MSG" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' | tr '\n' ' ')
    printf '{"h":"%s","m":"%s","f":"%s","i":%s,"d":%s,"b":"%s","p":%s,"t":"%s"}\n' \
      "$HASH" "$SAFE_MSG" "$FILES" "${INS:-0}" "${DEL:-0}" "$BRANCH" "${PARENTS:-1}" "$TS" \
      >> "$CORTEX_DIR/commits.jsonl" 2>/dev/null
  fi

  # Trigger async LLM enrichment (non-blocking)
  if [[ "${CORTEX_ENRICH:-0}" == "1" ]] && [[ -f "$HOME/.cortex/bin/cortex-enrich.sh" ]]; then
    nohup "$HOME/.cortex/bin/cortex-enrich.sh" "$(git rev-parse --show-toplevel)" </dev/null >/dev/null 2>&1 &
    disown 2>/dev/null || true
  fi
} 2>/dev/null

exit 0
# --- cortex-hook-v1 ---
