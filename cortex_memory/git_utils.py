"""Git utilities — subprocess wrappers with safe defaults."""

from __future__ import annotations

import logging
import subprocess
from pathlib import Path
from typing import Optional

logger = logging.getLogger(__name__)

_TIMEOUT = 10  # seconds


def _run(
    args: list[str],
    cwd: str | Path | None = None,
    timeout: int = _TIMEOUT,
) -> Optional[str]:
    """Run a git command, return stdout or None on error."""
    try:
        result = subprocess.run(
            args,
            cwd=cwd,
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode != 0:
            return None
        return result.stdout.strip()
    except (subprocess.TimeoutExpired, FileNotFoundError, OSError) as exc:
        logger.debug("git command failed: %s — %s", args, exc)
        return None


def get_project_root(path: str | Path | None = None) -> Optional[str]:
    """Find the git repository root, or None if not a git repo."""
    args = ["git", "rev-parse", "--show-toplevel"]
    return _run(args, cwd=path or ".")


def is_git_repo(path: str | Path | None = None) -> bool:
    """Check if path is inside a git work tree."""
    return _run(
        ["git", "rev-parse", "--is-inside-work-tree"],
        cwd=path or ".",
    ) == "true"


def get_branch(path: str | Path | None = None) -> str:
    """Return current branch name, or 'DETACHED' / 'unknown'."""
    cwd = path or "."
    branch = _run(["git", "branch", "--show-current"], cwd=cwd)
    if branch:
        return branch
    # Detached HEAD
    short = _run(["git", "rev-parse", "--short", "HEAD"], cwd=cwd)
    return f"DETACHED@{short}" if short else "unknown"


def has_commits(path: str | Path | None = None) -> bool:
    """Check if the repo has at least one commit."""
    return _run(["git", "rev-parse", "HEAD"], cwd=path or ".") is not None


def get_recent_commits(
    path: str | Path | None = None,
    count: int = 10,
    since: Optional[str] = None,
) -> list[dict[str, str]]:
    """Return recent commits as dicts with 'hash', 'message', 'date'.

    Args:
        path: Repo path
        count: Max commits to return
        since: ISO timestamp cutoff (git --since)
    """
    cwd = path or "."
    args = ["git", "log", f"-{count}", "--format=%H|%s|%aI"]
    if since:
        args.append(f"--since={since}")

    output = _run(args, cwd=cwd)
    if not output:
        return []

    commits = []
    for line in output.splitlines():
        parts = line.split("|", 2)
        if len(parts) == 3:
            commits.append({
                "hash": parts[0][:8],
                "message": parts[1],
                "date": parts[2],
            })
    return commits


def get_uncommitted_count(path: str | Path | None = None) -> int:
    """Count uncommitted files (staged + unstaged + untracked)."""
    output = _run(["git", "status", "--porcelain"], cwd=path or ".")
    if not output:
        return 0
    return len(output.splitlines())


def get_file_history(
    filepath: str,
    path: str | Path | None = None,
    count: int = 20,
) -> list[dict[str, str]]:
    """Return git log for a specific file."""
    cwd = path or "."
    output = _run(
        ["git", "log", f"-{count}", "--format=%H|%s|%aI", "--", filepath],
        cwd=cwd,
    )
    if not output:
        return []

    history = []
    for line in output.splitlines():
        parts = line.split("|", 2)
        if len(parts) == 3:
            history.append({
                "hash": parts[0][:8],
                "message": parts[1],
                "date": parts[2],
            })
    return history


def get_hot_files(
    path: str | Path | None = None,
    days: int = 7,
    limit: int = 10,
) -> list[dict[str, object]]:
    """Return most frequently changed files in the last N days."""
    cwd = path or "."
    output = _run(
        ["git", "log", f"--since={days} days ago", "--name-only", "--format="],
        cwd=cwd,
    )
    if not output:
        return []

    counts: dict[str, int] = {}
    for line in output.splitlines():
        line = line.strip()
        if line:
            counts[line] = counts.get(line, 0) + 1

    sorted_files = sorted(counts.items(), key=lambda x: x[1], reverse=True)
    return [
        {"file": f, "changes": c}
        for f, c in sorted_files[:limit]
    ]


def get_last_commit_info(path: str | Path | None = None) -> Optional[str]:
    """Return last commit as 'hash message (time ago)'."""
    return _run(
        ["git", "log", "-1", "--format=%h %s (%ar)"],
        cwd=path or ".",
    )


def get_diff_between_commits(
    commit1: str,
    commit2: str,
    path: str | Path | None = None,
    stat_only: bool = False,
) -> Optional[str]:
    """Get diff between two commits.

    Args:
        commit1: First commit (older)
        commit2: Second commit (newer), or "HEAD"
        path: Repository path
        stat_only: If True, return only --stat summary

    Returns:
        Diff output or None on error
    """
    cwd = path or "."
    args = ["git", "diff"]
    if stat_only:
        args.append("--stat")
    args.extend([commit1, commit2])

    return _run(args, cwd=cwd, timeout=30)


def get_recent_file_changes(
    path: str | Path | None = None,
    count: int = 10,
    with_stats: bool = True,
) -> list[dict[str, object]]:
    """Get files changed in recent commits with statistics.

    Args:
        path: Repository path
        count: Number of commits to analyze
        with_stats: Include line change stats

    Returns:
        List of dicts with file, changes, insertions, deletions
    """
    cwd = path or "."

    # Get files changed in last N commits with stats
    args = ["git", "log", f"-{count}", "--name-only", "--format=%H"]
    if with_stats:
        args = ["git", "log", f"-{count}", "--numstat", "--format=%H"]

    output = _run(args, cwd=cwd)
    if not output:
        return []

    file_stats: dict[str, dict[str, int]] = {}

    for line in output.splitlines():
        line = line.strip()
        if not line or len(line) == 40:  # Skip commit hashes
            continue

        if with_stats and "\t" in line:
            # Parse numstat: "insertions\tdeletions\tfilename"
            parts = line.split("\t")
            if len(parts) == 3:
                ins, dels, filename = parts
                if filename not in file_stats:
                    file_stats[filename] = {"changes": 0, "insertions": 0, "deletions": 0}
                file_stats[filename]["changes"] += 1
                try:
                    file_stats[filename]["insertions"] += int(ins) if ins != "-" else 0
                    file_stats[filename]["deletions"] += int(dels) if dels != "-" else 0
                except ValueError:
                    pass
        else:
            # Just count changes
            if line not in file_stats:
                file_stats[line] = {"changes": 1, "insertions": 0, "deletions": 0}
            else:
                file_stats[line]["changes"] += 1

    # Sort by change frequency
    sorted_files = sorted(
        file_stats.items(),
        key=lambda x: x[1]["changes"],
        reverse=True,
    )

    return [
        {"file": f, **stats}
        for f, stats in sorted_files
    ]


def get_coding_patterns(
    path: str | Path | None = None,
    days: int = 30,
) -> dict[str, object]:
    """Analyze coding patterns from recent commits.

    Args:
        path: Repository path
        days: Number of days to analyze

    Returns:
        Dict with patterns: file_types, common_words, active_hours
    """
    cwd = path or "."

    # Get files changed in time period
    output = _run(
        ["git", "log", f"--since={days} days ago", "--name-only", "--format="],
        cwd=cwd,
    )
    if not output:
        return {"file_types": {}, "common_words": {}, "active_hours": []}

    # Analyze file types
    file_types: dict[str, int] = {}
    for line in output.splitlines():
        line = line.strip()
        if line and "." in line:
            ext = line.rsplit(".", 1)[-1]
            file_types[ext] = file_types.get(ext, 0) + 1

    # Get commit messages for word frequency
    msg_output = _run(
        ["git", "log", f"--since={days} days ago", "--format=%s"],
        cwd=cwd,
    )
    common_words: dict[str, int] = {}
    if msg_output:
        for line in msg_output.splitlines():
            # Extract meaningful words (skip common prefixes)
            words = line.lower().split()
            for word in words:
                if len(word) > 3 and word not in {"feat", "fix", "docs", "test", "chore"}:
                    common_words[word] = common_words.get(word, 0) + 1

    # Get commit time patterns
    time_output = _run(
        ["git", "log", f"--since={days} days ago", "--format=%aI"],
        cwd=cwd,
    )
    active_hours: list[int] = []
    if time_output:
        for line in time_output.splitlines():
            try:
                # Extract hour from ISO timestamp
                hour = int(line[11:13])
                active_hours.append(hour)
            except (ValueError, IndexError):
                pass

    return {
        "file_types": dict(sorted(file_types.items(), key=lambda x: x[1], reverse=True)[:10]),
        "common_words": dict(sorted(common_words.items(), key=lambda x: x[1], reverse=True)[:10]),
        "active_hours": active_hours,
    }


def parse_commit_diff(diff_output: str) -> dict[str, object]:
    """Parse git diff output into structured format.

    Args:
        diff_output: Output from git diff command

    Returns:
        Dict with files, insertions, deletions, summary
    """
    if not diff_output:
        return {"files": [], "insertions": 0, "deletions": 0, "summary": ""}

    files_changed = []
    total_insertions = 0
    total_deletions = 0

    current_file = None
    for line in diff_output.splitlines():
        if line.startswith("diff --git"):
            # Extract filename: diff --git a/file b/file
            parts = line.split()
            if len(parts) >= 4:
                current_file = parts[3][2:]  # Remove b/ prefix
                files_changed.append(current_file)
        elif line.startswith("+") and not line.startswith("+++"):
            total_insertions += 1
        elif line.startswith("-") and not line.startswith("---"):
            total_deletions += 1

    summary = f"{len(files_changed)} files: +{total_insertions} -{total_deletions}"

    return {
        "files": files_changed,
        "insertions": total_insertions,
        "deletions": total_deletions,
        "summary": summary,
    }
