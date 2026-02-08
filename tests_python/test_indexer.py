"""Tests for indexer module."""

from pathlib import Path
from unittest.mock import MagicMock

import pytest

from cortex_memory.indexer import CommitIndexer
from cortex_memory.jsonl import CommitRecord


@pytest.fixture
def sample_commits():
    """Create sample commit records."""
    return [
        CommitRecord(
            h="abc12345",
            m="test commit 1",
            f="file1.py",
            i=10,
            d=5,
            b="main",
            p="xyz1",
            t="2024-01-15T10:00:00Z",
        ),
        CommitRecord(
            h="def67890",
            m="test commit 2",
            f="file2.py",
            i=20,
            d=10,
            b="main",
            p="xyz2",
            t="2024-01-16T10:00:00Z",
        ),
    ]


class TestCommitIndexer:
    """Test CommitIndexer class."""

    def test_init(self, tmp_git_repo):
        """Test initialization."""
        indexer = CommitIndexer(tmp_git_repo)

        assert indexer.project_dir == tmp_git_repo
        assert indexer.cortex_dir == tmp_git_repo / ".cortex"
        assert indexer.commits_file == tmp_git_repo / ".cortex" / "commits.jsonl"
        assert indexer.embeddings is not None
        assert indexer.vector_store is not None

    def test_init_custom_providers(self, tmp_git_repo):
        """Test initialization with custom providers."""
        mock_embeddings = MagicMock()
        mock_vector_store = MagicMock()

        indexer = CommitIndexer(
            tmp_git_repo,
            embeddings=mock_embeddings,
            vector_store=mock_vector_store,
        )

        assert indexer.embeddings == mock_embeddings
        assert indexer.vector_store == mock_vector_store

    def test_prepare_commit_text_basic(self, tmp_git_repo):
        """Test commit text preparation."""
        commit = CommitRecord(
            h="abc123",
            m="fix: bug in parser",
            f="parser.py",
            i=5,
            d=3,
            b="main",
            p="xyz",
            t="2024-01-15T10:00:00Z",
        )

        indexer = CommitIndexer(tmp_git_repo)
        text = indexer._prepare_commit_text(commit)

        assert "fix: bug in parser" in text
        assert "parser.py" in text
        assert "main" in text

    def test_prepare_commit_text_multiple_files(self, tmp_git_repo):
        """Test commit text with multiple files."""
        commit = CommitRecord(
            h="abc123",
            m="refactor",
            f="file1.py,file2.py,file3.py",
            i=10,
            d=5,
            b="feature",
            p="xyz",
            t="2024-01-15T10:00:00Z",
        )

        indexer = CommitIndexer(tmp_git_repo)
        text = indexer._prepare_commit_text(commit)

        assert "file1.py" in text
        assert "file2.py" in text
        assert "feature" in text

    def test_prepare_commit_text_many_files(self, tmp_git_repo):
        """Test commit text limits file list to 10."""
        files = ",".join([f"file{i}.py" for i in range(20)])
        commit = CommitRecord(
            h="abc123",
            m="big refactor",
            f=files,
            i=100,
            d=50,
            b="main",
            p="xyz",
            t="2024-01-15T10:00:00Z",
        )

        indexer = CommitIndexer(tmp_git_repo)
        text = indexer._prepare_commit_text(commit)

        # Should contain first 10 files
        assert "file0.py" in text
        assert "file9.py" in text
