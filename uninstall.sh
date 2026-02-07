#!/usr/bin/env bash
# Cortex Uninstaller — Clean removal
# Usage: uninstall.sh [--force]
set -uo pipefail

CORTEX_HOME="${CORTEX_HOME:-$HOME/.cortex}"

echo ''
echo 'Cortex Uninstaller'
echo '──────────────────'
echo ''

# ─── Confirmation ─────────────────────────────────────────────────────

if [[ "${1:-}" != "--force" ]]; then
  echo "This will remove:"
  echo "  - $CORTEX_HOME/ (scripts, config, registry)"
  echo "  - 'cx' alias from your shell config"
  echo "  - Git hooks from all registered projects"
  echo ""
  echo "Per-project .cortex/ directories will NOT be removed."
  echo ""
  printf "Continue? [y/N] "
  read -r confirm
  if [[ "$confirm" != "y" ]] && [[ "$confirm" != "Y" ]]; then
    echo "Cancelled."
    exit 0
  fi
fi

# ─── Remove Git Hooks ────────────────────────────────────────────────

REMOVED_HOOKS=0
if [[ -f "$CORTEX_HOME/registry.jsonl" ]]; then
  while IFS= read -r line; do
    PROJECT_PATH=$(echo "$line" | jq -r '.path // empty' 2>/dev/null) || continue
    [[ -z "$PROJECT_PATH" ]] && continue

    HOOK="$PROJECT_PATH/.git/hooks/post-commit"
    if [[ -f "$HOOK" ]] && grep -q 'cortex-hook-v1' "$HOOK" 2>/dev/null; then
      # Remove cortex section from hook
      sed '/# --- cortex-hook-v1 ---/,/# --- cortex-hook-v1 ---/d' "$HOOK" > "${HOOK}.tmp" 2>/dev/null
      if [[ -s "${HOOK}.tmp" ]]; then
        mv "${HOOK}.tmp" "$HOOK"
      else
        rm -f "$HOOK" "${HOOK}.tmp"
      fi
      REMOVED_HOOKS=$((REMOVED_HOOKS + 1))
    fi
  done < "$CORTEX_HOME/registry.jsonl"
fi
echo "✓ Removed hooks from $REMOVED_HOOKS projects"

# ─── Remove Shell Alias ──────────────────────────────────────────────

remove_alias_from() {
  local rc_file="$1"
  [[ ! -f "$rc_file" ]] && return

  if grep -q 'cortex' "$rc_file" 2>/dev/null; then
    # Remove cortex-related lines
    grep -v -E '(# Cortex|alias cx=|CORTEX_ENRICH)' "$rc_file" > "${rc_file}.tmp" 2>/dev/null
    mv "${rc_file}.tmp" "$rc_file"
    echo "✓ Removed alias from $(basename "$rc_file")"
  fi
}

remove_alias_from "$HOME/.zshrc"
remove_alias_from "$HOME/.bashrc"
remove_alias_from "$HOME/.bash_profile"
remove_alias_from "$HOME/.config/fish/config.fish"

# ─── Remove Cortex Home ──────────────────────────────────────────────

if [[ -d "$CORTEX_HOME" ]]; then
  rm -rf "$CORTEX_HOME"
  echo "✓ Removed $CORTEX_HOME"
fi

# ─── Done ─────────────────────────────────────────────────────────────

echo ''
echo '✅ Cortex uninstalled.'
echo ''
echo 'Note: Per-project .cortex/ directories were preserved.'
echo 'To remove them: find ~ -name ".cortex" -type d -maxdepth 4'
echo ''
