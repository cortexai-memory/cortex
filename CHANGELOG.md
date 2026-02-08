# Changelog

All notable changes to Cortex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
