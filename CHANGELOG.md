# Changelog

All notable changes to Cortex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
