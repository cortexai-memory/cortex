"""Pattern detection from graph and commit analysis."""

from __future__ import annotations

import logging
from collections import Counter, defaultdict
from typing import Optional

from cortex_memory.graph import FileGraph
from cortex_memory.jsonl import CommitRecord

logger = logging.getLogger(__name__)


class PatternDetector:
    """Detect architectural and coding patterns from commit history and graph.

    Identifies:
    - Architectural patterns (layered, modular, monolithic)
    - Change patterns (hotspots, isolated modules)
    - Collaboration patterns (ownership, co-authorship)
    - Temporal patterns (feature cycles, refactoring periods)
    """

    def __init__(
        self,
        commits: list[CommitRecord],
        graph: Optional[FileGraph] = None,
    ):
        """Initialize pattern detector.

        Args:
            commits: List of commit records
            graph: Optional file relationship graph
        """
        self.commits = commits
        self.graph = graph

    def detect_hotspots(self, top_n: int = 10) -> list[dict[str, object]]:
        """Detect frequently changed files (hotspots).

        Args:
            top_n: Number of hotspots to return

        Returns:
            List of hotspot files with change counts
        """
        file_changes: Counter = Counter()

        for commit in self.commits:
            files = [f.strip() for f in commit.f.split(",") if f.strip()]
            for filepath in files:
                file_changes[filepath] += 1

        hotspots = []
        for filepath, count in file_changes.most_common(top_n):
            hotspots.append({
                "file": filepath,
                "changes": count,
                "category": self._categorize_hotspot(count, len(self.commits)),
            })

        return hotspots

    def _categorize_hotspot(self, changes: int, total_commits: int) -> str:
        """Categorize hotspot severity.

        Args:
            changes: Number of changes to file
            total_commits: Total commits

        Returns:
            Category: critical, high, medium, low
        """
        ratio = changes / total_commits if total_commits > 0 else 0

        if ratio > 0.2:  # Changed in >20% of commits
            return "critical"
        elif ratio > 0.1:
            return "high"
        elif ratio > 0.05:
            return "medium"
        else:
            return "low"

    def detect_modules(self) -> list[dict[str, object]]:
        """Detect modules based on directory structure and co-change patterns.

        Returns:
            List of detected modules
        """
        if not self.graph:
            return []

        # Group files by directory
        modules: dict[str, list[str]] = defaultdict(list)

        for commit in self.commits:
            files = [f.strip() for f in commit.f.split(",") if f.strip()]
            for filepath in files:
                # Extract module from path (top-level directory)
                parts = filepath.split("/")
                if len(parts) > 1:
                    module = parts[0]
                    modules[module].append(filepath)

        # Calculate module stats
        module_stats = []
        for module, files in modules.items():
            unique_files = set(files)
            module_stats.append({
                "module": module,
                "files": len(unique_files),
                "changes": len(files),
                "activity": len(files) / len(self.commits) if self.commits else 0,
            })

        # Sort by activity
        module_stats.sort(key=lambda x: x["changes"], reverse=True)
        return module_stats

    def detect_isolated_files(self, min_changes: int = 3) -> list[dict[str, object]]:
        """Detect files that change independently (not co-changed with others).

        Args:
            min_changes: Minimum changes to consider

        Returns:
            List of isolated files
        """
        # Count how often each file changes alone vs. with others
        file_solo_changes: Counter = Counter()
        file_total_changes: Counter = Counter()

        for commit in self.commits:
            files = [f.strip() for f in commit.f.split(",") if f.strip()]

            for filepath in files:
                file_total_changes[filepath] += 1

                if len(files) == 1:
                    file_solo_changes[filepath] += 1

        # Find files with high solo ratio
        isolated = []
        for filepath, total in file_total_changes.items():
            if total < min_changes:
                continue

            solo = file_solo_changes[filepath]
            solo_ratio = solo / total

            if solo_ratio > 0.7:  # >70% of changes are solo
                isolated.append({
                    "file": filepath,
                    "total_changes": total,
                    "solo_changes": solo,
                    "solo_ratio": round(solo_ratio, 2),
                })

        isolated.sort(key=lambda x: x["total_changes"], reverse=True)
        return isolated

    def detect_feature_cycles(self) -> list[dict[str, object]]:
        """Detect feature development cycles based on commit patterns.

        Returns:
            List of detected cycles
        """
        # Group commits by time windows (e.g., weekly)
        from datetime import datetime, timedelta

        cycles = []
        current_cycle: list[CommitRecord] = []
        last_date: Optional[datetime] = None

        for commit in sorted(self.commits, key=lambda c: c.t):
            try:
                commit_date = datetime.fromisoformat(commit.t.replace("Z", "+00:00"))
            except Exception:
                continue

            # Start new cycle if more than 3 days gap
            if last_date and (commit_date - last_date) > timedelta(days=3):
                if current_cycle:
                    cycles.append(self._summarize_cycle(current_cycle))
                current_cycle = []

            current_cycle.append(commit)
            last_date = commit_date

        # Add final cycle
        if current_cycle:
            cycles.append(self._summarize_cycle(current_cycle))

        return cycles

    def _summarize_cycle(self, commits: list[CommitRecord]) -> dict[str, object]:
        """Summarize a development cycle.

        Args:
            commits: Commits in the cycle

        Returns:
            Cycle summary
        """
        if not commits:
            return {}

        # Categorize commits
        features = sum(1 for c in commits if "feat" in c.m.lower())
        fixes = sum(1 for c in commits if "fix" in c.m.lower())
        refactors = sum(1 for c in commits if "refactor" in c.m.lower())

        # Get time range
        start = commits[0].t[:10]
        end = commits[-1].t[:10]

        # Get affected files
        all_files = set()
        for commit in commits:
            files = [f.strip() for f in commit.f.split(",") if f.strip()]
            all_files.update(files)

        return {
            "start_date": start,
            "end_date": end,
            "commits": len(commits),
            "features": features,
            "fixes": fixes,
            "refactors": refactors,
            "files_affected": len(all_files),
        }

    def detect_ownership_patterns(self) -> dict[str, object]:
        """Detect file ownership patterns.

        Note: Requires author info in commits (not currently in CommitRecord).
        Returns placeholder for now.

        Returns:
            Ownership statistics
        """
        # Placeholder - would need author field in CommitRecord
        return {
            "note": "Ownership detection requires author field in commit records",
            "suggestion": "Add author field to post-commit hook",
        }

    def detect_all_patterns(self) -> dict[str, object]:
        """Detect all available patterns.

        Returns:
            Dict with all pattern detection results
        """
        return {
            "hotspots": self.detect_hotspots(top_n=10),
            "modules": self.detect_modules()[:10],
            "isolated_files": self.detect_isolated_files()[:10],
            "feature_cycles": self.detect_feature_cycles()[-5:],  # Last 5 cycles
            "ownership": self.detect_ownership_patterns(),
        }


def detect_architectural_style(modules: list[dict[str, object]]) -> str:
    """Detect overall architectural style from modules.

    Args:
        modules: List of module stats

    Returns:
        Architectural style description
    """
    if not modules:
        return "unknown"

    # Analyze module distribution
    total_files = sum(m["files"] for m in modules)
    module_count = len(modules)

    if module_count == 1:
        return "monolithic"
    elif module_count > 10 and total_files > 100:
        return "microservices / modular"
    elif module_count > 5:
        return "layered / modular"
    else:
        return "simple / minimal"


def detect_test_coverage_pattern(commits: list[CommitRecord]) -> dict[str, object]:
    """Detect test coverage patterns from commit history.

    Args:
        commits: List of commits

    Returns:
        Test coverage pattern info
    """
    test_commits = 0
    test_files_total = 0

    for commit in commits:
        files = [f.strip() for f in commit.f.split(",") if f.strip()]
        test_files = [f for f in files if "test" in f.lower() or "spec" in f.lower()]

        if test_files:
            test_commits += 1
            test_files_total += len(test_files)

    test_ratio = test_commits / len(commits) if commits else 0

    if test_ratio > 0.5:
        pattern = "test-driven / high coverage"
    elif test_ratio > 0.25:
        pattern = "moderate testing"
    else:
        pattern = "low test coverage"

    return {
        "pattern": pattern,
        "test_commits": test_commits,
        "test_commit_ratio": round(test_ratio, 2),
        "total_test_files": test_files_total,
    }
