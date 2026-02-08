#!/usr/bin/env bash
# Demo Script 1: Quick Start (30 seconds)
# Use with asciinema or similar: asciinema rec quickstart.cast

set -e

# Print with delays for readability
print_cmd() {
    echo "$ $1"
    sleep 0.5
    eval "$1"
    sleep 1
}

clear
echo "════════════════════════════════════════════════"
echo "  Cortex Quick Start Demo"
echo "  From zero to AI memory in 30 seconds"
echo "════════════════════════════════════════════════"
echo ""
sleep 2

# Step 1: Install
echo "Step 1: Install Cortex"
echo ""
print_cmd "curl -fsSL https://raw.githubusercontent.com/cortexai-memory/cortex/main/install.sh | bash"

# Step 2: Source config
echo ""
echo "Step 2: Reload shell"
echo ""
print_cmd "source ~/.zshrc"

# Step 3: Navigate to project
echo ""
echo "Step 3: Navigate to your project"
echo ""
print_cmd "cd ~/my-project"

# Step 4: Start AI with memory
echo ""
echo "Step 4: Start Claude Code with memory"
echo ""
print_cmd "cx"

echo ""
echo "════════════════════════════════════════════════"
echo "  ✓ Done! Claude now remembers everything."
echo "════════════════════════════════════════════════"
