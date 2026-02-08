#!/usr/bin/env bats
# Cortex Snapshot Tests — Session memory without commits

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
# SNAPSHOT TESTS (7)
# ═══════════════════════════════════════════════════════════════════════

@test "snapshot: captures uncommitted work" {
  cd "$TEST_REPO"
  mkdir -p .cortex/snapshots

  # Create uncommitted changes
  echo "new feature" > feature.txt
  git add feature.txt

  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' capture test-snapshot
  "
  [ "$status" -eq 0 ]

  # Check snapshot files created
  [ -f "$TEST_REPO/.cortex/snapshots/test-snapshot.snapshot" ]
  [ -f "$TEST_REPO/.cortex/snapshots/test-snapshot.diff" ]
  [ -f "$TEST_REPO/.cortex/snapshots/test-snapshot.files" ]
}

@test "snapshot: lists snapshots" {
  cd "$TEST_REPO"
  mkdir -p .cortex/snapshots

  # Create uncommitted changes and snapshot
  echo "change" >> file.txt
  git add file.txt
  bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' capture snap1
  "

  # List snapshots
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    cd '$TEST_REPO'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' list
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "snap1" ]]
}

@test "snapshot: shows snapshot details" {
  cd "$TEST_REPO"
  mkdir -p .cortex/snapshots

  # Create uncommitted changes and snapshot
  echo "change" >> file.txt
  git add file.txt
  bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' capture details-test
  " 2>/dev/null

  # Show snapshot
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    cd '$TEST_REPO'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' show details-test
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "Session ID" ]]
  [[ "$output" =~ "details-test" ]]
}

@test "snapshot: handles no uncommitted work" {
  cd "$TEST_REPO"
  mkdir -p .cortex/snapshots

  # No uncommitted changes
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' capture empty-test
  "
  [ "$status" -eq 0 ]
  [[ "$output" =~ "No uncommitted work" ]]
}

@test "snapshot: clears old snapshots" {
  cd "$TEST_REPO"
  mkdir -p .cortex/snapshots

  # Create an old snapshot manually
  local OLD_TS="2020-01-01T00:00:00Z"
  echo "{\"timestamp\":\"$OLD_TS\",\"session_id\":\"old-snap\",\"uncommitted_files\":1}" > .cortex/snapshots/old-snap.snapshot
  touch .cortex/snapshots/old-snap.diff
  touch .cortex/snapshots/old-snap.files

  # Clear snapshots older than 1 day
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    cd '$TEST_REPO'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' clear 1
  "
  [ "$status" -eq 0 ]

  # Old snapshot should be removed
  [ ! -f "$TEST_REPO/.cortex/snapshots/old-snap.snapshot" ]
}

@test "snapshot: included in context when present" {
  cd "$TEST_REPO"
  mkdir -p .cortex/snapshots

  # Create uncommitted changes and snapshot
  echo "uncommitted work" >> file.txt
  git add file.txt
  bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' capture context-test
  " 2>/dev/null

  # Generate context
  run bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-context.sh' '$TEST_REPO'
  "
  [ "$status" -eq 0 ]
  [ -f "$TEST_REPO/SESSION_CONTEXT.md" ]

  # Context should mention uncommitted work
  grep -q "uncommitted" "$TEST_REPO/SESSION_CONTEXT.md" || \
    grep -q "PREVIOUS SESSION" "$TEST_REPO/SESSION_CONTEXT.md"
}

@test "snapshot: latest symlink updated" {
  cd "$TEST_REPO"
  mkdir -p .cortex/snapshots

  # Create uncommitted changes and snapshot
  echo "change" >> file.txt
  git add file.txt
  bash -c "
    export CORTEX_HOME='$CORTEX_HOME'
    '$CORTEX_HOME/bin/cortex-snapshot.sh' capture symlink-test
  " 2>/dev/null

  # Check symlink exists and points to latest
  [ -L "$TEST_REPO/.cortex/snapshots/latest.snapshot" ]
  local target
  target=$(readlink "$TEST_REPO/.cortex/snapshots/latest.snapshot")
  [[ "$target" == *"symlink-test.snapshot" ]]
}
