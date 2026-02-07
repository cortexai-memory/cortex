# Contributing to Cortex

Thanks for your interest in contributing to Cortex! Here's how to get started.

## Quick Start

```bash
git clone https://github.com/cortex-memory/cortex.git
cd cortex
./install.sh
```

## Development

### Prerequisites

- bash 4.0+
- git 2.0+
- jq 1.6+
- [bats-core](https://github.com/bats-core/bats-core) (for running tests)
- [shellcheck](https://www.shellcheck.net/) (for linting)

### Running Tests

```bash
bats tests/
```

### Linting

```bash
shellcheck bin/*.sh templates/*.sh install.sh uninstall.sh
```

## Workflow

1. Fork the repo
2. Create a branch: `git checkout -b feature/my-feature`
3. Make your changes
4. Run tests: `bats tests/`
5. Run lint: `shellcheck bin/*.sh`
6. Commit: `git commit -m "feat: description"`
7. Push: `git push origin feature/my-feature`
8. Open a Pull Request

## Commit Messages

We use [Conventional Commits](https://www.conventionalcommits.org/):

```
feat: add new feature
fix: fix a bug
test: add or update tests
docs: update documentation
chore: maintenance tasks
refactor: code refactoring
```

## Code Style

- All scripts use `#!/usr/bin/env bash`
- Use `set -euo pipefail` (or `-uo pipefail` for scripts that must never fail)
- Quote all variables: `"$var"` not `$var`
- Use `[[ ]]` not `[ ]` for conditionals
- ShellCheck must pass with zero warnings
- Functions prefixed with `_cortex_` for internal utilities

## Reporting Bugs

Use the [bug report template](https://github.com/cortex-memory/cortex/issues/new?template=bug_report.md) and include:

- OS and version
- bash version (`bash --version`)
- Steps to reproduce
- Expected vs actual behavior
- Output of `~/.cortex/bin/cortex-doctor.sh`

## License

By contributing, you agree that your contributions will be licensed under MIT.
