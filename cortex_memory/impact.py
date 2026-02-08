"""Impact analysis for file changes using the relationship graph."""

from __future__ import annotations

import logging
from pathlib import Path
from typing import Optional

from cortex_memory.graph import FileGraph

logger = logging.getLogger(__name__)


class ImpactAnalyzer:
    """Analyze impact of file changes on the codebase.

    Uses the file relationship graph to determine:
    - What files depend on this file (direct impact)
    - What files are transitively affected (indirect impact)
    - Files frequently changed together (co-change impact)
    """

    def __init__(self, graph: FileGraph):
        """Initialize impact analyzer.

        Args:
            graph: File relationship graph
        """
        self.graph = graph

    def analyze_file(
        self,
        filepath: str,
        max_depth: int = 3,
    ) -> dict[str, object]:
        """Analyze impact of changing a file.

        Args:
            filepath: File to analyze
            max_depth: Maximum depth for transitive dependency traversal

        Returns:
            Impact analysis dict with direct and indirect impacts
        """
        # Direct dependents
        direct = self.graph.get_dependents(filepath)

        # Transitive dependents (BFS up to max_depth)
        transitive = self._get_transitive_dependents(filepath, max_depth)

        # Co-changed files
        co_changed = self.graph.get_frequently_changed_together(filepath, limit=10)

        # Calculate impact score
        impact_score = len(direct) * 10 + len(transitive) * 3 + len(co_changed)

        # Categorize impact
        if impact_score > 50:
            impact_level = "high"
        elif impact_score > 20:
            impact_level = "medium"
        else:
            impact_level = "low"

        return {
            "file": filepath,
            "impact_level": impact_level,
            "impact_score": impact_score,
            "direct_dependents": len(direct),
            "transitive_dependents": len(transitive),
            "co_changed_files": len(co_changed),
            "affected_files": {
                "direct": direct,
                "transitive": list(transitive - set(direct)),
                "co_changed": [r["path"] for r in co_changed],
            },
        }

    def _get_transitive_dependents(
        self,
        filepath: str,
        max_depth: int,
    ) -> set[str]:
        """Get all transitive dependents using BFS.

        Args:
            filepath: Starting file
            max_depth: Maximum traversal depth

        Returns:
            Set of all dependent file paths
        """
        visited = set()
        queue = [(filepath, 0)]  # (file, depth)

        while queue:
            current, depth = queue.pop(0)

            if depth >= max_depth:
                continue

            if current in visited:
                continue

            visited.add(current)

            # Get dependents of current file
            dependents = self.graph.get_dependents(current)
            for dep in dependents:
                if dep not in visited:
                    queue.append((dep, depth + 1))

        # Remove the starting file itself
        visited.discard(filepath)
        return visited

    def compare_impact(
        self,
        files: list[str],
        max_depth: int = 3,
    ) -> list[dict[str, object]]:
        """Compare impact of multiple files.

        Args:
            files: List of file paths
            max_depth: Maximum depth for analysis

        Returns:
            List of impact analyses sorted by impact score (highest first)
        """
        results = []

        for filepath in files:
            try:
                analysis = self.analyze_file(filepath, max_depth)
                results.append(analysis)
            except Exception as e:
                logger.warning(f"Failed to analyze {filepath}: {e}")
                continue

        # Sort by impact score
        results.sort(key=lambda x: x["impact_score"], reverse=True)
        return results

    def find_critical_files(
        self,
        min_dependents: int = 5,
        limit: int = 20,
    ) -> list[dict[str, object]]:
        """Find critical files with many dependents.

        Args:
            min_dependents: Minimum number of direct dependents
            limit: Max results to return

        Returns:
            List of critical files with impact info
        """
        # This would require scanning all files in the graph
        # For now, return empty list (implementation could be expensive)
        # In practice, you'd cache this or compute incrementally
        return []

    def get_blast_radius(
        self,
        filepath: str,
        max_depth: int = 3,
    ) -> dict[str, object]:
        """Get the blast radius of changing a file.

        This is similar to analyze_file but focuses on visualization of impact.

        Args:
            filepath: File to analyze
            max_depth: Maximum depth

        Returns:
            Blast radius info with depth-separated layers
        """
        layers: dict[int, list[str]] = {}

        visited = set()
        queue = [(filepath, 0)]

        while queue:
            current, depth = queue.pop(0)

            if depth > max_depth:
                continue

            if current in visited:
                continue

            visited.add(current)

            # Add to appropriate layer
            if depth > 0:  # Skip the source file itself
                if depth not in layers:
                    layers[depth] = []
                layers[depth].append(current)

            # Get dependents
            dependents = self.graph.get_dependents(current)
            for dep in dependents:
                if dep not in visited:
                    queue.append((dep, depth + 1))

        # Count total affected
        total_affected = sum(len(files) for files in layers.values())

        return {
            "file": filepath,
            "max_depth": max_depth,
            "total_affected": total_affected,
            "layers": layers,
        }


def build_graph_from_commits(
    commits: list,
    graph: FileGraph,
) -> None:
    """Build file relationship graph from commit history.

    Args:
        commits: List of CommitRecord objects
        graph: FileGraph to populate
    """
    for commit in commits:
        # Get files from commit
        files = [f.strip() for f in commit.f.split(",") if f.strip()]

        # Add co-change relationships
        if len(files) > 1:
            graph.add_co_changes(files)


def analyze_import_statements(
    filepath: Path,
    graph: FileGraph,
) -> None:
    """Parse file for import statements and add to graph.

    Args:
        filepath: File to analyze
        graph: FileGraph to populate

    Note:
        This is a simplified implementation. Full implementation would use
        AST parsing with tree-sitter or language-specific parsers.
    """
    if not filepath.exists():
        return

    try:
        content = filepath.read_text()
        lines = content.splitlines()

        # Simple regex-based detection (works for Python, JS, etc.)
        import re

        for line in lines:
            # Python: from X import Y, import X
            if match := re.match(r"^(?:from|import)\s+(\S+)", line):
                imported = match.group(1).split(".")[0]
                # Try to resolve to a file path (simplified)
                # In practice, you'd use proper module resolution
                possible_paths = [
                    f"{imported}.py",
                    f"{imported}/__init__.py",
                    f"src/{imported}.py",
                ]

                for path in possible_paths:
                    if Path(path).exists():
                        graph.add_edge(
                            str(filepath),
                            path,
                            "imports",
                        )
                        break

    except Exception as e:
        logger.warning(f"Failed to analyze imports in {filepath}: {e}")
