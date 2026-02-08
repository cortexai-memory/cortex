# Demo Scripts & Visual Guide

Scripts and instructions for creating demo GIFs/videos for Cortex.

## Recording Tools

**Recommended:**
- **asciinema** - Terminal recordings (https://asciinema.org)
- **VHS** - Generate terminal GIFs from code (https://github.com/charmbracelet/vhs)
- **LICEcap** - Simple GIF screen capture (https://www.cockos.com/licecap/)
- **Kap** - macOS screen recorder (https://getkap.co)

## Quick Setup

```bash
# Install asciinema
brew install asciinema

# Record a session
asciinema rec demo.cast

# Upload to asciinema.org
asciinema upload demo.cast

# Or convert to GIF
agg demo.cast demo.gif
```

## Demo Scripts

### 1. Quick Start (30 seconds)
**File:** `01-quickstart.sh`
**Shows:** Installation to first use
**Target:** New users wanting quick overview

```bash
chmod +x 01-quickstart.sh
asciinema rec quickstart.cast -c "./01-quickstart.sh"
```

### 2. Semantic Search Demo (45 seconds)
**Shows:** Finding commits with natural language
**Key moments:**
1. Regular git grep (shows many irrelevant results)
2. cortex_search with natural language
3. Relevant results highlighted

**Manual recording recommended** - Use Claude Code UI

### 3. Impact Analysis Demo (1 minute)
**Shows:** Understanding what breaks when changing a file
**Key moments:**
1. Developer wants to refactor auth file
2. Runs cortex_impact(filepath="auth/middleware.ts")
3. Shows dependency tree
4. Highlights risk level

**Manual recording recommended** - Use Claude Code UI

### 4. Knowledge Base Demo (1 minute)
**Shows:** Storing and recalling decisions
**Key moments:**
1. Store architectural decision with cortex_remember
2. 6 months later (simulate)
3. New developer asks question
4. cortex_recall finds the answer instantly

**Manual recording recommended** - Use Claude Code UI

## GIF Specifications

### Format
- **Format:** GIF or MP4
- **Frame rate:** 10-15 fps (GIF), 30 fps (MP4)
- **Resolution:** 1280x720 (720p) or 1920x1080 (1080p)
- **Duration:** 30-90 seconds max
- **File size:** < 10 MB for GIF, < 50 MB for MP4

### Style Guide
- **Terminal:** Use clean theme (e.g., Dracula, Nord)
- **Font:** Monospace, size 14-16pt
- **Speed:** Slow enough to read, fast enough to hold attention
- **Annotations:** Add text overlays for key points

## Recommended GIFs to Create

### README.md

**1. Hero GIF** (top of README)
- Shows: Install → First use → AI remembers
- Duration: 30 seconds
- Location: After title, before "The Problem"

**2. Layer 0 Demo**
- Shows: Basic memory working
- Duration: 20 seconds
- Location: "The Fix" section

**3. Semantic Search Demo**
- Shows: Natural language query finding relevant commits
- Duration: 45 seconds
- Location: MCP Server section

### QUICKSTART.md

**4. One-Command Install**
- Shows: Single curl command installing everything
- Duration: 15 seconds
- Location: Top of Layer 0 section

**5. MCP Setup**
- Shows: setup-mcp.sh running automatically
- Duration: 30 seconds
- Location: Layer 1 section

### EXAMPLES.md

**6. Use Case Comparison**
- Side-by-side: Before (git grep) vs After (cortex_search)
- Duration: 45 seconds
- Location: Use Case 3

**7. Impact Analysis**
- Shows: Full dependency tree visualization
- Duration: 30 seconds
- Location: Use Case 7

**8. Knowledge Recall**
- Shows: Storing decision → Recalling later
- Duration: 60 seconds
- Location: Use Case 5

## Screenshot Locations

### README.md

**Screenshot 1: SESSION_CONTEXT.md**
- Shows: Example generated context file
- Format: PNG
- Location: "What Your AI Sees" section

**Screenshot 2: MCP Tools List**
- Shows: All 12 tools in Claude Code
- Format: PNG
- Location: MCP Server section

**Screenshot 3: Semantic Search Results**
- Shows: Search results with relevance scores
- Format: PNG
- Location: After search example

### Architecture Diagrams

**Diagram 1: Two-Layer Architecture**
- Shows: Layer 0 (Bash) + Layer 1 (Python MCP)
- Format: SVG or PNG
- Tool: Excalidraw, draw.io, or ASCII art
- Location: "How It Works" section

**Diagram 2: Data Flow**
- Shows: Git → Hook → JSONL → MCP → Claude Code
- Format: SVG or PNG
- Location: "How It Works" section

## Creating GIFs with VHS

Install VHS:
```bash
go install github.com/charmbracelet/vhs@latest
```

Create a `.tape` file:
```
# quickstart.tape
Output quickstart.gif

Set FontSize 16
Set Width 1200
Set Height 600
Set Theme "Dracula"

Type "curl -fsSL https://raw.githubusercontent.com/cortexai-memory/cortex/main/install.sh | bash"
Enter
Sleep 3s

Type "cd ~/my-project"
Enter
Sleep 1s

Type "cx"
Enter
Sleep 2s

Type "# Claude now has memory! 🎉"
Sleep 3s
```

Generate:
```bash
vhs quickstart.tape
```

## Tips for Great Demos

1. **Keep it fast** - Attention span is < 30 seconds
2. **Show real problems** - Not just features
3. **Before/After** - Show pain point then solution
4. **Highlight wins** - "10 minutes → 10 seconds"
5. **Use real data** - Fake commits look fake
6. **Add captions** - Not everyone plays with sound
7. **Test on mobile** - Many view on phones

## Hosting GIFs

**Options:**
1. **GitHub repo** - Add to `/docs/gifs/`
2. **GitHub Releases** - Attach to release
3. **CDN** - imgur, CloudFlare, etc.
4. **asciinema.org** - Terminal recordings

**Recommended structure:**
```
docs/
├── gifs/
│   ├── quickstart.gif
│   ├── semantic-search.gif
│   ├── impact-analysis.gif
│   └── knowledge-base.gif
└── screenshots/
    ├── session-context.png
    ├── mcp-tools.png
    └── architecture.png
```

## Embedding in Markdown

```markdown
<!-- Relative path (recommended) -->
![Quick Start](docs/gifs/quickstart.gif)

<!-- Or with link -->
[![Quick Start](docs/gifs/quickstart.gif)](https://youtu.be/example)

<!-- Or hosted -->
![Quick Start](https://i.imgur.com/example.gif)
```

## Need Help?

- **asciinema docs:** https://docs.asciinema.org
- **VHS examples:** https://github.com/charmbracelet/vhs/tree/main/examples
- **GIF optimization:** https://ezgif.com/optimize
