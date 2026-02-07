#!/usr/bin/env bash
# Cortex Compaction — Archives old data, prevents storage growth
# Usage: cortex-compact.sh
# Env: CORTEX_RETENTION_DAYS (default: 30)

set -uo pipefail

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
RETENTION_DAYS="${CORTEX_RETENTION_DAYS:-30}"
REGISTRY_FILE="$CORTEX_HOME/registry.jsonl"
SESSION_CAP=200

# Counters
total_projects=0
total_commits_removed=0
total_summaries_removed=0
projects_cleaned=0

# ─── Check Registry ──────────────────────────────────────────────────

if [[ ! -f "$REGISTRY_FILE" ]]; then
  _cortex_log info "No registry found. Nothing to compact."
  exit 0
fi

# Calculate retention cutoff as ISO timestamp
CUTOFF=$(_cortex_date_ago "${RETENTION_DAYS}d" 2>/dev/null || echo "2000-01-01T00:00:00Z")

_cortex_log info "Starting compaction (retention: ${RETENTION_DAYS} days)..."

# ─── Process Each Project ─────────────────────────────────────────────
# CRITICAL: Use `while IFS= read -r` to handle paths with spaces

while IFS= read -r line; do
  [[ -z "$line" ]] && continue

  # Parse project path (skip corrupted entries)
  project_path=$(echo "$line" | jq -r '.path // empty' 2>/dev/null) || continue
  [[ -z "$project_path" ]] && continue

  cortex_dir="$project_path/.cortex"
  [[ ! -d "$cortex_dir" ]] && continue

  total_projects=$((total_projects + 1))
  project_commits_removed=0
  project_summaries_removed=0

  # 1. Trim commits.jsonl — remove entries older than cutoff
  commits_file="$cortex_dir/commits.jsonl"
  if [[ -f "$commits_file" ]]; then
    temp_file=$(mktemp)

    while IFS= read -r commit_line; do
      [[ -z "$commit_line" ]] && continue

      # Extract timestamp, skip corrupted entries
      ts=$(echo "$commit_line" | jq -r '.t // empty' 2>/dev/null) || continue
      [[ -z "$ts" ]] && continue

      # Keep if timestamp >= cutoff (string comparison works for ISO dates)
      if [[ "$ts" > "$CUTOFF" ]] || [[ "$ts" == "$CUTOFF" ]]; then
        echo "$commit_line" >> "$temp_file"
      else
        project_commits_removed=$((project_commits_removed + 1))
      fi
    done < "$commits_file"

    if [[ $project_commits_removed -gt 0 ]]; then
      mv "$temp_file" "$commits_file"
      total_commits_removed=$((total_commits_removed + project_commits_removed))
    else
      rm -f "$temp_file"
    fi
  fi

  # 2. Remove old summary files (keep latest.md)
  summaries_dir="$cortex_dir/summaries"
  if [[ -d "$summaries_dir" ]]; then
    while IFS= read -r summary_file; do
      [[ -z "$summary_file" ]] && continue

      # Cross-platform mtime check
      if _cortex_is_macos; then
        file_mtime=$(stat -f %m "$summary_file" 2>/dev/null || echo 0)
      else
        file_mtime=$(stat -c %Y "$summary_file" 2>/dev/null || echo 0)
      fi

      cutoff_epoch=$(date -u +%s)
      cutoff_epoch=$((cutoff_epoch - (RETENTION_DAYS * 86400)))

      if [[ "$file_mtime" -lt "$cutoff_epoch" ]]; then
        rm -f "$summary_file"
        project_summaries_removed=$((project_summaries_removed + 1))
      fi
    done < <(find "$summaries_dir" -type f -name '*.md' ! -name 'latest.md' 2>/dev/null || true)

    total_summaries_removed=$((total_summaries_removed + project_summaries_removed))
  fi

  # 3. Cap sessions.jsonl to last SESSION_CAP lines
  sessions_file="$cortex_dir/sessions.jsonl"
  if [[ -f "$sessions_file" ]]; then
    line_count=$(wc -l < "$sessions_file" | tr -d ' ')
    if [[ "$line_count" -gt "$SESSION_CAP" ]]; then
      temp_sessions=$(mktemp)
      tail -"$SESSION_CAP" "$sessions_file" > "$temp_sessions"
      mv "$temp_sessions" "$sessions_file"
    fi
  fi

  if [[ $project_commits_removed -gt 0 || $project_summaries_removed -gt 0 ]]; then
    projects_cleaned=$((projects_cleaned + 1))
  fi

done < "$REGISTRY_FILE"

# ─── Report ───────────────────────────────────────────────────────────

_cortex_log info "Compaction complete: removed $total_commits_removed old commits, $total_summaries_removed old summaries across $projects_cleaned/$total_projects projects"

exit 0
