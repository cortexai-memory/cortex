#!/usr/bin/env bash
# Cortex — Shared utility functions
# Sourced by all Cortex scripts. Never executed directly.
# shellcheck disable=SC2034

CORTEX_VERSION="0.1.0"
CORTEX_HOME="${CORTEX_HOME:-$HOME/.cortex}"

# ─── Platform Detection ──────────────────────────────────────────────

_cortex_is_macos() { [[ "$(uname -s)" == "Darwin" ]]; }
_cortex_is_linux() { [[ "$(uname -s)" == "Linux" ]]; }

_cortex_has_gnu_date() {
  date --version >/dev/null 2>&1
}

# ─── Date Functions ──────────────────────────────────────────────────

# UTC ISO 8601 timestamp (works on both macOS and Linux)
_cortex_date_iso() {
  date -u +%FT%TZ
}

# Date N units ago as ISO timestamp
# Usage: _cortex_date_ago "24H" or _cortex_date_ago "30d"
_cortex_date_ago() {
  local spec="$1"
  if _cortex_has_gnu_date; then
    # GNU date (Linux)
    local amount="${spec%[HhDdMm]}"
    local unit="${spec: -1}"
    case "$unit" in
      H|h) date -u -d "$amount hours ago" +%FT%TZ ;;
      D|d) date -u -d "$amount days ago" +%FT%TZ ;;
      M|m) date -u -d "$amount minutes ago" +%FT%TZ ;;
      *)   date -u -d "$amount hours ago" +%FT%TZ ;;
    esac
  else
    # BSD date (macOS)
    local amount="${spec%[HhDdMm]}"
    local unit="${spec: -1}"
    case "$unit" in
      H|h) date -u -v-"${amount}H" +%FT%TZ ;;
      D|d) date -u -v-"${amount}d" +%FT%TZ ;;
      M|m) date -u -v-"${amount}M" +%FT%TZ ;;
      *)   date -u -v-"${amount}H" +%FT%TZ ;;
    esac
  fi
}

# ─── JSON Functions ──────────────────────────────────────────────────

# Escape a string for safe JSON embedding
# Uses jq if available, falls back to sed
_cortex_json_escape() {
  local input="$1"
  if command -v jq >/dev/null 2>&1; then
    printf '%s' "$input" | jq -Rs '.'
  else
    # Fallback: escape critical chars
    printf '"%s"' "$(printf '%s' "$input" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e 's/\t/\\t/g' | tr '\n' ' ')"
  fi
}

# Atomically append a line to a JSONL file
# Usage: _cortex_safe_jsonl_append "file.jsonl" '{"key":"value"}'
_cortex_safe_jsonl_append() {
  local file="$1"
  local json_line="$2"
  local dir
  dir=$(dirname "$file")

  mkdir -p "$dir"

  # Validate JSON if jq is available
  if command -v jq >/dev/null 2>&1; then
    if ! printf '%s' "$json_line" | jq -e '.' >/dev/null 2>&1; then
      _cortex_log warn "Invalid JSON, skipping append: $json_line"
      return 1
    fi
  fi

  # Atomic append using lock file
  local lockfile="${file}.lock"
  local retries=3
  local i=0

  while [[ $i -lt $retries ]]; do
    if (set -o noclobber; echo "$$" > "$lockfile") 2>/dev/null; then
      # Got the lock
      printf '%s\n' "$json_line" >> "$file"
      rm -f "$lockfile"
      return 0
    fi
    i=$((i + 1))
    sleep 0.1
  done

  # Fallback: append without lock (better than losing data)
  printf '%s\n' "$json_line" >> "$file"
}

# ─── Logging ─────────────────────────────────────────────────────────

# Structured logging
# Usage: _cortex_log info "message"
_cortex_log() {
  local level="$1"
  shift
  local message="$*"

  [[ "${CORTEX_QUIET:-0}" == "1" ]] && return 0

  case "$level" in
    info)  echo "[Cortex] $message" ;;
    warn)  echo "[Cortex] Warning: $message" >&2 ;;
    error) echo "[Cortex] Error: $message" >&2 ;;
    *)     echo "[Cortex] $message" ;;
  esac
}

# ─── Dependency Checking ─────────────────────────────────────────────

# Check that required tools exist
# Usage: _cortex_require git jq
_cortex_require() {
  local missing=()
  for tool in "$@"; do
    if ! command -v "$tool" >/dev/null 2>&1; then
      missing+=("$tool")
    fi
  done

  if [[ ${#missing[@]} -gt 0 ]]; then
    _cortex_log error "Missing required tools: ${missing[*]}"
    for tool in "${missing[@]}"; do
      case "$tool" in
        jq)
          if _cortex_is_macos; then
            _cortex_log error "  Install: brew install jq"
          else
            _cortex_log error "  Install: sudo apt-get install jq"
          fi
          ;;
        git)
          _cortex_log error "  Install git from https://git-scm.com"
          ;;
        *)
          _cortex_log error "  Install $tool and ensure it's in PATH"
          ;;
      esac
    done
    return 1
  fi
}

# ─── Project Detection ───────────────────────────────────────────────

# Find the project root directory
# Returns git root if in a repo, otherwise pwd
_cortex_project_root() {
  local dir="${1:-}"
  if [[ -n "$dir" ]] && [[ -d "$dir" ]]; then
    (cd "$dir" && git rev-parse --show-toplevel 2>/dev/null) || echo "$dir"
  else
    git rev-parse --show-toplevel 2>/dev/null || pwd
  fi
}

# Check if we're inside a git repository
_cortex_is_git_repo() {
  local dir="${1:-.}"
  # Check if inside work tree
  if (cd "$dir" && git rev-parse --is-inside-work-tree >/dev/null 2>&1); then
    return 0
  fi
  # Bare repositories are technically git repos, allow them (with limited functionality)
  if (cd "$dir" && git rev-parse --is-bare-repository 2>/dev/null | grep -q "true"); then
    return 0
  fi
  return 1
}

# ─── UUID Generation ─────────────────────────────────────────────────

# Generate a unique session ID (cross-platform)
_cortex_uuid() {
  if command -v uuidgen >/dev/null 2>&1; then
    uuidgen | tr '[:upper:]' '[:lower:]'
  elif [[ -f /proc/sys/kernel/random/uuid ]]; then
    cat /proc/sys/kernel/random/uuid
  else
    # Fallback: timestamp + random
    printf '%s-%04x' "$(date +%s)" "$RANDOM"
  fi
}
