"""Tests for cortex_memory.git_utils module."""

from __future__ import annotations

import subprocess
from pathlib import Path

from cortex_memory.git_utils import (
    get_branch,
    get_file_history,
    get_hot_files,
    get_last_commit_info,
    get_project_root,
    get_recent_commits,
    get_uncommitted_count,
    has_commits,
    is_git_repo,
)


class TestIsGitRepo:
    def test_real_repo(self, tmp_git_repo: Path):
        assert is_git_repo(tmp_git_repo) is True

    def test_not_a_repo(self, tmp_path: Path):
        assert is_git_repo(tmp_path) is False


class TestGetProjectRoot:
    def test_from_repo_root(self, tmp_git_repo: Path):
        root = get_project_root(tmp_git_repo)
        assert root is not None
        assert Path(root).name == tmp_git_repo.name

    def test_from_subdir(self, tmp_git_repo: Path):
        subdir = tmp_git_repo / "sub"
        subdir.mkdir()
        root = get_project_root(subdir)
        assert root is not None
        assert Path(root).name == tmp_git_repo.name

    def test_not_a_repo(self, tmp_path: Path):
        assert get_project_root(tmp_path) is None


class TestGetBranch:
    def test_main_branch(self, tmp_git_repo: Path):
        branch = get_branch(tmp_git_repo)
        assert branch in ("main", "master")

    def test_not_a_repo(self, tmp_path: Path):
        assert get_branch(tmp_path) == "unknown"


class TestHasCommits:
    def test_with_commits(self, tmp_git_repo: Path):
        assert has_commits(tmp_git_repo) is True

    def test_empty_repo(self, tmp_path: Path):
        repo = tmp_path / "empty"
        repo.mkdir()
        subprocess.run(["git", "init"], cwd=repo, capture_output=True, check=True)
        assert has_commits(repo) is False


class TestGetRecentCommits:
    def test_returns_commits(self, tmp_git_repo: Path):
        commits = get_recent_commits(tmp_git_repo, count=5)
        assert len(commits) >= 1
        assert commits[0]["message"] == "initial commit"
        assert len(commits[0]["hash"]) == 8

    def test_empty_repo(self, tmp_path: Path):
        assert get_recent_commits(tmp_path) == []

    def test_with_multiple_commits(self, tmp_git_repo: Path):
        for i in range(3):
            (tmp_git_repo / "file.txt").write_text(f"change {i}\n")
            subprocess.run(["git", "add", "."], cwd=tmp_git_repo, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", f"commit {i}"],
                cwd=tmp_git_repo, capture_output=True,
            )
        commits = get_recent_commits(tmp_git_repo, count=10)
        assert len(commits) == 4  # initial + 3


class TestGetUncommittedCount:
    def test_clean_repo(self, tmp_git_repo: Path):
        assert get_uncommitted_count(tmp_git_repo) == 0

    def test_with_changes(self, tmp_git_repo: Path):
        (tmp_git_repo / "new.txt").write_text("new file\n")
        assert get_uncommitted_count(tmp_git_repo) >= 1

    def test_not_a_repo(self, tmp_path: Path):
        assert get_uncommitted_count(tmp_path) == 0


class TestGetFileHistory:
    def test_tracked_file(self, tmp_git_repo: Path):
        history = get_file_history("file.txt", path=tmp_git_repo)
        assert len(history) == 1
        assert history[0]["message"] == "initial commit"

    def test_untracked_file(self, tmp_git_repo: Path):
        assert get_file_history("nonexistent.txt", path=tmp_git_repo) == []


class TestGetHotFiles:
    def test_with_recent_activity(self, tmp_git_repo: Path):
        for i in range(3):
            (tmp_git_repo / "file.txt").write_text(f"v{i}\n")
            subprocess.run(["git", "add", "."], cwd=tmp_git_repo, capture_output=True)
            subprocess.run(
                ["git", "commit", "-m", f"update {i}"],
                cwd=tmp_git_repo, capture_output=True,
            )
        hot = get_hot_files(tmp_git_repo, days=7)
        assert len(hot) >= 1
        assert hot[0]["file"] == "file.txt"
        assert hot[0]["changes"] >= 3


class TestGetLastCommitInfo:
    def test_with_commits(self, tmp_git_repo: Path):
        info = get_last_commit_info(tmp_git_repo)
        assert info is not None
        assert "initial commit" in info

    def test_not_a_repo(self, tmp_path: Path):
        assert get_last_commit_info(tmp_path) is None
