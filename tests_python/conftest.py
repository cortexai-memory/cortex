"""Shared fixtures for cortex_memory tests."""

from __future__ import annotations

import json
import os
import subprocess
from pathlib import Path

import pytest


@pytest.fixture
def tmp_git_repo(tmp_path: Path) -> Path:
    """Create a temporary git repository with an initial commit."""
    repo = tmp_path / "repo"
    repo.mkdir()
    subprocess.run(["git", "init"], cwd=repo, capture_output=True, check=True)
    subprocess.run(
        ["git", "config", "user.email", "test@cortex.dev"],
        cwd=repo, capture_output=True, check=True,
    )
    subprocess.run(
        ["git", "config", "user.name", "Cortex Test"],
        cwd=repo, capture_output=True, check=True,
    )
    (repo / "file.txt").write_text("hello\n")
    subprocess.run(["git", "add", "."], cwd=repo, capture_output=True, check=True)
    subprocess.run(
        ["git", "commit", "-m", "initial commit"],
        cwd=repo, capture_output=True, check=True,
    )
    return repo


@pytest.fixture
def tmp_cortex_dir(tmp_path: Path) -> Path:
    """Create a temporary .cortex directory with sample JSONL files."""
    cortex_dir = tmp_path / ".cortex"
    cortex_dir.mkdir()

    # Sample commits
    commits = [
        {"h": "abc1234", "m": "feat: add auth module", "f": "src/auth.py", "i": 50, "d": 0, "b": "main", "p": 1, "t": "2026-02-08T10:00:00Z"},
        {"h": "def5678", "m": "fix: resolve login bug", "f": "src/auth.py,tests/test_auth.py", "i": 10, "d": 3, "b": "main", "p": 1, "t": "2026-02-08T11:00:00Z"},
        {"h": "ghi9012", "m": "refactor: clean up utils", "f": "src/utils.py", "i": 20, "d": 15, "b": "feature/cleanup", "p": "myproject", "t": "2026-02-08T12:00:00Z"},
    ]
    commits_file = cortex_dir / "commits.jsonl"
    commits_file.write_text("\n".join(json.dumps(c) for c in commits) + "\n")

    # Sample sessions
    sessions = [
        {"type": "start", "sid": "sess-001", "ts": "2026-02-08T09:00:00Z", "project": "myproject"},
        {"type": "end", "sid": "sess-001", "ts": "2026-02-08T10:30:00Z", "project": "myproject"},
        {"type": "start", "sid": "sess-002", "ts": "2026-02-08T11:00:00Z", "project": "myproject"},
    ]
    sessions_file = cortex_dir / "sessions.jsonl"
    sessions_file.write_text("\n".join(json.dumps(s) for s in sessions) + "\n")

    return cortex_dir


@pytest.fixture
def tmp_cortex_home(tmp_path: Path) -> Path:
    """Create a temporary CORTEX_HOME with config file."""
    home = tmp_path / "cortex_home"
    home.mkdir()
    config = home / "config"
    config.write_text(
        "llm_provider=none\n"
        "llm_model=qwen2.5-coder:7b\n"
        "retention_days=30\n"
    )
    return home
