# Cortex Quick Start

Get persistent memory for your AI coding assistant in **30 seconds**.

## Layer 0: Basic Memory (Bash Only)

**One command. Zero dependencies. Works immediately.**

```bash
curl -fsSL https://raw.githubusercontent.com/cortexai-memory/cortex/main/install.sh | bash
source ~/.zshrc  # or ~/.bashrc
cd your-project
cx  # Instead of 'claude'
```

**That's it.** Cortex now remembers everything between sessions.

### What Just Happened?

1. ✅ Installed Cortex to `~/.cortex/`
2. ✅ Added `cx` command (wrapper for `claude`)
3. ✅ Set up git hook to capture commits
4. ✅ Auto-generates `SESSION_CONTEXT.md` with your recent work

### First Session

```bash
cd ~/my-project
cx  # Opens Claude Code with memory
```

Claude now sees:
- Your recent commits (last 24h)
- Files you've been working on
- Current branch and git status
- Session history

### Make Some Changes

```bash
# Work on your project
echo "// New feature" >> src/main.js
git add . && git commit -m "feat: add new feature"

# Start next session
cx
```

Claude sees your new commit automatically. **No re-explaining needed.**

---

## Layer 1: AI Memory (Optional)

**Want semantic search, knowledge base, and impact analysis?**

### Prerequisites

```bash
# 1. Install Ollama (takes 2 minutes)
brew install ollama  # macOS
# OR: curl https://ollama.ai/install.sh | sh  # Linux

# 2. Start Ollama
ollama serve &

# 3. Pull embedding model (274 MB, one-time)
ollama pull nomic-embed-text
```

### Setup MCP Server

```bash
cd ~/cortex
uv sync  # Install Python dependencies (auto-installs uv if needed)

# Register with Claude Code (auto-detects installation)
echo '{
  "mcpServers": {
    "cortex-memory": {
      "command": "uv",
      "args": ["run", "--directory", "'$(pwd)'", "cortex-memory"]
    }
  }
}' > .mcp.json
```

### Test It

Open Claude Code in your project:

```
You: Index my commits for semantic search
Claude: [Calls cortex_index tool]

You: Find all authentication bugs
Claude: [Calls cortex_search with "authentication bugs"]

You: What breaks if I change auth/login.py?
Claude: [Calls cortex_impact on auth/login.py]
```

---

## Verification

### Check Layer 0 Works

```bash
cortex-status.sh
# Should show: commits tracked, sessions, hook installed
```

### Check Layer 1 Works

```bash
cd ~/cortex
uv run cortex-memory  # Should start MCP server
# Press Ctrl+C to stop
```

In Claude Code:
```
You: Show me cortex context
Claude: [Calls cortex_context tool successfully]
```

---

## Common Issues

### "cx: command not found"

```bash
source ~/.zshrc  # or ~/.bashrc
# OR restart terminal
```

### "Ollama not found" (Layer 1)

```bash
brew install ollama
ollama serve &
ollama pull nomic-embed-text
```

### "uv: command not found" (Layer 1)

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
source ~/.zshrc
```

---

## What's Next?

- **[Use Cases](EXAMPLES.md)** - Real-world scenarios
- **[README](README.md)** - Full documentation
- **[FAQ](README.md#faq)** - Troubleshooting

## Quick Reference

| Task | Command |
|------|---------|
| Start AI session | `cx` |
| Check status | `cortex-status.sh` |
| View context | `cat SESSION_CONTEXT.md` |
| Index commits (L1) | Use `cortex_index` in Claude Code |
| Search commits (L1) | Use `cortex_search` in Claude Code |

---

**Time to value:** 30 seconds (Layer 0) or 5 minutes (Layer 1)
