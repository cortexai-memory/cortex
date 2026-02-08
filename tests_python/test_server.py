"""Tests for cortex_memory.server module (MCP tools)."""

from __future__ import annotations

import json
import subprocess
from pathlib import Path

from cortex_memory.server import (
    cortex_context,
    cortex_file_history,
    cortex_search,
    cortex_status,
)


class TestCortexContext:
    def test_returns_markdown(self, tmp_git_repo: Path):
        result = cortex_context(str(tmp_git_repo))
        assert "# Cortex Context" in result
        assert "Git Status" in result

    def test_shows_branch(self, tmp_git_repo: Path):
        result = cortex_context(str(tmp_git_repo))
        assert "Branch:" in result

    def test_non_git_dir(self, tmp_path: Path):
        result = cortex_context(str(tmp_path))
        assert "Not a git repository" in result

    def test_with_cortex_data(self, tmp_git_repo: Path):
        cortex_dir = tmp_git_repo / ".cortex"
        cortex_dir.mkdir()
        commits = [
            {"h": "abc1234", "m": "test commit", "f": "file.py", "i": 10, "d": 2, "b": "main", "p": 1, "t": "2026-02-08T10:00:00Z"},
        ]
        (cortex_dir / "commits.jsonl").write_text(
            "\n".join(json.dumps(c) for c in commits) + "\n"
        )
        sessions = [
            {"type": "start", "sid": "s1", "ts": "2026-02-08T09:00:00Z", "project": "test"},
        ]
        (cortex_dir / "sessions.jsonl").write_text(
            "\n".join(json.dumps(s) for s in sessions) + "\n"
        )
        result = cortex_context(str(tmp_git_repo))
        assert "Sessions" in result
        assert "Total sessions: 1" in result


class TestCortexSearch:
    def test_finds_matching_commits(self, tmp_git_repo: Path):
        cortex_dir = tmp_git_repo / ".cortex"
        cortex_dir.mkdir()
        commits = [
            {"h": "abc1234", "m": "feat: add auth module", "f": "auth.py", "i": 50, "d": 0, "b": "main", "p": 1, "t": "2026-02-08T10:00:00Z"},
            {"h": "def5678", "m": "fix: resolve login bug", "f": "login.py", "i": 5, "d": 2, "b": "main", "p": 1, "t": "2026-02-08T11:00:00Z"},
        ]
        (cortex_dir / "commits.jsonl").write_text(
            "\n".join(json.dumps(c) for c in commits) + "\n"
        )
        result = cortex_search("auth", str(tmp_git_repo))
        assert "auth" in result.lower()
        assert "abc1234" in result

    def test_no_results(self, tmp_git_repo: Path):
        cortex_dir = tmp_git_repo / ".cortex"
        cortex_dir.mkdir()
        (cortex_dir / "commits.jsonl").write_text("")
        result = cortex_search("nonexistent-xyzzy", str(tmp_git_repo))
        assert "No results" in result or "nonexistent" in result

    def test_case_insensitive(self, tmp_git_repo: Path):
        cortex_dir = tmp_git_repo / ".cortex"
        cortex_dir.mkdir()
        commits = [
            {"h": "abc1234", "m": "feat: Add AUTH Module", "f": "auth.py", "i": 50, "d": 0, "b": "main", "p": 1, "t": "2026-02-08T10:00:00Z"},
        ]
        (cortex_dir / "commits.jsonl").write_text(json.dumps(commits[0]) + "\n")
        result = cortex_search("auth module", str(tmp_git_repo))
        assert "abc1234" in result


class TestCortexStatus:
    def test_returns_status(self, tmp_git_repo: Path):
        result = cortex_status(str(tmp_git_repo))
        assert "Cortex Status" in result
        assert "Version:" in result

    def test_shows_git_info(self, tmp_git_repo: Path):
        result = cortex_status(str(tmp_git_repo))
        assert "Branch:" in result

    def test_shows_data_counts(self, tmp_git_repo: Path):
        cortex_dir = tmp_git_repo / ".cortex"
        cortex_dir.mkdir()
        commits = [
            {"h": "abc", "m": "test", "f": "", "i": 0, "d": 0, "b": "main", "p": 1, "t": "2026-02-08T10:00:00Z"},
        ]
        (cortex_dir / "commits.jsonl").write_text(json.dumps(commits[0]) + "\n")
        result = cortex_status(str(tmp_git_repo))
        assert "Commits tracked: 1" in result


class TestCortexFileHistory:
    def test_tracked_file(self, tmp_git_repo: Path):
        result = cortex_file_history("file.txt", str(tmp_git_repo))
        assert "file.txt" in result
        assert "initial commit" in result

    def test_untracked_file(self, tmp_git_repo: Path):
        result = cortex_file_history("nonexistent.py", str(tmp_git_repo))
        assert "No history" in result

    def test_multiple_commits(self, tmp_git_repo: Path):
        for i in range(3):
            (tmp_git_repo / "file.txt").write_text(f"v{i}\n")
            subprocess.run(["git", "add", "."], cwd=tmp_git_repo, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", f"update file v{i}"],
                cwd=tmp_git_repo, capture_output=True,
            )
        result = cortex_file_history("file.txt", str(tmp_git_repo))
        assert "4 commits" in result  # initial + 3 updates
