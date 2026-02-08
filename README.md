<div align="center">

# Cortex

**Persistent memory for AI coding assistants**

Every AI coding tool forgets everything between sessions. Cortex fixes that.

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Tests](https://img.shields.io/github/actions/workflow/status/cortexai-memory/cortex/test.yml?label=tests)](https://github.com/cortexai-memory/cortex/actions)
[![macOS](https://img.shields.io/badge/macOS-supported-black)](https://www.apple.com/macos/)
[![Linux](https://img.shields.io/badge/Linux-supported-orange)](https://www.linux.org/)

[Install](#install) · [How It Works](#how-it-works) · [Usage](#usage) · [Config](#configuration) · [FAQ](#faq)

</div>

---

## The Problem

Every AI coding assistant — Claude Code, Cursor, Copilot, Aider — starts each session with **zero memory** of what happened before.

**You waste 10-15 minutes every session:**
- "What was I working on?"
- "Why did I make that architectural decision?"
- "Which files did I change yesterday?"

**This costs you ~5 hours per week.**

<!-- TODO: Add GIF showing developer frustration re-explaining context -->
<!-- ![Before Cortex](docs/gifs/before-cortex.gif) -->

## The Fix

Cortex gives your AI **permanent memory**. One command, zero configuration.

```bash
curl -fsSL https://raw.githubusercontent.com/cortexai-memory/cortex/main/install.sh | bash
cd your-project && cx  # That's it. AI now remembers everything.
```

<!-- TODO: Add GIF showing instant context awareness -->
<!-- ![After Cortex](docs/gifs/after-cortex.gif) -->

**How it works:**
```
git commit → Cortex captures metadata → AI reads context → Zero re-explaining
```

**Two layers:**
- **Layer 0 (bash):** Core memory. No dependencies. Works in 30 seconds.
- **Layer 1 (Python MCP):** AI superpowers. Semantic search. Impact analysis. Knowledge base.

## Quick Start

### I want memory NOW (30 seconds)

```bash
# One command
curl -fsSL https://raw.githubusercontent.com/cortexai-memory/cortex/main/install.sh | bash
source ~/.zshrc  # or ~/.bashrc

# Use it
cd your-project
cx  # Instead of 'claude' - now with memory
```

**Done.** Claude now sees your recent commits, active files, and session history.

**[See detailed quickstart →](QUICKSTART.md)**

### I want AI superpowers (5 minutes)

Semantic search, knowledge base, impact analysis:

```bash
# Automated setup (installs Ollama, models, everything)
cd cortex
./setup-mcp.sh  # Takes 5 minutes, fully automated

# Test it
cx
# You: "Find authentication bugs"
# Claude: [Semantic search finds relevant commits]
# You: "What breaks if I change auth/login.py?"
# Claude: [Shows full dependency tree]
```

**[See examples →](EXAMPLES.md)**

## Why Cortex?

| Without Cortex | With Cortex |
|----------------|-------------|
| 😤 Re-explain project every session (10 min) | 😊 AI knows everything (0 sec) |
| 🔍 `git grep` through 200 commits (10+ min) | ⚡ Natural language search (10 sec) |
| 🤷 "Why did we choose MongoDB?" → Unknown | 💡 Instant recall of all decisions |
| 😱 Change file → hope nothing breaks (30+ min) | 🎯 Full dependency tree (5 sec) |
| **~5 hours wasted per week** | **~5 minutes wasted per week** |

**Time saved: 260 hours/year = 6.5 weeks of productivity**

<!-- TODO: Add comparison GIF side-by-side -->
<!-- ![Before vs After](docs/gifs/comparison.gif) -->

## Install

### Option 1: Fast Install (Recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/cortexai-memory/cortex/main/install.sh | bash
source ~/.zshrc  # or ~/.bashrc
```

### Option 2: Manual Clone

```bash
git clone https://github.com/cortexai-memory/cortex.git
cd cortex && ./install.sh
source ~/.zshrc
```

**Requirements:** git, jq (both pre-installed on macOS)

### MCP Server (Optional - for Claude Code)

**One command, fully automated setup:**

```bash
cd cortex
./setup-mcp.sh  # Installs Ollama, models, Python, everything (5 minutes)
```

**That's it.** The script automatically:
- ✅ Installs Ollama (if not installed)
- ✅ Starts Ollama service
- ✅ Pulls nomic-embed-text model (274 MB)
- ✅ Installs uv + Python dependencies
- ✅ Registers MCP server with Claude Code
- ✅ Tests everything works

**Manual setup** (if you prefer):

```bash
# 1. Install dependencies
brew install ollama  # macOS
cd cortex && uv sync

# 2. Pull model
ollama serve &
ollama pull nomic-embed-text

# 3. Register with Claude Code (auto-created by setup-mcp.sh)
# .mcp.json file will be in cortex directory
```

**MCP Tools Available (9 total):**

**Phase 2 - Context & Search:**
- `cortex_context` - Live session context (equivalent to SESSION_CONTEXT.md)
- `cortex_search` - **Semantic search** over commits (natural language queries!)
- `cortex_diff` - Compare commits with detailed diffs
- `cortex_index` - Index commits for vector search
- `cortex_status` - Memory stats and configuration
- `cortex_file_history` - Git history for specific files

**Phase 3 - Knowledge Base:**
- `cortex_remember` - Store decisions, lessons, patterns, bug fixes
- `cortex_recall` - Search knowledge base with full-text search
- `cortex_decisions` - List all architectural decisions

**Phase 4 - Code Intelligence:**
- `cortex_impact` - **Impact analysis** - "what breaks if I change this file?"
- `cortex_related` - Find related files (imports, co-changes)
- `cortex_patterns` - Detect hotspots, modules, and development cycles

**Example searches:**
- "authentication bugs" → finds auth-related commits by meaning, not keywords
- "recent refactorings" → semantic understanding of refactor commits
- "database schema changes" → finds relevant migrations

**Quick Start (MCP Server):**
```bash
# PHASE 2: Semantic Search
cortex_index()  # Index commits for semantic search
cortex_search(query="authentication bugs")
cortex_search(query="database migrations", file_type="sql")

# PHASE 3: Knowledge Base
cortex_remember(
    category="decision",
    title="Use PostgreSQL",
    content="Chose PostgreSQL for JSONB support and full-text search"
)
cortex_recall(query="database choice")
cortex_decisions()  # List all decisions

# PHASE 4: Code Intelligence
cortex_impact(filepath="src/auth/login.py")  # What breaks if I change this?
cortex_related(filepath="src/auth/login.py")  # Find related files
cortex_patterns()  # Detect hotspots and patterns
```

## Usage

### Starting an AI Session

```bash
cd your-project
cx                  # instead of 'claude'
```

That's it. First run auto-initializes. Every run after that generates fresh context.

### Checking Status

```bash
cortex-status.sh    # View project memory status
```

Shows:
- Recent commits and activity
- Memory usage (tracked commits, sessions, storage)
- Current task (from PROJECT_STATE.md or features.json)
- Health status
- JSON output available with `--json` flag

### File Watching (Optional)

```bash
cortex-watch.sh [--daemon]    # Monitor file changes in real-time
```

Automatically tracks file system events (create, modify, delete) to `.cortex/events.jsonl`. Requires `fswatch` (macOS) or `inotify-tools` (Linux).

### Progress Tracking

Cortex auto-generates `PROGRESS.md` showing:
- ✅ What's been done (last 7 days)
- 🔨 What's in progress (feature branches)
- ⏳ What's next (from PROJECT_STATE.md)
- 📊 Velocity metrics (commits/day, lines added)

### Session Memory (NEW in v1.7.0)

**Work without committing!** Cortex now remembers your session even if you don't commit:

```bash
cx
# Chat for 10 min, make changes
# Close terminal without committing

# Later...
cx
# ✅ Claude sees your previous uncommitted work!
```

**Snapshot Management:**
```bash
cortex-snapshot.sh list         # See all snapshots
cortex-snapshot.sh show latest  # View details
cortex-snapshot.sh clear 7      # Remove snapshots older than 7 days
```

**How it works:**
- On `cx` exit, Cortex auto-saves uncommitted work
- Next session shows: "PREVIOUS SESSION (uncommitted work)"
- You can continue working OR commit
- No more re-explaining what you did!

### Enhanced Workflow (NEW in v1.8.0)

**Quick Commit:**
```bash
cx-commit "feat: add login page"          # Commit + enrich + update context
cx-commit "fix: auth bug" src/auth.js     # Commit specific files
```

**Session Notes:**
```bash
cx-note add "Remember to test edge cases"  # Add note
cx-note list                               # View all notes
cx-note export                             # Export to SESSION_NOTES.md
```

**Snapshot Power Tools:**
```bash
cortex-snapshot.sh diff latest              # View snapshot diff
cortex-snapshot.sh search "authentication"   # Search snapshots
cortex-snapshot.sh branch latest new-feature # Create branch from snapshot
cortex-snapshot.sh undo                     # Remove latest snapshot
```

**Preview Context:**
```bash
cortex-preview.sh  # See what Claude will receive (without launching)
```

### Smart Features (v1.8.0)

- **Auto-restore**: Prompts you to continue from previous session on `cx` start
- **Session summaries**: AI summary of what you accomplished (when CORTEX_ENRICH=1)
- **Context prioritization**: Cortex highlights most-changed files automatically
- **Focus areas**: Shows which file types you're actively working on

## What Your AI Sees

When you run `cx`, Cortex generates `SESSION_CONTEXT.md`:

```markdown
# SESSION_CONTEXT.md (auto-generated by Cortex)
# Session #42 | Project: my-saas-app

## SINCE LAST SESSION
a1b2c3d feat(auth): add Google OAuth provider
e4f5g6h test(auth): add login flow E2E tests

## RECENT COMMITS (24h)
- a1b2c3d feat(auth): add Google OAuth provider [+145/-2]
- e4f5g6h test(auth): add login flow E2E tests [+89/-0]
- f7g8h9i fix(auth): handle OAuth callback redirect [+12/-4]

## CURRENT TASK
Feature F006: Metadata Writer — Status: pending

## GIT STATUS
Branch: feature/auth | Uncommitted: 2 files
Last: f7g8h9i fix(auth): handle OAuth callback redirect (35 minutes ago)

## WARNINGS
None.
```

Your AI assistant reads this automatically. No copy-pasting. No re-explaining.

## How It Works

**Two-layer architecture:**

```
┌──────────────────────────────────────────────────────────────────────┐
│                         HOW CORTEX WORKS                              │
├──────────────────────────────────────────────────────────────────────┤
│                                                                      │
│  LAYER 0 (Bash) — Core Memory                                        │
│  ─────────────────────────────────                                   │
│  1. GIT HOOK (post-commit)                                           │
│     Captures commit metadata to .cortex/commits.jsonl                │
│     Runs in <10ms. Never blocks git.                                 │
│                                                                      │
│  2. CONTEXT GENERATOR (cortex-context.sh)                            │
│     Reads git data → writes SESSION_CONTEXT.md                       │
│     Runs in <100ms. ~500 tokens of context.                          │
│                                                                      │
│  3. SESSION MANAGER (cx command)                                     │
│     Generate context → launch Claude → log session                   │
│     Auto-initializes on first run per project.                       │
│                                                                      │
│  LAYER 1 (Python MCP) — Intelligence [Optional]                      │
│  ───────────────────────────────────────────                         │
│  4. PHASE 2: Semantic Search                                         │
│     • LanceDB vectors (.cortex/vectors/) — 768-dim embeddings        │
│     • Ollama (nomic-embed-text) — local, offline                     │
│     • Tools: cortex_search, cortex_index, cortex_diff                │
│                                                                      │
│  5. PHASE 3: Knowledge Base                                          │
│     • SQLite + FTS5 (.cortex/knowledge.db) — full-text search        │
│     • Stores: decisions, lessons, patterns, bug fixes                │
│     • Tools: cortex_remember, cortex_recall, cortex_decisions        │
│                                                                      │
│  6. PHASE 4: Code Intelligence                                       │
│     • SQLite graph (.cortex/graph.db) — file relationships           │
│     • Tracks: imports, co-changes, dependencies                      │
│     • Tools: cortex_impact, cortex_related, cortex_patterns          │
│                                                                      │
│  7. MCP SERVER                                                       │
│     Exposes 12 tools to Claude Code via Model Context Protocol       │
│                                                                      │
└──────────────────────────────────────────────────────────────────────┘
```

### Storage

All data lives in `.cortex/` (auto-added to `.gitignore`):

```
.cortex/
├── commits.jsonl       # Commit metadata (one JSON line per commit)
├── sessions.jsonl      # Session start/end timestamps
├── summaries/          # Optional LLM-generated summaries
│   └── latest.md
├── vectors/            # Vector embeddings (Phase 2)
│   └── commits.lance   # LanceDB storage for semantic search
├── knowledge.db        # Knowledge base (Phase 3)
│                      # SQLite + FTS5: decisions, lessons, patterns, bug fixes
└── graph.db            # File relationship graph (Phase 4)
                       # SQLite adjacency list: imports, co-changes, dependencies
```

## Configuration

### Layer 0 (Bash)

Edit `~/.cortex/config`:

```ini
# LLM provider for richer summaries (optional)
# Options: none | ollama | openrouter | gemini
llm_provider=none
llm_model=qwen2.5-coder:7b

# Uncomment to use cloud providers
# openrouter_key=sk-or-...
# gemini_key=AI...
```

Enable LLM enrichment for AI-powered commit summaries:

```bash
export CORTEX_ENRICH=1
```

### Layer 1 (Python MCP)

MCP server configuration is in `.mcp.json` (auto-created during setup):

```json
{
  "mcpServers": {
    "cortex-memory": {
      "command": "uv",
      "args": ["run", "--directory", "/path/to/cortex", "cortex-memory"]
    }
  }
}
```

**Python dependencies:** Managed by `uv` (see `pyproject.toml`)
- `mcp[cli]>=1.0.0` - MCP protocol server
- `pydantic>=2.0.0` - Data validation
- `lancedb>=0.6.0` - Vector database (optional, for semantic search)
- `ollama>=0.1.0` - Local embeddings (optional, for semantic search)
- `numpy>=1.24.0` - Vector operations (optional, for semantic search)

## Works With

| Tool | Status | How |
|------|--------|-----|
| Claude Code | Works | Reads SESSION_CONTEXT.md automatically |
| Cursor | Works | Add SESSION_CONTEXT.md to .cursorrules |
| Aider | Works | Reads markdown files from project root |
| Continue.dev | Works | Configure in .continue/ |
| Copilot | Works | Reference in prompts |
| Any AI tool | Works | Any tool that reads project files |

## Benchmarks

| Operation | Time | Impact |
|-----------|------|--------|
| Post-commit hook | <10ms | Never blocks git |
| Context generation | <100ms | Instant on `cx` |
| Memory usage | <5MB | Negligible |
| Context size | ~500 tokens | <1% of context window |

## Health Check

```bash
~/.cortex/bin/cortex-doctor.sh
```

```
Cortex Doctor v0.1.0
────────────────────────
✓ git 2.43.0
✓ jq 1.7.1
✓ ~/.cortex/ exists
✓ Scripts executable
✓ cx alias configured
✓ .cortex/ initialized
✓ Git hook installed (v1)
✓ commits.jsonl valid (42 entries)
✓ sessions.jsonl valid (12 sessions)
○ Ollama: not configured (optional)

Health: GOOD (9/9 required checks passed)
```

## FAQ

**Does it slow down git?**
No. The post-commit hook runs in <10ms and never blocks. It uses `exit 0` to ensure git is never affected.

**Does it need Ollama/LLMs?**
No. Layer 0 (bash) works with just git + jq. Layer 1 (MCP server with semantic search) is optional and requires Ollama for embeddings.

**Do I need the MCP server?**
No. The MCP server (Layer 1) is optional. Layer 0 provides full functionality via SESSION_CONTEXT.md. Layer 1 adds semantic search and Claude Code integration.

**What's the difference between Layer 0 and Layer 1?**
- **Layer 0 (bash):** Captures commits → generates SESSION_CONTEXT.md. No Python, no dependencies, always works.
- **Layer 1 (Python MCP):** Semantic search over commits, natural language queries, Claude Code integration. Optional.

**Does it work in CI/CD?**
Yes. The hook auto-detects CI environments (GitHub Actions, GitLab CI, Jenkins, Buildkite, CircleCI, Travis) and skips itself.

**Does it work with teams?**
Yes. `.cortex/` is local-only (auto-added to .gitignore). Each developer has their own memory. No merge conflicts.

**How much disk space do vector embeddings use?**
Approximately 3KB per commit. 1000 commits ≈ 3MB. LanceDB storage is efficient and local.

**Can I use semantic search without Ollama?**
Not yet. Currently requires local Ollama for embeddings. Cloud embedding providers (OpenAI, Cohere) planned for future releases.

**How do I uninstall?**
```bash
./install.sh --uninstall
# or manually: rm -rf ~/.cortex && remove 'cx' alias from shell rc
```

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## License

[MIT](LICENSE) — free for personal and commercial use.

---

<div align="center">
<i>Never re-explain your project to an AI again.</i>
</div>
