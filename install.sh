#!/usr/bin/env bash
# Cortex Installer
# Works both cloned (./install.sh) and piped (curl -fsSL url | bash)
# Idempotent — safe to run multiple times
set -euo pipefail

CORTEX_HOME="${CORTEX_HOME:-$HOME/.cortex}"
CORTEX_REPO="cortex-memory/cortex"

# ─── Banner ───────────────────────────────────────────────────────────

echo ''
echo '  ____          _            '
echo ' / ___|___  _ __| |_ _____  __'
echo '| |   / _ \| __| __/ _ \ \/ /'
echo '| |__| (_) | |  | ||  __/>  < '
# shellcheck disable=SC1003
echo ' \____\___/|_|   \__\___/_/\_\'
echo ''
echo 'Persistent memory for AI coding assistants'
echo '───────────────────────────────────────────'
echo ''

# ─── Handle --uninstall flag ──────────────────────────────────────────

if [[ "${1:-}" == "--uninstall" ]]; then
  if [[ -f "$CORTEX_HOME/bin/uninstall.sh" ]]; then
    exec "$CORTEX_HOME/bin/uninstall.sh" "${@:2}"
  else
    echo "[Cortex] Uninstaller not found. Remove manually: rm -rf ~/.cortex"
    exit 1
  fi
fi

# ─── Dependency Check ─────────────────────────────────────────────────

check_dep() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Error: $1 is required but not installed."
    case "$1" in
      git) echo "  Install: https://git-scm.com" ;;
      jq)
        if [[ "$(uname -s)" == "Darwin" ]]; then
          echo "  Install: brew install jq"
        else
          echo "  Install: sudo apt-get install -y jq"
        fi
        ;;
    esac
    exit 1
  fi
}

check_dep git
check_dep jq

echo "✓ git $(git --version | awk '{print $3}')"
echo "✓ jq $(jq --version 2>/dev/null | sed 's/jq-//')"

# ─── Locate Source Files ──────────────────────────────────────────────

CLEANUP_TMPDIR=0
SCRIPT_DIR=""

# Detect if running from cloned repo or piped
if [[ -t 0 ]] && [[ -f "${BASH_SOURCE[0]:-}" ]]; then
  CANDIDATE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  if [[ -f "$CANDIDATE/bin/cortex-context.sh" ]]; then
    SCRIPT_DIR="$CANDIDATE"
  fi
fi

if [[ -z "$SCRIPT_DIR" ]]; then
  # Piped mode or files not found — download from GitHub
  echo ""
  echo "Downloading Cortex..."
  TMPDIR=$(mktemp -d)
  CLEANUP_TMPDIR=1

  # Try latest release tag, fallback to main
  TAG=$(curl -sS "https://api.github.com/repos/$CORTEX_REPO/releases/latest" 2>/dev/null | jq -r '.tag_name // empty' 2>/dev/null || true)
  if [[ -n "$TAG" ]]; then
    curl -sL "https://github.com/$CORTEX_REPO/archive/$TAG.tar.gz" | tar xz -C "$TMPDIR" --strip-components=1
  else
    curl -sL "https://github.com/$CORTEX_REPO/archive/main.tar.gz" | tar xz -C "$TMPDIR" --strip-components=1
  fi
  SCRIPT_DIR="$TMPDIR"
fi

if [[ ! -d "$SCRIPT_DIR/bin" ]]; then
  echo "Error: Could not locate Cortex source files."
  [[ "$CLEANUP_TMPDIR" -eq 1 ]] && rm -rf "$TMPDIR"
  exit 1
fi

# ─── Install Files ────────────────────────────────────────────────────

echo ""
echo "Installing to $CORTEX_HOME..."

mkdir -p "$CORTEX_HOME"/{bin,templates}

# Copy scripts
cp "$SCRIPT_DIR/bin/"*.sh "$CORTEX_HOME/bin/" 2>/dev/null || true
cp "$SCRIPT_DIR/templates/"*.sh "$CORTEX_HOME/templates/" 2>/dev/null || true

# Set permissions
chmod +x "$CORTEX_HOME/bin/"*.sh 2>/dev/null || true
chmod +x "$CORTEX_HOME/templates/"*.sh 2>/dev/null || true

echo "✓ Scripts installed"

# ─── Default Config ───────────────────────────────────────────────────

if [[ ! -f "$CORTEX_HOME/config" ]]; then
  cat > "$CORTEX_HOME/config" << 'CFG'
# Cortex Configuration
# ────────────────────

# LLM provider for richer commit summaries (optional)
# Options: none | ollama | openrouter | gemini
llm_provider=none

# Model to use (provider-specific)
llm_model=qwen2.5-coder:7b

# API keys (uncomment and fill in if using cloud providers)
# openrouter_key=sk-or-...
# gemini_key=AI...

# Retention: days to keep commit history (default: 30)
# retention_days=30
CFG
  echo "✓ Config created"
else
  echo "✓ Config exists (preserved)"
fi

# ─── Shell Alias ──────────────────────────────────────────────────────

detect_shell_rc() {
  if [[ -n "${ZSH_VERSION:-}" ]] || [[ "${SHELL:-}" == */zsh ]]; then
    echo "$HOME/.zshrc"
  elif [[ "${SHELL:-}" == */fish ]]; then
    echo "$HOME/.config/fish/config.fish"
  elif [[ -f "$HOME/.bashrc" ]]; then
    echo "$HOME/.bashrc"
  elif [[ -f "$HOME/.bash_profile" ]]; then
    echo "$HOME/.bash_profile"
  else
    echo "$HOME/.bashrc"
  fi
}

SHELL_RC=$(detect_shell_rc)
ALIAS_INSTALLED=0

if [[ "$SHELL_RC" == *.fish ]]; then
  # Fish shell uses different syntax
  mkdir -p "$(dirname "$SHELL_RC")"
  if ! grep -q 'alias cx' "$SHELL_RC" 2>/dev/null; then
    {
      echo ''
      echo '# Cortex — persistent memory for AI coding'
      echo "alias cx=\"$CORTEX_HOME/bin/cortex-session.sh\""
      echo "set -gx CORTEX_ENRICH 0"
    } >> "$SHELL_RC"
    ALIAS_INSTALLED=1
  fi
else
  # Bash/Zsh
  if ! grep -q 'alias cx=' "$SHELL_RC" 2>/dev/null; then
    {
      echo ''
      echo '# Cortex — persistent memory for AI coding'
      echo "alias cx=\"\$HOME/.cortex/bin/cortex-session.sh\""
      echo "export CORTEX_ENRICH=0  # Set to 1 to enable LLM enrichment"
    } >> "$SHELL_RC"
    ALIAS_INSTALLED=1
  fi
fi

if [[ "$ALIAS_INSTALLED" -eq 1 ]]; then
  echo "✓ Shell alias 'cx' added to $(basename "$SHELL_RC")"
else
  echo "✓ Shell alias 'cx' already configured"
fi

# ─── Cleanup ──────────────────────────────────────────────────────────

[[ "$CLEANUP_TMPDIR" -eq 1 ]] && rm -rf "$TMPDIR"

# ─── Done ─────────────────────────────────────────────────────────────

echo ''
echo '───────────────────────────────────────────'
echo '✅ Cortex installed!'
echo ''
echo 'Quick start:'
echo "  source $SHELL_RC    # reload shell (one time)"
echo '  cd your-project      # navigate to any project'
echo '  cx                   # instead of "claude"'
echo ''
echo 'Optional: Enable LLM enrichment for richer context'
echo "  edit ~/.cortex/config → set llm_provider=ollama"
echo '  export CORTEX_ENRICH=1'
echo ''
echo 'Health check:'
echo '  ~/.cortex/bin/cortex-doctor.sh'
echo ''
