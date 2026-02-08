"""File relationship graph using SQLite adjacency list."""

from __future__ import annotations

import logging
import sqlite3
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)


class GraphError(Exception):
    """Raised when graph operations fail."""


class FileGraph:
    """SQLite-backed file relationship graph.

    Tracks relationships between files:
    - imports: File A imports File B
    - co_changes: Files changed together in same commit
    - depends_on: File A depends on File B (manual annotations)
    """

    def __init__(self, db_path: Path):
        """Initialize file graph.

        Args:
            db_path: Path to SQLite database file
        """
        self.db_path = Path(db_path)
        self.db_path.parent.mkdir(parents=True, exist_ok=True)
        self._conn: Optional[sqlite3.Connection] = None
        self._init_db()

    def _get_conn(self) -> sqlite3.Connection:
        """Get or create database connection."""
        if self._conn is None:
            self._conn = sqlite3.connect(str(self.db_path))
            self._conn.row_factory = sqlite3.Row
        return self._conn

    def _init_db(self) -> None:
        """Initialize database schema."""
        conn = self._get_conn()

        # Files table
        conn.execute("""
            CREATE TABLE IF NOT EXISTS files (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                path TEXT UNIQUE NOT NULL,
                type TEXT,
                last_seen TEXT
            )
        """)

        # Edges table (adjacency list)
        conn.execute("""
            CREATE TABLE IF NOT EXISTS edges (
                id INTEGER PRIMARY KEY AUTOINCREMENT,
                from_file_id INTEGER NOT NULL,
                to_file_id INTEGER NOT NULL,
                relationship TEXT NOT NULL,
                weight INTEGER DEFAULT 1,
                metadata TEXT,
                created_at TEXT NOT NULL,
                FOREIGN KEY (from_file_id) REFERENCES files (id),
                FOREIGN KEY (to_file_id) REFERENCES files (id),
                UNIQUE (from_file_id, to_file_id, relationship)
            )
        """)

        # Indexes for fast lookups
        conn.execute("CREATE INDEX IF NOT EXISTS idx_edges_from ON edges (from_file_id)")
        conn.execute("CREATE INDEX IF NOT EXISTS idx_edges_to ON edges (to_file_id)")
        conn.execute(
            "CREATE INDEX IF NOT EXISTS idx_edges_relationship ON edges (relationship)"
        )

        conn.commit()
        logger.debug(f"Initialized file graph at {self.db_path}")

    def add_file(self, filepath: str, file_type: Optional[str] = None) -> int:
        """Add or update file node.

        Args:
            filepath: File path
            file_type: File type/extension

        Returns:
            File ID
        """
        conn = self._get_conn()
        from datetime import datetime, timezone

        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        # Insert or update
        conn.execute(
            """
            INSERT INTO files (path, type, last_seen)
            VALUES (?, ?, ?)
            ON CONFLICT(path) DO UPDATE SET last_seen = ?, type = COALESCE(?, type)
            """,
            (filepath, file_type, now, now, file_type),
        )
        conn.commit()

        # Get ID
        cursor = conn.execute("SELECT id FROM files WHERE path = ?", (filepath,))
        row = cursor.fetchone()
        return row[0] if row else -1

    def add_edge(
        self,
        from_file: str,
        to_file: str,
        relationship: str,
        weight: int = 1,
        metadata: Optional[str] = None,
    ) -> None:
        """Add or update edge between files.

        Args:
            from_file: Source file path
            to_file: Target file path
            relationship: Relationship type (imports, co_changes, depends_on)
            weight: Edge weight (frequency, strength)
            metadata: Optional metadata (JSON string)
        """
        conn = self._get_conn()
        from datetime import datetime, timezone

        # Ensure both files exist
        from_id = self.add_file(from_file)
        to_id = self.add_file(to_file)

        now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

        # Insert or increment weight
        conn.execute(
            """
            INSERT INTO edges (from_file_id, to_file_id, relationship, weight, metadata, created_at)
            VALUES (?, ?, ?, ?, ?, ?)
            ON CONFLICT(from_file_id, to_file_id, relationship)
            DO UPDATE SET weight = weight + ?, metadata = COALESCE(?, metadata)
            """,
            (from_id, to_id, relationship, weight, metadata, now, weight, metadata),
        )
        conn.commit()

    def get_related_files(
        self,
        filepath: str,
        relationship: Optional[str] = None,
        limit: int = 20,
    ) -> list[dict[str, object]]:
        """Get files related to the given file.

        Args:
            filepath: File path
            relationship: Filter by relationship type
            limit: Max results

        Returns:
            List of related files with relationship info
        """
        conn = self._get_conn()

        # Get file ID
        cursor = conn.execute("SELECT id FROM files WHERE path = ?", (filepath,))
        row = cursor.fetchone()
        if not row:
            return []

        file_id = row[0]

        # Query related files (both directions)
        if relationship:
            sql = """
                SELECT f.path, e.relationship, e.weight, e.metadata
                FROM edges e
                JOIN files f ON (
                    (e.from_file_id = ? AND f.id = e.to_file_id) OR
                    (e.to_file_id = ? AND f.id = e.from_file_id)
                )
                WHERE e.relationship = ?
                ORDER BY e.weight DESC
                LIMIT ?
            """
            params = (file_id, file_id, relationship, limit)
        else:
            sql = """
                SELECT f.path, e.relationship, e.weight, e.metadata
                FROM edges e
                JOIN files f ON (
                    (e.from_file_id = ? AND f.id = e.to_file_id) OR
                    (e.to_file_id = ? AND f.id = e.from_file_id)
                )
                ORDER BY e.weight DESC
                LIMIT ?
            """
            params = (file_id, file_id, limit)

        cursor = conn.execute(sql, params)
        return [dict(row) for row in cursor.fetchall()]

    def get_dependencies(self, filepath: str) -> list[str]:
        """Get files that this file depends on.

        Args:
            filepath: File path

        Returns:
            List of file paths this file depends on
        """
        related = self.get_related_files(filepath, relationship="imports")
        return [r["path"] for r in related]

    def get_dependents(self, filepath: str) -> list[str]:
        """Get files that depend on this file.

        Args:
            filepath: File path

        Returns:
            List of file paths that depend on this file
        """
        conn = self._get_conn()

        cursor = conn.execute("SELECT id FROM files WHERE path = ?", (filepath,))
        row = cursor.fetchone()
        if not row:
            return []

        file_id = row[0]

        # Files that import this file
        cursor = conn.execute(
            """
            SELECT f.path
            FROM edges e
            JOIN files f ON f.id = e.from_file_id
            WHERE e.to_file_id = ? AND e.relationship = 'imports'
            ORDER BY e.weight DESC
            """,
            (file_id,),
        )

        return [row[0] for row in cursor.fetchall()]

    def get_frequently_changed_together(
        self,
        filepath: str,
        limit: int = 10,
    ) -> list[dict[str, object]]:
        """Get files frequently changed together with this file.

        Args:
            filepath: File path
            limit: Max results

        Returns:
            List of files with co-change counts
        """
        return self.get_related_files(filepath, relationship="co_changes", limit=limit)

    def add_co_changes(self, files: list[str]) -> None:
        """Add co-change relationships for files changed together.

        Args:
            files: List of file paths changed in same commit
        """
        # Create edges between all pairs
        for i, file_a in enumerate(files):
            for file_b in files[i + 1 :]:
                self.add_edge(file_a, file_b, "co_changes", weight=1)

    def get_stats(self) -> dict[str, object]:
        """Get graph statistics.

        Returns:
            Dict with node and edge counts
        """
        conn = self._get_conn()

        cursor = conn.execute("SELECT COUNT(*) FROM files")
        file_count = cursor.fetchone()[0]

        cursor = conn.execute("SELECT COUNT(*) FROM edges")
        edge_count = cursor.fetchone()[0]

        cursor = conn.execute(
            "SELECT relationship, COUNT(*) FROM edges GROUP BY relationship"
        )
        relationships = {row[0]: row[1] for row in cursor.fetchall()}

        return {
            "files": file_count,
            "edges": edge_count,
            "relationships": relationships,
            "db_size_kb": self.db_path.stat().st_size / 1024 if self.db_path.exists() else 0,
        }

    def close(self) -> None:
        """Close database connection."""
        if self._conn:
            self._conn.close()
            self._conn = None

    def __enter__(self):
        """Context manager entry."""
        return self

    def __exit__(self, exc_type, exc_val, exc_tb):
        """Context manager exit."""
        self.close()
