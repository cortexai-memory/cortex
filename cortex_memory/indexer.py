"""Incremental commit indexer for vector search."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

from cortex_memory.embeddings import OllamaEmbeddings
from cortex_memory.jsonl import CommitRecord, get_cortex_dir, read_commits
from cortex_memory.vector_store import VectorStore

logger = logging.getLogger(__name__)


class IndexerError(Exception):
    """Raised when indexing operations fail."""


class CommitIndexer:
    """Incremental indexer for commit history.

    Reads commits from JSONL, generates embeddings, and stores in vector DB.
    Tracks what's already indexed to avoid duplicate work.
    """

    def __init__(
        self,
        project_dir: Path,
        embeddings: Optional[OllamaEmbeddings] = None,
        vector_store: Optional[VectorStore] = None,
    ):
        """Initialize indexer.

        Args:
            project_dir: Project root directory
            embeddings: Embeddings provider (defaults to OllamaEmbeddings)
            vector_store: Vector store (defaults to VectorStore at .cortex/vectors)
        """
        self.project_dir = Path(project_dir)
        self.cortex_dir = get_cortex_dir(self.project_dir)
        self.commits_file = self.cortex_dir / "commits.jsonl"

        self.embeddings = embeddings or OllamaEmbeddings()
        self.vector_store = vector_store or VectorStore(self.cortex_dir)

    def _prepare_commit_text(self, commit: CommitRecord) -> str:
        """Prepare commit for embedding.

        Combines message, files, and branch into searchable text.

        Args:
            commit: Commit record

        Returns:
            Text representation for embedding
        """
        # Format: "message | files: file1, file2 | branch: main"
        parts = [commit.m]

        if commit.f:
            # Limit file list to avoid huge texts
            files = commit.f.split(",")[:10]
            parts.append(f"files: {', '.join(files)}")

        if commit.b:
            parts.append(f"branch: {commit.b}")

        return " | ".join(parts)

    def get_indexing_progress(self) -> dict[str, object]:
        """Get current indexing progress.

        Returns:
            Dict with total commits, indexed commits, pending count
        """
        # Count total commits in JSONL
        all_commits = read_commits(self.commits_file)
        total = len(all_commits)

        # Count indexed commits
        indexed_hashes = self.vector_store.get_indexed_hashes()
        indexed_count = len(indexed_hashes)

        # Calculate pending (commits in JSONL but not in vector store)
        pending = total - indexed_count

        return {
            "total": total,
            "indexed": indexed_count,
            "pending": max(0, pending),
            "progress": round(indexed_count / total * 100, 1) if total > 0 else 0.0,
        }

    def index_new_commits(
        self,
        limit: Optional[int] = None,
        batch_size: int = 10,
    ) -> dict[str, object]:
        """Index commits that haven't been indexed yet.

        Args:
            limit: Max commits to index (None = all pending)
            batch_size: Number of commits to embed/store per batch

        Returns:
            Dict with indexing results: indexed, failed, skipped

        Raises:
            IndexerError: If indexing fails critically
        """
        # Read all commits
        all_commits = read_commits(self.commits_file)
        if not all_commits:
            return {"indexed": 0, "failed": 0, "skipped": 0, "message": "No commits to index"}

        # Get already indexed hashes
        indexed_hashes = self.vector_store.get_indexed_hashes()
        logger.info(f"Found {len(indexed_hashes)} already indexed commits")

        # Filter to only new commits
        new_commits = [c for c in all_commits if c.h not in indexed_hashes]

        if not new_commits:
            return {"indexed": 0, "failed": 0, "skipped": 0, "message": "All commits already indexed"}

        # Apply limit
        if limit:
            new_commits = new_commits[:limit]

        logger.info(f"Indexing {len(new_commits)} new commits (batch_size={batch_size})")

        indexed_count = 0
        failed_count = 0
        skipped_count = 0

        # Process in batches
        for i in range(0, len(new_commits), batch_size):
            batch = new_commits[i:i + batch_size]
            batch_results = []

            # Generate embeddings for batch
            for commit in batch:
                try:
                    text = self._prepare_commit_text(commit)
                    if not text.strip():
                        logger.warning(f"Skipping commit {commit.h[:8]} with empty text")
                        skipped_count += 1
                        continue

                    embedding = self.embeddings.embed_text(text)
                    batch_results.append((commit, embedding))

                except Exception as e:
                    logger.error(f"Failed to embed commit {commit.h[:8]}: {e}")
                    failed_count += 1
                    continue

            # Store batch in vector store
            if batch_results:
                try:
                    added = self.vector_store.add_commits_batch(batch_results)
                    indexed_count += added
                    logger.info(f"Indexed batch {i // batch_size + 1}: {added} commits")

                except Exception as e:
                    logger.error(f"Failed to store batch: {e}")
                    failed_count += len(batch_results)

        result = {
            "indexed": indexed_count,
            "failed": failed_count,
            "skipped": skipped_count,
            "total_processed": len(new_commits),
        }

        if indexed_count > 0:
            result["message"] = f"Successfully indexed {indexed_count} commits"
        elif failed_count > 0:
            result["message"] = f"Indexing failed for {failed_count} commits"
        else:
            result["message"] = "No commits were indexed"

        return result

    def reindex_all(self, batch_size: int = 10) -> dict[str, object]:
        """Clear vector store and reindex all commits.

        Args:
            batch_size: Batch size for embedding generation

        Returns:
            Dict with reindexing results

        Raises:
            IndexerError: If reindexing fails
        """
        logger.warning("Reindexing all commits (clearing existing index)")

        try:
            # Clear existing index
            self.vector_store.clear()

            # Index all commits
            return self.index_new_commits(limit=None, batch_size=batch_size)

        except Exception as e:
            raise IndexerError(f"Reindexing failed: {e}") from e

    def test_indexing_pipeline(self) -> dict[str, object]:
        """Test the full indexing pipeline with a single commit.

        Returns:
            Dict with test results: success, error, timing

        Raises:
            IndexerError: If test fails
        """
        import time

        # Read first commit
        all_commits = read_commits(self.commits_file)
        if not all_commits:
            return {"success": False, "error": "No commits available for testing"}

        commit = all_commits[0]

        try:
            # Test embedding generation
            start = time.time()
            text = self._prepare_commit_text(commit)
            embedding = self.embeddings.embed_text(text)
            embed_time = time.time() - start

            # Test vector store
            start = time.time()
            # Don't actually store (would create duplicate)
            # Just verify embedding format
            if not embedding or len(embedding) < 100:
                return {
                    "success": False,
                    "error": f"Invalid embedding dimension: {len(embedding)}",
                }
            store_time = time.time() - start

            return {
                "success": True,
                "commit": commit.h[:8],
                "text_length": len(text),
                "embedding_dim": len(embedding),
                "embed_time_ms": round(embed_time * 1000, 2),
                "store_time_ms": round(store_time * 1000, 2),
            }

        except Exception as e:
            return {
                "success": False,
                "error": str(e),
                "commit": commit.h[:8],
            }


def auto_index_new_commits(
    project_dir: Path,
    max_commits: int = 50,
) -> dict[str, object]:
    """Auto-index new commits (convenience function for hooks/watchers).

    Args:
        project_dir: Project root
        max_commits: Maximum commits to index per run (prevents long operations)

    Returns:
        Indexing results dict
    """
    try:
        indexer = CommitIndexer(project_dir)

        # Check if embedding service is available
        if not indexer.embeddings.test_connection():
            return {
                "indexed": 0,
                "failed": 0,
                "skipped": 0,
                "message": "Embedding service not available (Ollama not running?)",
            }

        # Index up to max_commits
        return indexer.index_new_commits(limit=max_commits, batch_size=10)

    except Exception as e:
        logger.error(f"Auto-indexing failed: {e}")
        return {
            "indexed": 0,
            "failed": 0,
            "skipped": 0,
            "error": str(e),
        }
