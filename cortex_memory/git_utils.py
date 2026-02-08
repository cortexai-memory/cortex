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
