# Contributing to Cortex

Thank you for your interest in contributing! This guide will help you get started.

## Quick Links

- **Bug Reports:** [GitHub Issues](https://github.com/cortexai-memory/cortex/issues)
- **Feature Requests:** [GitHub Discussions](https://github.com/cortexai-memory/cortex/discussions)

## Ways to Contribute

### 1. Documentation & Visual Demos (High Impact!)

**We need demo GIFs showing:**
- Quick start (30 seconds)
- Semantic search (45 seconds)
- Impact analysis (60 seconds)
- Knowledge base (60 seconds)

**See [demo-scripts/README.md](demo-scripts/README.md) for instructions.**

### 2. Code Contributions

**Development setup:**
```bash
git clone https://github.com/cortexai-memory/cortex.git
cd cortex
uv sync --all-extras
./run-tests.sh
```

**Before contributing:**
1. Open an issue to discuss
2. Fork and create feature branch
3. Write tests
4. Submit PR

### 3. Testing & Bug Reports

**Report bugs with:**
- System info: `cortex-doctor.sh`
- Reproduction steps
- Expected vs actual behavior

## Pull Request Process

1. Fork repository
2. Create branch: `git checkout -b feature/name`
3. Commit with: `feat:`, `fix:`, `docs:`, `test:`
4. Push and open PR

**PR Checklist:**
- [ ] Tests pass
- [ ] Documentation updated
- [ ] Follows style guide

Thank you for contributing! 🎉
