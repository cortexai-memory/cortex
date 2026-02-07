# Changelog

All notable changes to Cortex will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
