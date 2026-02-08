"""Tests for graph module."""

from cortex_memory.graph import FileGraph


class TestFileGraph:
    """Test FileGraph class."""

    def test_init(self, tmp_path):
        """Test graph initialization."""
        db_path = tmp_path / "graph.db"
        graph = FileGraph(db_path)

        assert db_path.exists()
        assert graph.db_path == db_path

        graph.close()

    def test_add_file(self, tmp_path):
        """Test adding a file node."""
        db_path = tmp_path / "graph.db"

        with FileGraph(db_path) as graph:
            file_id = graph.add_file("src/main.py", file_type="py")
            assert file_id > 0

            # Adding same file again should return same ID
            file_id2 = graph.add_file("src/main.py")
            assert file_id2 == file_id

    def test_add_edge(self, tmp_path):
        """Test adding edges."""
        db_path = tmp_path / "graph.db"

        with FileGraph(db_path) as graph:
            graph.add_edge("src/main.py", "src/utils.py", "imports")

            # Should create both files and edge
            related = graph.get_related_files("src/main.py")
            assert len(related) > 0
            assert related[0]["path"] == "src/utils.py"
            assert related[0]["relationship"] == "imports"

    def test_get_dependencies(self, tmp_path):
        """Test getting dependencies."""
        db_path = tmp_path / "graph.db"

        with FileGraph(db_path) as graph:
            graph.add_edge("src/main.py", "src/utils.py", "imports")
            graph.add_edge("src/main.py", "src/config.py", "imports")

            deps = graph.get_dependencies("src/main.py")
            assert len(deps) == 2
            assert "src/utils.py" in deps
            assert "src/config.py" in deps

    def test_get_dependents(self, tmp_path):
        """Test getting dependents."""
        db_path = tmp_path / "graph.db"

        with FileGraph(db_path) as graph:
            # main.py imports utils.py
            graph.add_edge("src/main.py", "src/utils.py", "imports")
            # app.py also imports utils.py
            graph.add_edge("src/app.py", "src/utils.py", "imports")

            # utils.py should have 2 dependents
            dependents = graph.get_dependents("src/utils.py")
            assert len(dependents) == 2
            assert "src/main.py" in dependents
            assert "src/app.py" in dependents

    def test_add_co_changes(self, tmp_path):
        """Test adding co-change relationships."""
        db_path = tmp_path / "graph.db"

        with FileGraph(db_path) as graph:
            files = ["src/main.py", "src/utils.py", "src/config.py"]
            graph.add_co_changes(files)

            # main.py should be co-changed with utils.py and config.py
            related = graph.get_frequently_changed_together("src/main.py")
            assert len(related) == 2

    def test_get_stats(self, tmp_path):
        """Test getting graph statistics."""
        db_path = tmp_path / "graph.db"

        with FileGraph(db_path) as graph:
            graph.add_edge("src/main.py", "src/utils.py", "imports")
            graph.add_edge("src/main.py", "src/config.py", "co_changes")

            stats = graph.get_stats()
            assert stats["files"] == 3  # main, utils, config
            assert stats["edges"] == 2
            assert "imports" in stats["relationships"]
            assert "co_changes" in stats["relationships"]
