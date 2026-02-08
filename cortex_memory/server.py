"""Cortex Memory MCP Server — exposes coding memory to Claude Code."""

from __future__ import annotations

import json
from datetime import datetime, timezone
from pathlib import Path

from mcp.server.fastmcp import FastMCP

from cortex_memory import __version__
from cortex_memory.config import load_config
from cortex_memory.git_utils import (
    get_branch,
    get_file_history,
    get_hot_files,
    get_last_commit_info,
    get_project_root,
    get_recent_commits,
    get_uncommitted_count,
    has_commits,
    is_git_repo,
)
from cortex_memory.jsonl import (
    CommitRecord,
    count_sessions,
    get_cortex_dir,
    get_last_session_end,
    read_commits,
    read_sessions,
)

mcp = FastMCP(
    "cortex-memory",
    instructions="Persistent coding memory — context, search, and file history",
)


def _resolve_project(project_dir: str | None) -> Path:
    """Resolve project directory: use arg, git root, or cwd."""
    if project_dir:
        p = Path(project_dir).expanduser().resolve()
        if p.is_dir():
            return p
    root = get_project_root()
    if root:
        return Path(root)
    return Path.cwd()


@mcp.tool()
def cortex_context(project_dir: str | None = None) -> str:
    """Generate live session context for the current project.

    Returns a markdown summary equivalent to SESSION_CONTEXT.md with:
    - Git status (branch, uncommitted files, last commit)
    - Recent commits (last 24h from JSONL or git log)
    - Session history
    - Hot files (most changed in last 7 days)
    - Warnings (uncommitted files, stale branch, conflicts)
    """
    project = _resolve_project(project_dir)
    cortex_dir = get_cortex_dir(project)
    now = datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")

    lines = [
        f"# Cortex Context",
        f"**Generated:** {now} | **Project:** {project.name}",
        "",
    ]

    # --- Git status ---
    if is_git_repo(project):
        branch = get_branch(project)
        uncommitted = get_uncommitted_count(project)
        last = get_last_commit_info(project) or "no commits"
        lines += [
            "## Git Status",
            f"Branch: {branch} | Uncommitted: {uncommitted} files",
            f"Last: {last}",
            "",
        ]
    else:
        lines += ["## Git Status", "Not a git repository.", ""]

    # --- Session info ---
    sessions_file = cortex_dir / "sessions.jsonl"
    sessions = read_sessions(sessions_file)
    session_count = count_sessions(sessions)
    last_end = get_last_session_end(sessions)
    lines += [
        "## Sessions",
        f"Total sessions: {session_count}",
    ]
    if last_end:
        lines.append(f"Last session ended: {last_end}")
    lines.append("")

    # --- Recent commits (24h) ---
    commits_file = cortex_dir / "commits.jsonl"
    from cortex_memory.jsonl import read_commits as _read_commits

    # Try JSONL first, fall back to git log
    cutoff_24h = _iso_hours_ago(24)
    commits = _read_commits(commits_file, since=cutoff_24h)

    if commits:
        lines.append("## Recent Commits (24h)")
        for c in commits[-15:]:
            lines.append(f"- {c.h[:8]} {c.m} [+{c.i}/-{c.d}] {c.f}")
        lines.append("")
    else:
        # Fallback to git log
        git_commits = get_recent_commits(project, count=10, since="24 hours ago")
        if git_commits:
            lines.append("## Recent Commits (24h)")
            for c in git_commits:
                lines.append(f"- {c['hash']} {c['message']}")
            lines.append("")
        else:
            lines += ["## Recent Commits (24h)", "No commits in last 24 hours.", ""]

    # --- Hot files ---
    hot = get_hot_files(project)
    if hot:
        lines.append("## Focus Areas (most active files, last 7 days)")
        for item in hot[:5]:
            lines.append(f"- {item['file']} ({item['changes']} changes)")
        lines.append("")

    # --- Warnings ---
    warnings = []
    if is_git_repo(project):
        uc = get_uncommitted_count(project)
        if uc > 5:
            warnings.append(f"{uc} uncommitted files — consider committing or stashing")
    if warnings:
        lines.append("## Warnings")
        for w in warnings:
            lines.append(f"- {w}")
        lines.append("")

    return "\n".join(lines)


@mcp.tool()
def cortex_search(query: str, project_dir: str | None = None) -> str:
    """Search commit history for a query string.

    Performs case-insensitive text search across commit messages and file names
    in the JSONL commit log. Returns matching commits.

    In Phase 2, this will be upgraded to vector similarity search.
    """
    project = _resolve_project(project_dir)
    cortex_dir = get_cortex_dir(project)
    commits_file = cortex_dir / "commits.jsonl"

    all_commits = read_commits(commits_file)
    query_lower = query.lower()

    matches = []
    for c in all_commits:
        searchable = f"{c.m} {c.f} {c.b}".lower()
        if query_lower in searchable:
            matches.append(c)

    if not matches:
        # Fallback: search git log directly
        from cortex_memory.git_utils import _run

        output = _run(
            ["git", "log", "--oneline", "--all", f"--grep={query}", "-20"],
            cwd=project,
        )
        if output:
            return f"## Search Results for '{query}' (from git log)\n\n{output}"
        return f"No results found for '{query}'."

    lines = [f"## Search Results for '{query}' ({len(matches)} matches)", ""]
    for c in matches[-20:]:
        lines.append(f"- {c.h[:8]} {c.m} [{c.b}] [+{c.i}/-{c.d}]")

    return "\n".join(lines)


@mcp.tool()
def cortex_status(project_dir: str | None = None) -> str:
    """Show Cortex memory stats for a project.

    Returns counts of commits, sessions, JSONL file sizes,
    and configuration summary.
    """
    project = _resolve_project(project_dir)
    cortex_dir = get_cortex_dir(project)
    config = load_config()

    lines = [
        f"# Cortex Status",
        f"**Project:** {project.name}",
        f"**Cortex dir:** {cortex_dir}",
        f"**Version:** {__version__}",
        "",
    ]

    # JSONL stats
    commits_file = cortex_dir / "commits.jsonl"
    sessions_file = cortex_dir / "sessions.jsonl"

    commits = read_commits(commits_file)
    sessions = read_sessions(sessions_file)

    lines += [
        "## Data",
        f"- Commits tracked: {len(commits)}",
        f"- Sessions: {count_sessions(sessions)}",
        f"- commits.jsonl: {_file_size(commits_file)}",
        f"- sessions.jsonl: {_file_size(sessions_file)}",
        "",
    ]

    # Config summary
    lines += [
        "## Config",
        f"- LLM provider: {config.llm_provider}",
        f"- LLM model: {config.llm_model}",
        f"- Retention: {config.retention_days} days",
        f"- CORTEX_HOME: {config.cortex_home}",
        "",
    ]

    # Git stats
    if is_git_repo(project):
        branch = get_branch(project)
        uncommitted = get_uncommitted_count(project)
        lines += [
            "## Git",
            f"- Branch: {branch}",
            f"- Uncommitted: {uncommitted} files",
        ]

    return "\n".join(lines)


@mcp.tool()
def cortex_file_history(filepath: str, project_dir: str | None = None) -> str:
    """Show git history for a specific file.

    Returns the commit log for a single file, useful for understanding
    when and why a file was changed.
    """
    project = _resolve_project(project_dir)
    history = get_file_history(filepath, path=project, count=20)

    if not history:
        return f"No history found for '{filepath}'."

    lines = [f"## History for {filepath} ({len(history)} commits)", ""]
    for entry in history:
        lines.append(f"- {entry['hash']} {entry['message']} ({entry['date'][:10]})")

    return "\n".join(lines)


# --- Resource ---

@mcp.resource("cortex://context")
def context_resource() -> str:
    """Live session context as an MCP resource."""
    return cortex_context()


# --- Helpers ---

def _iso_hours_ago(hours: int) -> str:
    """Return ISO timestamp for N hours ago."""
    from datetime import timedelta

    dt = datetime.now(timezone.utc) - timedelta(hours=hours)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def _file_size(path: Path) -> str:
    """Human-readable file size."""
    if not path.is_file():
        return "not found"
    size = path.stat().st_size
    if size < 1024:
        return f"{size} B"
    elif size < 1024 * 1024:
        return f"{size / 1024:.1f} KB"
    else:
        return f"{size / (1024 * 1024):.1f} MB"


def main() -> None:
    """Entry point for `cortex-memory` CLI."""
    mcp.run()


if __name__ == "__main__":
    main()
