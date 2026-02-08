"""Vector storage using LanceDB for semantic commit search."""

from __future__ import annotations

import logging
from datetime import datetime, timezone
from pathlib import Path
from typing import Optional

import numpy as np

from cortex_memory.jsonl import CommitRecord

logger = logging.getLogger(__name__)


class VectorStoreError(Exception):
    """Raised when vector store operations fail."""


class VectorStore:
    """LanceDB-backed vector store for commit embeddings.

    Stores commit metadata + embeddings in .cortex/vectors/ directory.
    Enables semantic similarity search over commit history.
    """

    def __init__(self, cortex_dir: Path):
        """Initialize vector store.

        Args:
            cortex_dir: Path to .cortex directory (e.g., /path/to/project/.cortex)
        """
        self.cortex_dir = Path(cortex_dir)
        self.vectors_dir = self.cortex_dir / "vectors"
        self.vectors_dir.mkdir(parents=True, exist_ok=True)

        self._db: Optional[object] = None
        self._table: Optional[object] = None
        self.table_name = "commits"

    def _get_db(self):
        """Lazy-load LanceDB connection."""
        if self._db is None:
            try:
                import lancedb
                self._db = lancedb.connect(str(self.vectors_dir))
            except ImportError as e:
                raise VectorStoreError(
                    "lancedb package not installed. Install with: pip install lancedb"
                ) from e
            except Exception as e:
                raise VectorStoreError(f"Failed to connect to LanceDB: {e}") from e
        return self._db

    def _get_table(self):
        """Get or create the commits table."""
        if self._table is not None:
            return self._table

        db = self._get_db()

        # Check if table exists
        try:
            tables = [t.name if hasattr(t, 'name') else str(t) for t in db.list_tables()]
            if self.table_name in tables:
                self._table = db.open_table(self.table_name)
                logger.debug(f"Opened existing table: {self.table_name}")
                return self._table
        except Exception as e:
            logger.warning(f"Error checking tables: {e}")

        # Table doesn't exist, will be created on first add
        return None

    def add_commit(
        self,
        commit: CommitRecord,
        embedding: list[float],
    ) -> None:
        """Add a commit with its embedding to the vector store.

        Args:
            commit: Commit record from JSONL
            embedding: Embedding vector (typically 768 dimensions)

        Raises:
            VectorStoreError: If storage fails
        """
        if not embedding:
            raise ValueError("Embedding cannot be empty")

        db = self._get_db()

        # Prepare data for LanceDB
        data = [{
            "hash": commit.h,
            "message": commit.m,
            "files": commit.f,
            "insertions": commit.i,
            "deletions": commit.d,
            "branch": commit.b,
            "parent": commit.p,
            "timestamp": commit.t,
            "vector": embedding,
        }]

        try:
            if self._table is None:
                # Create table with first record
                self._table = db.create_table(self.table_name, data=data, mode="overwrite")
                logger.info(f"Created vector table: {self.table_name}")
            else:
                # Add to existing table
                self._table.add(data)
                logger.debug(f"Added commit {commit.h[:8]} to vector store")

        except Exception as e:
            raise VectorStoreError(f"Failed to add commit to vector store: {e}") from e

    def add_commits_batch(
        self,
        commits: list[tuple[CommitRecord, list[float]]],
    ) -> int:
        """Add multiple commits with embeddings in batch.

        Args:
            commits: List of (CommitRecord, embedding) tuples

        Returns:
            Number of commits successfully added

        Raises:
            VectorStoreError: If batch operation fails
        """
        if not commits:
            return 0

        db = self._get_db()

        # Prepare batch data
        data = []
        for commit, embedding in commits:
            if not embedding:
                logger.warning(f"Skipping commit {commit.h[:8]} with empty embedding")
                continue

            data.append({
                "hash": commit.h,
                "message": commit.m,
                "files": commit.f,
                "insertions": commit.i,
                "deletions": commit.d,
                "branch": commit.b,
                "parent": commit.p,
                "timestamp": commit.t,
                "vector": embedding,
            })

        if not data:
            return 0

        try:
            if self._table is None:
                # Create table with batch
                self._table = db.create_table(self.table_name, data=data, mode="overwrite")
                logger.info(f"Created vector table with {len(data)} commits")
            else:
                # Add batch to existing table
                self._table.add(data)
                logger.info(f"Added {len(data)} commits to vector store")

            return len(data)

        except Exception as e:
            raise VectorStoreError(f"Failed to add batch to vector store: {e}") from e

    def search_similar(
        self,
        query_embedding: list[float],
        limit: int = 10,
        min_score: float = 0.0,
    ) -> list[dict[str, object]]:
        """Search for commits similar to the query embedding.

        Args:
            query_embedding: Query vector to search for
            limit: Maximum number of results
            min_score: Minimum similarity score (0-1)

        Returns:
            List of dicts with commit metadata and similarity scores

        Raises:
            VectorStoreError: If search fails
        """
        if not query_embedding:
            raise ValueError("Query embedding cannot be empty")

        table = self._get_table()
        if table is None:
            logger.warning("No vector table exists yet")
            return []

        try:
            # LanceDB vector search
            results = (
                table.search(query_embedding)
                .limit(limit)
                .to_list()
            )

            # Filter by minimum score and format results
            formatted = []
            for row in results:
                # LanceDB returns _distance, convert to similarity score (0-1)
                distance = row.get("_distance", 1.0)
                # Cosine distance to similarity: similarity = 1 - distance/2
                # (LanceDB uses L2 distance by default, need to check metric)
                score = max(0.0, 1.0 - distance / 2.0)

                if score < min_score:
                    continue

                formatted.append({
                    "hash": row["hash"],
                    "message": row["message"],
                    "files": row["files"],
                    "insertions": row["insertions"],
                    "deletions": row["deletions"],
                    "branch": row["branch"],
                    "timestamp": row["timestamp"],
                    "score": round(score, 4),
                })

            return formatted

        except Exception as e:
            raise VectorStoreError(f"Vector search failed: {e}") from e

    def get_indexed_hashes(self) -> set[str]:
        """Get set of all commit hashes in the vector store.

        Returns:
            Set of commit hashes (8-char short hashes)
        """
        table = self._get_table()
        if table is None:
            return set()

        try:
            # Query just the hash column
            results = table.to_pandas()["hash"].tolist()
            return set(results)
        except Exception as e:
            logger.warning(f"Failed to get indexed hashes: {e}")
            return set()

    def count_commits(self) -> int:
        """Count total commits in vector store.

        Returns:
            Number of indexed commits
        """
        table = self._get_table()
        if table is None:
            return 0

        try:
            return table.count_rows()
        except Exception as e:
            logger.warning(f"Failed to count rows: {e}")
            return 0

    def get_stats(self) -> dict[str, object]:
        """Get vector store statistics.

        Returns:
            Dict with stats: count, size, dimensions, etc.
        """
        table = self._get_table()

        if table is None:
            return {
                "indexed": 0,
                "size_mb": 0.0,
                "dimensions": None,
                "available": False,
            }

        try:
            count = table.count_rows()

            # Get vector dimensions from first row
            dimensions = None
            if count > 0:
                first_row = table.to_pandas().iloc[0]
                if "vector" in first_row:
                    dimensions = len(first_row["vector"])

            # Calculate directory size
            size_bytes = sum(
                f.stat().st_size
                for f in self.vectors_dir.rglob("*")
                if f.is_file()
            )
            size_mb = size_bytes / (1024 * 1024)

            return {
                "indexed": count,
                "size_mb": round(size_mb, 2),
                "dimensions": dimensions,
                "available": True,
                "path": str(self.vectors_dir),
            }

        except Exception as e:
            logger.warning(f"Failed to get stats: {e}")
            return {
                "indexed": 0,
                "size_mb": 0.0,
                "dimensions": None,
                "available": False,
                "error": str(e),
            }

    def clear(self) -> None:
        """Clear all data from vector store.

        Warning: This deletes all indexed commits!
        """
        try:
            db = self._get_db()
            tables = [t.name if hasattr(t, 'name') else str(t) for t in db.list_tables()]
            if self.table_name in tables:
                db.drop_table(self.table_name)
                self._table = None
                logger.info(f"Cleared vector table: {self.table_name}")
        except Exception as e:
            raise VectorStoreError(f"Failed to clear vector store: {e}") from e
