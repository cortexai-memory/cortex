# Changelog

All notable changes to Cortex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.7.0] - 2026-02-08

### Added
- **Session Memory** - Track context even without commits! 🎉
  - Auto-snapshots on `cx` exit when uncommitted work exists
  - New `cortex-snapshot.sh` command for snapshot management
  - Subcommands: capture, list, show, restore, clear
  - Snapshots include: git diff, file list, timestamp, metadata
  - Latest snapshot automatically shown in SESSION_CONTEXT.md
  - Work-in-progress preserved between sessions
- Enhanced `cortex-session.sh` with exit hook
  - Detects uncommitted work on session end
  - Auto-captures snapshot with helpful reminder
  - Friendly messages guide next steps
- Enhanced `cortex-context.sh` with uncommitted work section
  - Shows previous session's uncommitted work
  - Displays file count and summary
  - Actionable next steps (continue, commit, view details)
- 7 new snapshot tests (67 total tests)

### Changed
- SESSION_CONTEXT.md now includes "PREVIOUS SESSION" section when snapshots exist
- Exit messages more informative about uncommitted work
- Trap signals expanded to INT and TERM for better cleanup

### Benefits
- ✅ No pressure to commit mid-session
- ✅ Context preserved even without commits
- ✅ Easier exploratory coding
- ✅ Automatic work-in-progress tracking
- ✅ Solves "I forgot to commit" problem

## [1.0.0] - 2026-02-08

**🎉 Phase 1 Complete - Intelligence Layer**

This major release completes Phase 1 of the Cortex implementation plan, transforming Cortex from a simple context generator into an intelligent, automated memory system for AI coding assistants.

### Highlights

- **User-Facing Commands**: `cortex-status` for project dashboards
- **Intelligence Layer**: Enhanced LLM prompts (commit/session/decisions), ADR extraction
- **Automation**: File watcher, PROGRESS.md auto-generation, background daemon
- **Developer Experience**: Tab completion for bash/zsh
- **Quality**: 60 comprehensive tests (48 unit + 12 integration), all passing

### All Phase 1 Features (v0.1.0 → v1.6.0)

**v0.1.0** - Foundation
- Post-commit git hook with metadata capture
- SESSION_CONTEXT.md generator
- Session manager (`cx` command)
- Optional LLM enrichment (Ollama, OpenRouter, Gemini)
- Storage compaction
- Health diagnostics (`cortex-doctor`)
- One-command installer
- 33 tests

**v1.1.0** - Status Dashboard
- `cortex-status` command with project metrics
- JSON output mode
- 38 tests

**v1.2.0** - Enhanced Intelligence
- Specialized prompt templates (commit/session/decisions)
- Architectural Decision Records (ADR) extraction
- Structured output directories
- Multi-prompt support
- 38 tests

**v1.3.0** - Automation
- File watcher (`cortex-watch`) with fswatch/inotifywait
- PROGRESS.md auto-generation
- Velocity metrics (commits/day, lines added)
- Event logging
- 44 tests

**v1.4.0** - Background Daemon
- `cortex-daemon` with start/stop/status/restart/logs
- Automated periodic compaction (24h)
- Automated health checks (7d)
- Log rotation (10MB)
- Platform integration (launchd/systemd templates)
- 48 tests

**v1.5.0** - Developer Experience
- Bash completion
- Zsh completion with descriptions
- Auto-installed and sourced
- 48 tests

**v1.6.0** - Test Coverage
- Comprehensive integration test suite
- 60 total tests (48 unit + 12 integration)
- Full pipeline coverage
- Cross-platform compatibility tests

### Breaking Changes

None. All changes are backward compatible with v0.1.0.

### Upgrade Path

From any v0.x or v1.x release:
```bash
cd cortex && git pull && ./install.sh
source ~/.zshrc
```

### What's Next (Phase 2)

- Plugin architecture
- Cursor/Aider/Continue.dev adapters
- VS Code extension
- Cross-project memory
- Web dashboard

---

## [1.6.0] - 2026-02-08

### Added
- **Comprehensive integration test suite** (`tests/integration.bats`)
  - 12 end-to-end workflow tests
  - Full pipeline testing (init → commit → context)
  - Multi-project support verification
  - Enrichment pipeline testing (mocked)
  - Session lifecycle tracking
  - Compaction behavior validation
  - Cross-platform compatibility tests
- **60 total tests** (48 unit tests + 12 integration tests)

### Changed
- All tests passing on macOS
- Test coverage now includes all Phase 1 features

## [1.5.0] - 2026-02-08

### Added
- **Tab completion** for bash and zsh
  - `completions/cortex.bash` — Bash completion with command/flag awareness
  - `completions/cortex.zsh` — Zsh completion with descriptions
  - Completions for: cortex-daemon.sh, cortex-status.sh, cortex-watch.sh, cortex-doctor.sh
  - Auto-installed and sourced by installer

### Changed
- Installer now detects shell type and adds appropriate completion file
- Shell RC files updated with completion sourcing

## [1.4.0] - 2026-02-08

### Added
- **Background daemon** (`cortex-daemon.sh`) for automated maintenance
  - Commands: start, stop, status, restart, logs
  - Automated periodic compaction (default: every 24 hours)
  - Automated health checks (default: every 7 days)
  - Log rotation at 10MB threshold
  - Configurable intervals via `daemon_compact_interval` and `daemon_doctor_interval`
- Platform integration templates
  - macOS: launchd plist for `~/Library/LaunchAgents/`
  - Linux: systemd service for `~/.config/systemd/user/`
- 4 new test cases (48 total tests)

### Changed
- Updated installer with daemon usage instructions
- Config template includes daemon interval settings

## [1.3.0] - 2026-02-08

### Added
- **File watcher** (`cortex-watch.sh`) for real-time file system monitoring
  - Cross-platform support: fswatch (macOS) and inotifywait (Linux)
  - Logs create, modify, delete, and move events to `.cortex/events.jsonl`
  - Smart exclusions for node_modules, .git, build directories, temp files
  - Daemon mode with PID tracking for background operation
  - Graceful cleanup on exit
- **PROGRESS.md auto-generation** showing project velocity
  - What's been done (last 7 days with commit stats)
  - What's in progress (feature branches)
  - What's next (from PROJECT_STATE.md or features.json)
  - Velocity metrics (commits/day, lines added)
  - Controlled via `CORTEX_GENERATE_PROGRESS` environment variable
- 6 new test cases (44 total tests)

### Changed
- Updated README with file watching and progress tracking documentation
- Context generator now includes PROGRESS.md generation by default

## [1.2.0] - 2026-02-08

### Added
- **Enhanced LLM summarization** with specialized prompt templates
  - `summarize-commit.txt` — Structured commit summaries focusing on What/Why/Impact
  - `summarize-session.txt` — End-of-session synthesis across multiple commits
  - `extract-decisions.txt` — Architectural Decision Records (ADRs)
- Structured output directories for different summary types
  - `.cortex/summaries/commits/` — Per-commit summaries
  - `.cortex/summaries/sessions/` — Session-level summaries
  - `.cortex/decisions/` — Extracted architectural decisions
- Multi-prompt support in `cortex-enrich.sh`
- Architectural decisions included in SESSION_CONTEXT.md
- New `enrichment_prompts` config option (commit, session, decisions)

### Changed
- Enhanced prompt quality with examples and detailed guidelines
- Increased timeout for LLM calls from 15s to 30s
- Installer config template updated with enrichment options

## [1.1.0] - 2026-02-08

### Added
- **cortex-status command** — User-facing status dashboard showing project memory state
  - Displays recent commits, memory usage (commits tracked, sessions, storage)
  - Shows current task from PROJECT_STATE.md or features.json
  - Health status and last check time
  - JSON output mode with `--json` flag for programmatic access
- 5 new test cases for status command (38 total tests)

### Changed
- Updated README with status command documentation and examples

## [0.1.1] - 2026-02-07

### Fixed
- Restored GitHub Actions workflow for automated CI testing on macOS and Ubuntu

## [0.1.0] - 2026-02-07

### Added
- Post-commit git hook — captures commit metadata to `.cortex/commits.jsonl`
- Context generator — reads git data, writes `SESSION_CONTEXT.md`
- Session manager — `cx` command: generate context, launch Claude Code, log session
- Optional LLM enrichment — Ollama, OpenRouter, Gemini support
- Storage compaction — prevents unbounded growth of JSONL files
- Health diagnostics — `cortex-doctor.sh` with self-repair capability
- One-command installer — works from clone and curl pipe
- Clean uninstaller
- Comprehensive test suite (30+ bats tests)
- CI pipeline — matrix testing on macOS and Ubuntu
- Cross-platform support — macOS and Linux

### Security
- CI/CD environment auto-detection (hooks skip in CI)
- JSON construction via jq (prevents injection)
- Atomic file writes (prevents corruption)
- Lock file for concurrent access
