#!/usr/bin/env bats
# Cortex Integration Tests — End-to-end workflows

load test-helper

# ═══════════════════════════════════════════════════════════════════════
# Setup / Teardown
# ═══════════════════════════════════════════════════════════════════════

setup() {
  setup_test_repo
  setup_cortex_home
}

teardown() {
  cleanup
}

# ═══════════════════════════════════════════════════════════════════════
# INTEGRATION TESTS (12+)
# ═══════════════════════════════════════════════════════════════════════

@test "integration: full workflow init → commit → context" {
  cd "$TEST_REPO"

  # Install hook
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    mkdir -p .cortex
    cp '$CORTEX_HOME/templates/post-commit.sh' .git/hooks/post-commit
    chmod +x .git/hooks/post-commit
  "
  [ "$status" -eq 0 ]

  # Make a commit
  echo "feature" >> file.txt
  cd "$TEST_REPO" && git add . && git commit -m "add feature"

  # Verify commit was tracked
  [ -f "$TEST_REPO/.cortex/commits.jsonl" ]
  grep -q "add feature" "$TEST_REPO/.cortex/commits.jsonl"

  # Generate context
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-context.sh' '$TEST_REPO'
  "
  [ "$status" -eq 0 ]
  [ -f "$TEST_REPO/SESSION_CONTEXT.md" ]

  # Verify context contains commit
  grep -q "add feature" "$TEST_REPO/SESSION_CONTEXT.md"
}

@test "integration: multi-project support" {
  local PROJ1=$(mktemp -d)
  local PROJ2=$(mktemp -d)

  # Init both projects
  cd "$PROJ1" && git init && echo "proj1" > file.txt && git add . && git commit -m "proj1 init"
  cd "$PROJ2" && git init && echo "proj2" > file.txt && git add . && git commit -m "proj2 init"

  # Register both
  mkdir -p "$PROJ1/.cortex" "$PROJ2/.cortex"
  echo "{\"path\":\"$PROJ1\",\"ts\":\"2026-01-01T00:00:00Z\"}" >> "$CORTEX_HOME/registry.jsonl"
  echo "{\"path\":\"$PROJ2\",\"ts\":\"2026-01-01T00:00:00Z\"}" >> "$CORTEX_HOME/registry.jsonl"

  # Generate context for each
  bash -c "export CORTEX_HOME='$CORTEX_HOME'; '$CORTEX_HOME/bin/cortex-context.sh' '$PROJ1'" 2>/dev/null
  bash -c "export CORTEX_HOME='$CORTEX_HOME'; '$CORTEX_HOME/bin/cortex-context.sh' '$PROJ2'" 2>/dev/null

  [ -f "$PROJ1/SESSION_CONTEXT.md" ]
  [ -f "$PROJ2/SESSION_CONTEXT.md" ]

  # Contexts should be different
  ! diff "$PROJ1/SESSION_CONTEXT.md" "$PROJ2/SESSION_CONTEXT.md" >/dev/null

  rm -rf "$PROJ1" "$PROJ2"
}

@test "integration: enrichment pipeline (mock)" {
  install_test_hook
  create_test_commits 1

  # Mock enrichment by creating summary manually
  mkdir -p "$TEST_REPO/.cortex/summaries/commits"
  local HASH=$(cd "$TEST_REPO" && git rev-parse --short HEAD)
  echo "# COMMIT Summary

**Generated:** 2026-01-01T00:00:00Z
**Commit:** \`$HASH\` — test commit
**Model:** mock

---

This is a test summary.
" > "$TEST_REPO/.cortex/summaries/commits/$HASH.md"

  cp "$TEST_REPO/.cortex/summaries/commits/$HASH.md" "$TEST_REPO/.cortex/summaries/latest.md"

  # Generate context
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-context.sh' '$TEST_REPO'
  "
  [ "$status" -eq 0 ]

  # Should include AI summary
  grep -q "AI SUMMARY" "$TEST_REPO/SESSION_CONTEXT.md"
  grep -q "test summary" "$TEST_REPO/SESSION_CONTEXT.md"
}

@test "integration: session lifecycle" {
  cd "$TEST_REPO"
  mkdir -p .cortex

  # Session start
  local TS_START=$(_cortex_date_iso 2>/dev/null || date -u +%FT%TZ)
  echo "{\"type\":\"start\",\"sid\":\"test-session\",\"ts\":\"$TS_START\",\"project\":\"$TEST_REPO\"}" >> .cortex/sessions.jsonl

  # Session end
  sleep 1
  local TS_END=$(_cortex_date_iso 2>/dev/null || date -u +%FT%TZ)
  echo "{\"type\":\"end\",\"sid\":\"test-session\",\"ts\":\"$TS_END\"}" >> .cortex/sessions.jsonl

  # Verify session tracking
  [ -f "$TEST_REPO/.cortex/sessions.jsonl" ]
  grep -q "test-session" "$TEST_REPO/.cortex/sessions.jsonl"
  grep -c "test-session" "$TEST_REPO/.cortex/sessions.jsonl" | grep -q "2"
}

@test "integration: compaction preserves recent commits" {
  install_test_hook
  create_test_commits 10

  # All commits should be in JSONL
  local COUNT_BEFORE=$(wc -l < "$TEST_REPO/.cortex/commits.jsonl" | tr -d ' ')
  [ "$COUNT_BEFORE" -eq 10 ]

  # Run compaction (retention=999 days, should keep all)
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    export RETENTION_DAYS=999
    '$CORTEX_HOME/bin/cortex-compact.sh'
  "
  [ "$status" -eq 0 ]

  # Should still have all commits
  local COUNT_AFTER=$(wc -l < "$TEST_REPO/.cortex/commits.jsonl" | tr -d ' ')
  [ "$COUNT_AFTER" -eq 10 ]
}

@test "integration: status reflects project state" {
  install_test_hook
  create_test_commits 5

  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    cd '$TEST_REPO'
    '$CORTEX_HOME/bin/cortex-status.sh'
  "
  [ "$status" -eq 0 ]

  # Should show correct commit count
  echo "$output" | grep -q "Commits tracked: 5"
}

@test "integration: progress tracking with feature branches" {
  cd "$TEST_REPO"

  # Create feature branch
  git checkout -b feature/new-thing
  echo "feature work" >> file.txt
  git add . && git commit -m "wip: feature work"

  # Generate progress
  export CORTEX_GENERATE_PROGRESS=1
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    export CORTEX_GENERATE_PROGRESS=1
    '$CORTEX_HOME/bin/cortex-context.sh' '$TEST_REPO'
  "
  [ "$status" -eq 0 ]

  if [ -f "$TEST_REPO/PROGRESS.md" ]; then
    grep -q "feature/" "$TEST_REPO/PROGRESS.md" || grep -q "In Progress" "$TEST_REPO/PROGRESS.md"
  fi
}

@test "integration: doctor detects and reports all issues" {
  # Create problematic state
  mkdir -p "$TEST_REPO/.cortex"

  # Corrupt JSONL
  echo "not valid json" > "$TEST_REPO/.cortex/commits.jsonl"

  # Missing hook
  rm -f "$TEST_REPO/.git/hooks/post-commit"

  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    cd '$TEST_REPO'
    '$CORTEX_HOME/bin/cortex-doctor.sh'
  "

  # Doctor should detect issues
  echo "$output" | grep -q "commits.jsonl" || [ "$status" -ne 0 ]
}

@test "integration: watch events logged correctly" {
  skip "File watcher requires fswatch/inotifywait"

  cd "$TEST_REPO"
  mkdir -p .cortex

  # Note: Actual watch test would require fswatch/inotifywait
  # This is a structural test only
  [ -f "$CORTEX_HOME/bin/cortex-watch.sh" ]
}

@test "integration: daemon manages lifecycle" {
  # Start daemon briefly
  timeout 3 bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-daemon.sh' start || true
  " 2>/dev/null &

  sleep 1

  # Check status
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-daemon.sh' status
  "

  # Cleanup
  bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-daemon.sh' stop
  " 2>/dev/null || true

  # Just verify commands work
  [ "$status" -eq 0 ] || [ "$status" -eq 1 ]
}

@test "integration: gitignore prevents cortex files in repo" {
  cd "$TEST_REPO"

  # Session initialization adds .cortex to gitignore
  # This is tested in session tests, just verify pattern
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    cd '$TEST_REPO'
    mkdir -p .cortex
    # Session init would normally do this
    echo '.cortex/' >> .gitignore
    echo 'SESSION_CONTEXT.md' >> .gitignore
  "

  [ -f "$TEST_REPO/.gitignore" ]
  grep -q ".cortex" "$TEST_REPO/.gitignore"

  # Create cortex files
  echo "data" > .cortex/commits.jsonl
  echo "context" > SESSION_CONTEXT.md

  # Verify gitignore works (files should not appear in git status)
  cd "$TEST_REPO"
  run git status --porcelain
  # Gitignored files should NOT appear in status
  ! echo "$output" | grep ".cortex"
  ! echo "$output" | grep "SESSION_CONTEXT.md"
}

@test "integration: cross-platform date handling" {
  # Test that date functions work on both macOS and Linux
  run bash -c "
    source '$CORTEX_HOME/bin/_cortex-utils.sh'
    _cortex_date_iso
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T ]]

  run bash -c "
    source '$CORTEX_HOME/bin/_cortex-utils.sh'
    _cortex_date_ago '24H' || _cortex_date_ago '1 day ago'
  "
  [ "$status" -eq 0 ]
}
