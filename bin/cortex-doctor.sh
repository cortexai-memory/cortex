#!/usr/bin/env bash
# Cortex Doctor — Health diagnostics and self-repair
# Usage: cortex-doctor.sh [--fix]

set -euo pipefail

# ─── Source Utilities ─────────────────────────────────────────────────

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=bin/_cortex-utils.sh
source "$SCRIPT_DIR/_cortex-utils.sh" 2>/dev/null || \
  source "${CORTEX_HOME:-$HOME/.cortex}/bin/_cortex-utils.sh" 2>/dev/null || {
    echo "[Cortex] Error: Cannot find _cortex-utils.sh" >&2
    exit 1
  }

# ─── Config ───────────────────────────────────────────────────────────

CORTEX_HOME="${CORTEX_HOME:-$HOME/.cortex}"
FIX_MODE=false
HOOK_MARKER="cortex-hook-v1"

[[ "${1:-}" == "--fix" ]] && FIX_MODE=true

# Counters
checks_passed=0
checks_failed=0
checks_optional=0
required_total=0

# ─── Check Helpers ────────────────────────────────────────────────────

pass() {
  echo "  ✓ $1"
  checks_passed=$((checks_passed + 1))
  required_total=$((required_total + 1))
}

fail() {
  echo "  ✗ $1"
  checks_failed=$((checks_failed + 1))
  required_total=$((required_total + 1))
}

optional() {
  echo "  ○ $1"
  checks_optional=$((checks_optional + 1))
}

fixed() {
  echo "    → Fixed: $1"
}

# ─── Header ───────────────────────────────────────────────────────────

echo ""
echo "Cortex Doctor v$CORTEX_VERSION"
echo "────────────────────────"

# ─── Check 1: git ─────────────────────────────────────────────────────

if command -v git &>/dev/null; then
  pass "git $(git --version | awk '{print $3}')"
else
  fail "git: not installed"
fi

# ─── Check 2: jq ─────────────────────────────────────────────────────

if command -v jq &>/dev/null; then
  pass "jq $(jq --version 2>/dev/null | sed 's/jq-//')"
else
  fail "jq: not installed"
fi

# ─── Check 3: ~/.cortex/ exists ───────────────────────────────────────

if [[ -d "$CORTEX_HOME" ]]; then
  pass "$CORTEX_HOME/ exists"
else
  fail "$CORTEX_HOME/ does not exist"
  if [[ "$FIX_MODE" == "true" ]]; then
    mkdir -p "$CORTEX_HOME"/{bin,templates}
    fixed "Created $CORTEX_HOME/"
  fi
fi

# ─── Check 4: Scripts executable ──────────────────────────────────────

if [[ -d "$CORTEX_HOME/bin" ]]; then
  non_exec=0
  for script in "$CORTEX_HOME/bin/"*.sh; do
    [[ ! -f "$script" ]] && continue
    [[ ! -x "$script" ]] && non_exec=$((non_exec + 1))
  done

  if [[ $non_exec -eq 0 ]]; then
    pass "Scripts executable"
  else
    fail "$non_exec scripts not executable"
    if [[ "$FIX_MODE" == "true" ]]; then
      chmod +x "$CORTEX_HOME/bin/"*.sh 2>/dev/null || true
      fixed "Set execute permissions"
    fi
  fi
else
  fail "$CORTEX_HOME/bin/ does not exist"
fi

# ─── Check 5: Shell alias ────────────────────────────────────────────

alias_found=false
for rc in "$HOME/.zshrc" "$HOME/.bashrc" "$HOME/.bash_profile" "$HOME/.config/fish/config.fish"; do
  if [[ -f "$rc" ]] && grep -q 'alias cx=' "$rc" 2>/dev/null; then
    alias_found=true
    break
  fi
done

if [[ "$alias_found" == "true" ]]; then
  pass "cx alias configured"
else
  fail "cx alias not found in shell rc"
fi

# ─── Project-Specific Checks (only in git repos) ─────────────────────

if _cortex_is_git_repo; then
  REPO_ROOT=$(_cortex_project_root)

  # Check 6: .cortex/ directory
  if [[ -d "$REPO_ROOT/.cortex" ]]; then
    pass ".cortex/ initialized"
  else
    fail ".cortex/ not found in project"
    if [[ "$FIX_MODE" == "true" ]]; then
      mkdir -p "$REPO_ROOT/.cortex"
      fixed "Created .cortex/"
    fi
  fi

  # Check 7: Git hook installed
  HOOK_FILE="$REPO_ROOT/.git/hooks/post-commit"
  if [[ -f "$HOOK_FILE" ]] && grep -q "$HOOK_MARKER" "$HOOK_FILE" 2>/dev/null; then
    pass "Git hook installed (v1)"
  else
    fail "Git hook missing or outdated"
    if [[ "$FIX_MODE" == "true" ]] && [[ -f "$CORTEX_HOME/templates/post-commit.sh" ]]; then
      # shellcheck disable=SC2094
      [[ -f "$HOOK_FILE" ]] && printf '\n' >> "$HOOK_FILE"
      cat "$CORTEX_HOME/templates/post-commit.sh" >> "$HOOK_FILE"
      chmod +x "$HOOK_FILE"
      fixed "Installed git hook"
    fi
  fi

  # Check 8: commits.jsonl valid
  COMMITS_FILE="$REPO_ROOT/.cortex/commits.jsonl"
  if [[ -f "$COMMITS_FILE" ]]; then
    total_lines=$(wc -l < "$COMMITS_FILE" | tr -d ' ')
    invalid_lines=0

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "$line" | jq -e '.' >/dev/null 2>&1 || invalid_lines=$((invalid_lines + 1))
    done < "$COMMITS_FILE"

    if [[ $invalid_lines -eq 0 ]]; then
      pass "commits.jsonl valid ($total_lines entries)"
    else
      fail "commits.jsonl has $invalid_lines corrupted entries"
      if [[ "$FIX_MODE" == "true" ]]; then
        temp_file=$(mktemp)
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "$line" | jq -e '.' >/dev/null 2>&1 && echo "$line" >> "$temp_file"
        done < "$COMMITS_FILE"
        mv "$temp_file" "$COMMITS_FILE"
        fixed "Removed $invalid_lines corrupted entries"
      fi
    fi
  else
    pass "commits.jsonl (no commits yet)"
  fi

  # Check 9: sessions.jsonl valid
  SESSIONS_FILE="$REPO_ROOT/.cortex/sessions.jsonl"
  if [[ -f "$SESSIONS_FILE" ]]; then
    total_lines=$(wc -l < "$SESSIONS_FILE" | tr -d ' ')
    invalid_lines=0

    while IFS= read -r line; do
      [[ -z "$line" ]] && continue
      echo "$line" | jq -e '.' >/dev/null 2>&1 || invalid_lines=$((invalid_lines + 1))
    done < "$SESSIONS_FILE"

    if [[ $invalid_lines -eq 0 ]]; then
      sessions_count=$(grep -c '"type":"start"' "$SESSIONS_FILE" 2>/dev/null || echo 0)
      pass "sessions.jsonl valid ($sessions_count sessions)"
    else
      fail "sessions.jsonl has $invalid_lines corrupted entries"
      if [[ "$FIX_MODE" == "true" ]]; then
        temp_file=$(mktemp)
        while IFS= read -r line; do
          [[ -z "$line" ]] && continue
          echo "$line" | jq -e '.' >/dev/null 2>&1 && echo "$line" >> "$temp_file"
        done < "$SESSIONS_FILE"
        mv "$temp_file" "$SESSIONS_FILE"
        fixed "Removed $invalid_lines corrupted entries"
      fi
    fi
  else
    pass "sessions.jsonl (no sessions yet)"
  fi

  # Check 10: SESSION_CONTEXT.md freshness
  CONTEXT_FILE="$REPO_ROOT/SESSION_CONTEXT.md"
  if [[ -f "$CONTEXT_FILE" ]]; then
    if _cortex_is_macos; then
      file_mtime=$(stat -f %m "$CONTEXT_FILE" 2>/dev/null || echo 0)
    else
      file_mtime=$(stat -c %Y "$CONTEXT_FILE" 2>/dev/null || echo 0)
    fi
    now=$(date +%s)
    age_hours=$(( (now - file_mtime) / 3600 ))

    if [[ $age_hours -lt 24 ]]; then
      pass "Last context: ${age_hours}h ago"
    else
      fail "Context is stale (${age_hours}h old)"
    fi
  else
    pass "SESSION_CONTEXT.md (not yet generated)"
  fi
else
  echo "  (not in a git repo — skipping project checks)"
fi

# ─── Optional: Ollama ─────────────────────────────────────────────────

if command -v ollama &>/dev/null; then
  optional "Ollama: available"
else
  optional "Ollama: not configured (optional)"
fi

# ─── Summary ──────────────────────────────────────────────────────────

echo ""
if [[ $checks_failed -eq 0 ]]; then
  echo "Health: GOOD ($checks_passed/$required_total required checks passed)"
else
  echo "Health: ISSUES ($checks_failed/$required_total checks failed)"
  if [[ "$FIX_MODE" == "false" ]]; then
    echo ""
    echo "Run with --fix to auto-repair fixable issues"
  fi
fi

# Always exit 0 - doctor is a diagnostic tool, not a gating tool
# Scripts can parse output to detect issues if needed
exit 0
