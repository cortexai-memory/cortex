"""SQLite knowledge store with FTS5 full-text search."""

from __future__ import annotations

import logging
import sqlite3
import uuid
from pathlib import Path
from typing import Optional

from cortex_memory.schemas import KnowledgeEntry

logger = logging.getLogger(__name__)


class KnowledgeStoreError(Exception):
    """Raised when knowledge store operations fail."""


class KnowledgeStore:
    """SQLite-backed knowledge base with FTS5 search.

    Stores decisions, patterns, lessons, and bug fixes with full-text search.
    """

    def __init__(self, db_path: Path):
        """Initialize knowledge store.

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
        """Initialize database schema with FTS5 search."""
        conn = self._get_conn()

        # Main knowledge table
        conn.execute("""
            CREATE TABLE IF NOT EXISTS knowledge (
                id TEXT PRIMARY KEY,
                category TEXT NOT NULL,
                title TEXT NOT NULL,
                content TEXT NOT NULL,
                context TEXT,
                consequences TEXT,
                alternatives TEXT,
                root_cause TEXT,
                prevention TEXT,
                situation TEXT,
                action TEXT,
                examples TEXT,
                commit_hash TEXT,
                files TEXT,
                severity TEXT,
                frequency INTEGER,
                tags TEXT,
                created_at TEXT NOT NULL,
                updated_at TEXT
            )
        """)

        # FTS5 virtual table for full-text search
        conn.execute("""
            CREATE VIRTUAL TABLE IF NOT EXISTS knowledge_fts USING fts5(
                id UNINDEXED,
                category,
                title,
                content,
                context,
                tags,
                content='knowledge',
                content_rowid='rowid'
            )
        """)

        # Triggers to keep FTS5 in sync
        conn.execute("""
            CREATE TRIGGER IF NOT EXISTS knowledge_ai AFTER INSERT ON knowledge BEGIN
                INSERT INTO knowledge_fts(rowid, id, category, title, content, context, tags)
                VALUES (new.rowid, new.id, new.category, new.title, new.content, new.context, new.tags);
            END;
        """)

        conn.execute("""
            CREATE TRIGGER IF NOT EXISTS knowledge_ad AFTER DELETE ON knowledge BEGIN
                DELETE FROM knowledge_fts WHERE rowid = old.rowid;
            END;
        """)

        conn.execute("""
            CREATE TRIGGER IF NOT EXISTS knowledge_au AFTER UPDATE ON knowledge BEGIN
                DELETE FROM knowledge_fts WHERE rowid = old.rowid;
                INSERT INTO knowledge_fts(rowid, id, category, title, content, context, tags)
                VALUES (new.rowid, new.id, new.category, new.title, new.content, new.context, new.tags);
            END;
        """)

        conn.commit()
        logger.debug(f"Initialized knowledge database at {self.db_path}")

    def add(self, entry: KnowledgeEntry) -> str:
        """Add knowledge entry to store.

        Args:
            entry: Knowledge entry (Decision, Pattern, BugFix, Lesson, Note)

        Returns:
            Entry ID

        Raises:
            KnowledgeStoreError: If insertion fails
        """
        conn = self._get_conn()
        entry_dict = entry.to_dict()

        # Generate ID if not present
        if not entry_dict.get("id"):
            entry_dict["id"] = str(uuid.uuid4())[:8]

        # Ensure all required fields exist (set to None if not present)
        required_fields = [
            "id", "category", "title", "content", "context", "consequences", "alternatives",
            "root_cause", "prevention", "situation", "action", "examples", "commit_hash",
            "files", "severity", "frequency", "tags", "created_at"
        ]
        for field in required_fields:
            if field not in entry_dict:
                entry_dict[field] = None

        try:
            conn.execute(
                """
                INSERT INTO knowledge (
                    id, category, title, content, context, consequences, alternatives,
                    root_cause, prevention, situation, action, examples, commit_hash,
                    files, severity, frequency, tags, created_at
                ) VALUES (
                    :id, :category, :title, :content, :context, :consequences, :alternatives,
                    :root_cause, :prevention, :situation, :action, :examples, :commit_hash,
                    :files, :severity, :frequency, :tags, :created_at
                )
                """,
                entry_dict,
            )
            conn.commit()
            logger.info(f"Added {entry_dict['category']} entry: {entry_dict['id']}")
            return entry_dict["id"]

        except sqlite3.IntegrityError as e:
            raise KnowledgeStoreError(f"Entry with ID {entry_dict['id']} already exists") from e
        except Exception as e:
            raise KnowledgeStoreError(f"Failed to add entry: {e}") from e

    def get(self, entry_id: str) -> Optional[dict[str, object]]:
        """Get knowledge entry by ID.

        Args:
            entry_id: Entry ID

        Returns:
            Entry dict or None if not found
        """
        conn = self._get_conn()
        cursor = conn.execute("SELECT * FROM knowledge WHERE id = ?", (entry_id,))
        row = cursor.fetchone()

        if row:
            return dict(row)
        return None

    def search(
        self,
        query: str,
        category: Optional[str] = None,
        limit: int = 10,
    ) -> list[dict[str, object]]:
        """Full-text search over knowledge base.

        Args:
            query: Search query (FTS5 syntax supported)
            category: Filter by category (decision, pattern, bug_fix, lesson, note)
            limit: Max results to return

        Returns:
            List of matching entries sorted by relevance
        """
        conn = self._get_conn()

        # Build query
        if category:
            sql = """
                SELECT k.*, rank
                FROM knowledge_fts
                JOIN knowledge k ON knowledge_fts.id = k.id
                WHERE knowledge_fts MATCH ?
                AND k.category = ?
                ORDER BY rank
                LIMIT ?
            """
            params = (query, category, limit)
        else:
            sql = """
                SELECT k.*, rank
                FROM knowledge_fts
                JOIN knowledge k ON knowledge_fts.id = k.id
                WHERE knowledge_fts MATCH ?
                ORDER BY rank
                LIMIT ?
            """
            params = (query, limit)

        try:
            cursor = conn.execute(sql, params)
            return [dict(row) for row in cursor.fetchall()]
        except Exception as e:
            logger.error(f"Search failed: {e}")
            return []

    def list_all(
        self,
        category: Optional[str] = None,
        limit: int = 50,
    ) -> list[dict[str, object]]:
        """List all entries, optionally filtered by category.

        Args:
            category: Filter by category
            limit: Max results

        Returns:
            List of entries sorted by creation date (newest first)
        """
        conn = self._get_conn()

        if category:
            sql = "SELECT * FROM knowledge WHERE category = ? ORDER BY created_at DESC LIMIT ?"
            params = (category, limit)
        else:
            sql = "SELECT * FROM knowledge ORDER BY created_at DESC LIMIT ?"
            params = (limit,)

        cursor = conn.execute(sql, params)
        return [dict(row) for row in cursor.fetchall()]

    def update(self, entry_id: str, updates: dict[str, object]) -> bool:
        """Update knowledge entry.

        Args:
            entry_id: Entry ID
            updates: Fields to update

        Returns:
            True if updated, False if not found

        Raises:
            KnowledgeStoreError: If update fails
        """
        if not updates:
            return False

        conn = self._get_conn()

        # Build SET clause
        set_clause = ", ".join(f"{key} = ?" for key in updates.keys())
        values = list(updates.values())
        values.append(entry_id)

        try:
            cursor = conn.execute(
                f"UPDATE knowledge SET {set_clause} WHERE id = ?",
                values,
            )
            conn.commit()
            return cursor.rowcount > 0
        except Exception as e:
            raise KnowledgeStoreError(f"Failed to update entry: {e}") from e

    def delete(self, entry_id: str) -> bool:
        """Delete knowledge entry.

        Args:
            entry_id: Entry ID

        Returns:
            True if deleted, False if not found
        """
        conn = self._get_conn()
        cursor = conn.execute("DELETE FROM knowledge WHERE id = ?", (entry_id,))
        conn.commit()
        return cursor.rowcount > 0

    def count(self, category: Optional[str] = None) -> int:
        """Count entries.

        Args:
            category: Filter by category

        Returns:
            Number of entries
        """
        conn = self._get_conn()

        if category:
            cursor = conn.execute("SELECT COUNT(*) FROM knowledge WHERE category = ?", (category,))
        else:
            cursor = conn.execute("SELECT COUNT(*) FROM knowledge")

        return cursor.fetchone()[0]

    def get_tags(self) -> list[tuple[str, int]]:
        """Get all tags with usage counts.

        Returns:
            List of (tag, count) tuples sorted by count descending
        """
        conn = self._get_conn()

        # Extract tags and count occurrences
        cursor = conn.execute("SELECT tags FROM knowledge WHERE tags IS NOT NULL")
        tag_counts: dict[str, int] = {}

        for row in cursor.fetchall():
            tags = row["tags"]
            if tags:
                for tag in tags.split(","):
                    tag = tag.strip()
                    if tag:
                        tag_counts[tag] = tag_counts.get(tag, 0) + 1

        return sorted(tag_counts.items(), key=lambda x: x[1], reverse=True)

    def get_stats(self) -> dict[str, object]:
        """Get knowledge base statistics.

        Returns:
            Dict with counts by category and total
        """
        conn = self._get_conn()

        stats = {
            "total": self.count(),
            "decisions": self.count("decision"),
            "patterns": self.count("pattern"),
            "bug_fixes": self.count("bug_fix"),
            "lessons": self.count("lesson"),
            "notes": self.count("note"),
            "tags": len(self.get_tags()),
            "db_size_kb": self.db_path.stat().st_size / 1024 if self.db_path.exists() else 0,
        }

        return stats

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
