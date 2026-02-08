"""Tests for sqlite_store module."""

from cortex_memory.schemas import Decision, Pattern
from cortex_memory.sqlite_store import KnowledgeStore


class TestKnowledgeStore:
    """Test KnowledgeStore class."""

    def test_init(self, tmp_path):
        """Test database initialization."""
        db_path = tmp_path / "knowledge.db"
        store = KnowledgeStore(db_path)

        assert db_path.exists()
        assert store.db_path == db_path

        store.close()

    def test_add_decision(self, tmp_path):
        """Test adding a decision."""
        db_path = tmp_path / "knowledge.db"

        with KnowledgeStore(db_path) as store:
            decision = Decision(
                title="Use React",
                content="Chose React for frontend framework",
            )

            entry_id = store.add(decision)
            assert entry_id is not None

            # Retrieve it
            retrieved = store.get(entry_id)
            assert retrieved is not None
            assert retrieved["title"] == "Use React"
            assert retrieved["category"] == "decision"

    def test_add_pattern(self, tmp_path):
        """Test adding a pattern."""
        db_path = tmp_path / "knowledge.db"

        with KnowledgeStore(db_path) as store:
            pattern = Pattern(
                title="MVC Pattern",
                content="Follow MVC for organization",
            )

            entry_id = store.add(pattern)
            retrieved = store.get(entry_id)

            assert retrieved["title"] == "MVC Pattern"
            assert retrieved["category"] == "pattern"

    def test_search(self, tmp_path):
        """Test full-text search."""
        db_path = tmp_path / "knowledge.db"

        with KnowledgeStore(db_path) as store:
            # Add some entries
            store.add(Decision(title="Use PostgreSQL", content="Database choice"))
            store.add(Decision(title="Use Redis", content="Caching choice"))
            store.add(Pattern(title="Repository", content="Data access pattern"))

            # Search for "database"
            results = store.search("database")
            assert len(results) > 0
            assert any("PostgreSQL" in r["title"] for r in results)

    def test_list_all(self, tmp_path):
        """Test listing all entries."""
        db_path = tmp_path / "knowledge.db"

        with KnowledgeStore(db_path) as store:
            store.add(Decision(title="D1", content="Content1"))
            store.add(Decision(title="D2", content="Content2"))

            results = store.list_all(category="decision")
            assert len(results) == 2

    def test_count(self, tmp_path):
        """Test counting entries."""
        db_path = tmp_path / "knowledge.db"

        with KnowledgeStore(db_path) as store:
            assert store.count() == 0

            store.add(Decision(title="D1", content="Content"))
            assert store.count() == 1
            assert store.count("decision") == 1
            assert store.count("pattern") == 0

    def test_delete(self, tmp_path):
        """Test deleting entries."""
        db_path = tmp_path / "knowledge.db"

        with KnowledgeStore(db_path) as store:
            entry_id = store.add(Decision(title="Test", content="Content"))
            assert store.get(entry_id) is not None

            deleted = store.delete(entry_id)
            assert deleted is True
            assert store.get(entry_id) is None

    def test_get_stats(self, tmp_path):
        """Test getting statistics."""
        db_path = tmp_path / "knowledge.db"

        with KnowledgeStore(db_path) as store:
            store.add(Decision(title="D1", content="Content"))
            store.add(Pattern(title="P1", content="Content"))

            stats = store.get_stats()
            assert stats["total"] == 2
            assert stats["decisions"] == 1
            assert stats["patterns"] == 1
