"""Tests for vector_store module."""

from pathlib import Path

import pytest

from cortex_memory.jsonl import CommitRecord
from cortex_memory.vector_store import VectorStore


@pytest.fixture
def sample_commit():
    """Create a sample commit record."""
    return CommitRecord(
        h="abc12345",
        m="test commit",
        f="file1.py,file2.py",
        i=10,
        d=5,
        b="main",
        p="xyz789",
        t="2024-01-15T10:00:00Z",
    )


@pytest.fixture
def sample_embedding():
    """Create a sample embedding vector."""
    return [0.1] * 768


class TestVectorStore:
    """Test VectorStore class."""

    def test_init(self, tmp_path):
        """Test initialization."""
        cortex_dir = tmp_path / ".cortex"
        store = VectorStore(cortex_dir)

        assert store.cortex_dir == cortex_dir
        assert store.vectors_dir == cortex_dir / "vectors"
        assert store.vectors_dir.exists()
        assert store.table_name == "commits"
        assert store._db is None
        assert store._table is None

    def test_add_commit_empty_embedding(self, tmp_path, sample_commit):
        """Test error on empty embedding."""
        cortex_dir = tmp_path / ".cortex"
        store = VectorStore(cortex_dir)

        with pytest.raises(ValueError, match="Embedding cannot be empty"):
            store.add_commit(sample_commit, [])

    def test_add_commits_batch_empty(self, tmp_path):
        """Test batch with empty input."""
        cortex_dir = tmp_path / ".cortex"
        store = VectorStore(cortex_dir)
        count = store.add_commits_batch([])

        assert count == 0

    def test_search_similar_empty_query(self, tmp_path):
        """Test search with empty query."""
        cortex_dir = tmp_path / ".cortex"
        store = VectorStore(cortex_dir)

        with pytest.raises(ValueError, match="Query embedding cannot be empty"):
            store.search_similar([])

    def test_get_indexed_hashes_no_table(self, tmp_path):
        """Test getting hashes when no table exists."""
        cortex_dir = tmp_path / ".cortex"
        store = VectorStore(cortex_dir)
        hashes = store.get_indexed_hashes()

        assert hashes == set()

    def test_count_commits_no_table(self, tmp_path):
        """Test counting when no table exists."""
        cortex_dir = tmp_path / ".cortex"
        store = VectorStore(cortex_dir)
        count = store.count_commits()

        assert count == 0

    def test_get_stats_no_table(self, tmp_path):
        """Test stats when no table exists."""
        cortex_dir = tmp_path / ".cortex"
        store = VectorStore(cortex_dir)
        stats = store.get_stats()

        assert stats["indexed"] == 0
        assert stats["dimensions"] is None
        assert stats["available"] is False
