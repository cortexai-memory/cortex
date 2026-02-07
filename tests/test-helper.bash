#!/usr/bin/env bash
# Shared test utilities for Cortex bats tests

# Create a temporary git repository for testing
setup_test_repo() {
  export TEST_REPO=$(mktemp -d)
  cd "$TEST_REPO" || return 1
  git init
  git config user.email "test@cortex.dev"
  git config user.name "Cortex Test"
  echo "hello" > file.txt
  git add . && git commit -m "initial commit"
}

# Create a temporary CORTEX_HOME
setup_cortex_home() {
  export CORTEX_HOME=$(mktemp -d)
  mkdir -p "$CORTEX_HOME"/{bin,templates}
  cp "$BATS_TEST_DIRNAME/../bin/"*.sh "$CORTEX_HOME/bin/" 2>/dev/null || true
  cp "$BATS_TEST_DIRNAME/../templates/"*.sh "$CORTEX_HOME/templates/" 2>/dev/null || true
  chmod +x "$CORTEX_HOME/bin/"*.sh 2>/dev/null || true
  chmod +x "$CORTEX_HOME/templates/"*.sh 2>/dev/null || true

  # Create minimal config
  cat > "$CORTEX_HOME/config" << 'EOF'
llm_provider=none
llm_model=qwen2.5-coder:7b
EOF
}

# Clean up all temp directories
cleanup() {
  [[ -n "${TEST_REPO:-}" ]] && rm -rf "$TEST_REPO"
  [[ -n "${CORTEX_HOME:-}" ]] && rm -rf "$CORTEX_HOME"
}

# Create N test commits in the test repo
create_test_commits() {
  local count="${1:-3}"
  cd "$TEST_REPO" || return 1
  for i in $(seq 1 "$count"); do
    echo "change $i" >> file.txt
    git add . && git commit -m "test commit $i"
  done
}

# Install the cortex hook in the test repo
install_test_hook() {
  local hook="$TEST_REPO/.git/hooks/post-commit"
  cat "$CORTEX_HOME/templates/post-commit.sh" > "$hook"
  chmod +x "$hook"
  mkdir -p "$TEST_REPO/.cortex"
}

# Add corrupted lines to a JSONL file
corrupt_jsonl() {
  local file="$1"
  echo "this is not json" >> "$file"
  echo '{"valid":true}' >> "$file"
  echo "another bad line {{{" >> "$file"
}
