#!/usr/bin/env bash
# Cortex MCP Server Setup - One-Command Installation
# Automatically installs Ollama, pulls models, sets up Python, and registers with Claude Code

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() { echo -e "${BLUE}ℹ${NC} $1"; }
log_success() { echo -e "${GREEN}✓${NC} $1"; }
log_warning() { echo -e "${YELLOW}⚠${NC} $1"; }
log_error() { echo -e "${RED}✗${NC} $1"; }

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Get OS
get_os() {
    case "$(uname -s)" in
        Darwin*) echo "macos" ;;
        Linux*)  echo "linux" ;;
        *)       echo "unknown" ;;
    esac
}

OS=$(get_os)

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║        Cortex MCP Server - Automated Setup                ║"
echo "║                                                            ║"
echo "║  This will install:                                        ║"
echo "║  • Ollama (if not installed)                               ║"
echo "║  • nomic-embed-text model (274 MB)                         ║"
echo "║  • uv (Python package manager)                             ║"
echo "║  • Python dependencies                                     ║"
echo "║  • MCP server registration with Claude Code                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# Step 1: Check/Install Ollama
log_info "Step 1/5: Checking Ollama installation..."

if command_exists ollama; then
    log_success "Ollama already installed"
else
    log_warning "Ollama not found. Installing..."

    if [ "$OS" = "macos" ]; then
        if command_exists brew; then
            brew install ollama
        else
            log_error "Homebrew not found. Please install from https://brew.sh"
            exit 1
        fi
    elif [ "$OS" = "linux" ]; then
        curl -fsSL https://ollama.ai/install.sh | sh
    else
        log_error "Unsupported OS. Please install Ollama manually from https://ollama.ai"
        exit 1
    fi

    log_success "Ollama installed"
fi

# Step 2: Start Ollama
log_info "Step 2/5: Starting Ollama service..."

if pgrep -x "ollama" > /dev/null; then
    log_success "Ollama already running"
else
    if [ "$OS" = "macos" ]; then
        # Start Ollama in background
        nohup ollama serve > /dev/null 2>&1 &
        sleep 2
    elif [ "$OS" = "linux" ]; then
        # Check if systemd service exists
        if systemctl list-units --full -all | grep -q "ollama.service"; then
            sudo systemctl start ollama
        else
            nohup ollama serve > /dev/null 2>&1 &
            sleep 2
        fi
    fi

    log_success "Ollama service started"
fi

# Step 3: Pull nomic-embed-text model
log_info "Step 3/5: Pulling nomic-embed-text model (274 MB, may take 1-2 minutes)..."

if ollama list | grep -q "nomic-embed-text"; then
    log_success "Model already downloaded"
else
    ollama pull nomic-embed-text
    log_success "Model downloaded"
fi

# Step 4: Install uv and Python dependencies
log_info "Step 4/5: Installing Python dependencies..."

if ! command_exists uv; then
    log_warning "uv not found. Installing..."
    curl -LsSf https://astral.sh/uv/install.sh | sh

    # Add uv to PATH for current session
    export PATH="$HOME/.local/bin:$PATH"

    log_success "uv installed"
fi

# Install Python dependencies
log_info "Installing Python packages..."
uv sync
log_success "Python dependencies installed"

# Step 5: Register MCP server with Claude Code
log_info "Step 5/5: Registering MCP server with Claude Code..."

CORTEX_DIR="$(pwd)"
MCP_CONFIG=".mcp.json"

cat > "$MCP_CONFIG" <<EOF
{
  "mcpServers": {
    "cortex-memory": {
      "command": "uv",
      "args": [
        "run",
        "--directory",
        "$CORTEX_DIR",
        "cortex-memory"
      ]
    }
  }
}
EOF

log_success "MCP server registered (config: $MCP_CONFIG)"

# Test MCP server
log_info "Testing MCP server..."

if uv run cortex-memory --help >/dev/null 2>&1; then
    log_success "MCP server is working"
else
    log_error "MCP server test failed"
    exit 1
fi

# Final summary
echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                    Setup Complete! 🎉                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
log_success "Cortex MCP Server is ready to use"
echo ""
echo "Next steps:"
echo "  1. Open Claude Code in your project directory"
echo "  2. Try these commands:"
echo ""
echo "     ${GREEN}cortex_context()${NC}          - View session context"
echo "     ${GREEN}cortex_index()${NC}            - Index commits for semantic search"
echo "     ${GREEN}cortex_search(query=\"auth\")${NC} - Search commits"
echo "     ${GREEN}cortex_impact(filepath=\"src/main.ts\")${NC} - Impact analysis"
echo ""
echo "Documentation:"
echo "  • Quick Start: ${BLUE}cat QUICKSTART.md${NC}"
echo "  • Examples:    ${BLUE}cat EXAMPLES.md${NC}"
echo "  • Full Docs:   ${BLUE}cat README.md${NC}"
echo ""
