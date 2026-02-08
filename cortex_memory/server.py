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
    get_coding_patterns,
    get_diff_between_commits,
    get_file_history,
    get_hot_files,
    get_last_commit_info,
    get_project_root,
    get_recent_commits,
    get_recent_file_changes,
    get_uncommitted_count,
    has_commits,
    is_git_repo,
    parse_commit_diff,
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


def _format_vector_search_results(
    query: str,
    results: list[dict[str, object]],
    file_type: str | None,
    branch: str | None,
    since: str | None,
    until: str | None,
    total_indexed: int,
) -> str:
    """Format vector search results as markdown.

    Args:
        query: Original search query
        results: List of search results with scores
        file_type: File type filter (for header)
        branch: Branch filter (for header)
        since: Since date filter (for header)
        until: Until date filter (for header)
        total_indexed: Total commits in vector store

    Returns:
        Formatted markdown string
    """
    filter_info = []
    if file_type:
        filter_info.append(f"type={file_type}")
    if branch:
        filter_info.append(f"branch={branch}")
    if since or until:
        filter_info.append(f"date={since or '*'} to {until or '*'}")

    header = f"## Search Results for '{query}' ({len(results)} matches"
    if filter_info:
        header += f", {', '.join(filter_info)}"
    header += ")"

    lines = [
        header,
        "",
        f"_Semantic search across {total_indexed} indexed commits_",
        "",
    ]

    for r in results:
        hash_short = r["hash"][:8] if len(r["hash"]) > 8 else r["hash"]
        message = r["message"]
        files = r["files"].split(",")[0] if "," in r["files"] else r["files"]
        branch_name = r["branch"]
        date_str = r["timestamp"][:10] if r["timestamp"] else ""
        score = r["score"]
        insertions = r.get("insertions", 0)
        deletions = r.get("deletions", 0)

        # Format score as percentage with visual indicator
        score_pct = int(score * 100)
        if score_pct >= 80:
            score_icon = "🔥"
        elif score_pct >= 60:
            score_icon = "✓"
        else:
            score_icon = "·"

        lines.append(f"- **{hash_short}** {message} _{score_icon} {score_pct}%_")
        lines.append(f"  `{files}` [{branch_name}] [{date_str}] [+{insertions}/-{deletions}]")

    return "\n".join(lines)


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

    # --- Recent file changes ---
    if is_git_repo(project):
        file_changes = get_recent_file_changes(project, count=10, with_stats=True)
        if file_changes:
            lines.append("## Recent File Changes (last 10 commits)")
            for item in file_changes[:8]:
                ins = item.get("insertions", 0)
                dels = item.get("deletions", 0)
                changes = item.get("changes", 0)
                lines.append(f"- {item['file']} ({changes}x, +{ins}/-{dels})")
            lines.append("")

    # --- Coding patterns ---
    if is_git_repo(project):
        patterns = get_coding_patterns(project, days=30)
        if patterns and patterns.get("file_types"):
            lines.append("## Coding Patterns (last 30 days)")

            # File types
            file_types = patterns.get("file_types", {})
            if file_types:
                top_types = list(file_types.items())[:5]
                lines.append(
                    "File types: " + ", ".join(f"{ext} ({count})" for ext, count in top_types)
                )

            # Active hours
            active_hours = patterns.get("active_hours", [])
            if active_hours:
                from collections import Counter
                hour_counts = Counter(active_hours)
                top_hours = hour_counts.most_common(3)
                hours_str = ", ".join(f"{h}:00 ({c})" for h, c in top_hours)
                lines.append(f"Most active hours: {hours_str}")

            # Common words
            common_words = patterns.get("common_words", {})
            if common_words:
                top_words = list(common_words.items())[:5]
                words_str = ", ".join(f"{word} ({count})" for word, count in top_words)
                lines.append(f"Common words: {words_str}")

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
def cortex_search(
    query: str,
    project_dir: str | None = None,
    file_type: str | None = None,
    branch: str | None = None,
    since: str | None = None,
    until: str | None = None,
    use_regex: bool = False,
    use_vector: bool = True,
    limit: int = 20,
) -> str:
    """Search commit history with semantic or text search.

    Args:
        query: Search query (natural language or keywords)
        project_dir: Project path
        file_type: Filter by file extension (e.g., "py", "js")
        branch: Filter by branch name
        since: Filter commits after this date (ISO format)
        until: Filter commits before this date (ISO format)
        use_regex: Treat query as regex pattern (forces text search)
        use_vector: Use semantic vector search if available (default: True)
        limit: Max results to return (default: 20)

    Returns:
        Formatted search results with relevance scores
    """
    import re

    project = _resolve_project(project_dir)
    cortex_dir = get_cortex_dir(project)
    commits_file = cortex_dir / "commits.jsonl"

    # Try vector search first if enabled and no regex
    if use_vector and not use_regex:
        try:
            from cortex_memory.embeddings import OllamaEmbeddings
            from cortex_memory.vector_store import VectorStore

            vector_store = VectorStore(cortex_dir)

            # Check if vector store has data
            stats = vector_store.get_stats()
            if stats.get("indexed", 0) > 0:
                # Generate query embedding
                embeddings = OllamaEmbeddings()
                query_embedding = embeddings.embed_text(query)

                # Search vector store
                results = vector_store.search_similar(
                    query_embedding,
                    limit=limit * 2,  # Get more, filter later
                    min_score=0.3,  # Minimum relevance threshold
                )

                if results:
                    # Apply additional filters
                    filtered_results = results

                    if file_type:
                        ext = file_type if file_type.startswith(".") else f".{file_type}"
                        filtered_results = [r for r in filtered_results if ext in r["files"].lower()]

                    if branch:
                        filtered_results = [r for r in filtered_results if r["branch"] == branch]

                    if since:
                        filtered_results = [r for r in filtered_results if r["timestamp"] >= since]

                    if until:
                        filtered_results = [r for r in filtered_results if r["timestamp"] <= until]

                    # Limit final results
                    filtered_results = filtered_results[:limit]

                    if filtered_results:
                        return _format_vector_search_results(
                            query,
                            filtered_results,
                            file_type,
                            branch,
                            since,
                            until,
                            stats.get("indexed", 0),
                        )

        except Exception as e:
            # Vector search failed, fall back to text search
            logger.warning(f"Vector search failed, falling back to text search: {e}")

    # Fallback to text search
    all_commits = read_commits(commits_file)

    # Apply filters
    filtered = all_commits

    # Date range filter
    if since:
        filtered = [c for c in filtered if c.t >= since]
    if until:
        filtered = [c for c in filtered if c.t <= until]

    # Branch filter
    if branch:
        filtered = [c for c in filtered if c.b == branch]

    # File type filter
    if file_type:
        ext = file_type if file_type.startswith(".") else f".{file_type}"
        filtered = [c for c in filtered if ext in c.f.lower()]

    # Search query
    matches = []
    if use_regex:
        try:
            pattern = re.compile(query, re.IGNORECASE)
            for c in filtered:
                searchable = f"{c.m} {c.f}"
                if pattern.search(searchable):
                    matches.append(c)
        except re.error as e:
            return f"Invalid regex pattern: {e}"
    else:
        query_lower = query.lower()
        for c in filtered:
            searchable = f"{c.m} {c.f} {c.b}".lower()
            if query_lower in searchable:
                matches.append(c)

    if not matches:
        # Build filter description
        filters = []
        if file_type:
            filters.append(f"file_type={file_type}")
        if branch:
            filters.append(f"branch={branch}")
        if since:
            filters.append(f"since={since}")
        if until:
            filters.append(f"until={until}")

        filter_str = f" (filters: {', '.join(filters)})" if filters else ""

        # Try fallback git log search
        if not filters:
            from cortex_memory.git_utils import _run
            output = _run(
                ["git", "log", "--oneline", "--all", f"--grep={query}", "-20"],
                cwd=project,
            )
            if output:
                return f"## Search Results for '{query}' (from git log)\n\n{output}"

        return f"No results found for '{query}'{filter_str}."

    # Sort by recency (newest first)
    matches.sort(key=lambda c: c.t, reverse=True)

    # Limit results
    matches = matches[:limit]

    # Format results
    filter_info = []
    if file_type:
        filter_info.append(f"type={file_type}")
    if branch:
        filter_info.append(f"branch={branch}")
    if since or until:
        filter_info.append(f"date={since or '*'} to {until or '*'}")

    header = f"## Search Results for '{query}' ({len(matches)} matches"
    if filter_info:
        header += f", {', '.join(filter_info)}"
    header += ")"

    lines = [header, "", "_Using text search (vector search not available)_", ""]

    for c in matches:
        # Show match context
        files = c.f.split(",")[0] if "," in c.f else c.f
        date_str = c.t[:10] if c.t else ""
        lines.append(f"- **{c.h[:8]}** {c.m}")
        lines.append(f"  `{files}` [{c.b}] [{date_str}] [+{c.i}/-{c.d}]")

    return "\n".join(lines)


@mcp.tool()
def cortex_diff(
    commit1: str | None = None,
    commit2: str | None = None,
    project_dir: str | None = None,
    count: int = 1,
    stat_only: bool = False,
) -> str:
    """Show changes between commits or in recent commits.

    Args:
        commit1: First commit hash (older), or None for HEAD~count
        commit2: Second commit hash (newer), or "HEAD"
        project_dir: Project path
        count: If commit1/commit2 not provided, show last N commits (default: 1)
        stat_only: Show only summary stats, not full diff

    Returns:
        Formatted diff output with file changes and stats
    """
    project = _resolve_project(project_dir)

    if not is_git_repo(project):
        return "Not a git repository."

    # Determine commit range
    if commit1 and commit2:
        c1, c2 = commit1, commit2
    elif commit1:
        c1, c2 = commit1, "HEAD"
    else:
        # Show last N commits
        c1 = f"HEAD~{count}" if count > 1 else "HEAD~1"
        c2 = "HEAD"

    # Get the diff
    diff_output = get_diff_between_commits(c1, c2, path=project, stat_only=stat_only)

    if not diff_output:
        return f"No differences found between {c1} and {c2}."

    # Parse diff for summary
    if stat_only:
        # Already in --stat format
        lines = [
            f"## Changes: {c1} → {c2}",
            "",
            "```",
            diff_output,
            "```",
        ]
    else:
        # Parse and show structured diff
        parsed = parse_commit_diff(diff_output)

        lines = [
            f"## Changes: {c1} → {c2}",
            "",
            f"**{parsed['summary']}**",
            "",
        ]

        if parsed["files"]:
            lines.append("### Files Changed")
            for f in parsed["files"][:20]:
                lines.append(f"- {f}")
            if len(parsed["files"]) > 20:
                lines.append(f"  ... and {len(parsed['files']) - 20} more")
            lines.append("")

        # Show condensed diff (first 30 lines)
        lines.append("### Diff Preview")
        lines.append("```diff")
        diff_lines = diff_output.splitlines()
        for line in diff_lines[:30]:
            lines.append(line)
        if len(diff_lines) > 30:
            lines.append(f"... ({len(diff_lines) - 30} more lines)")
        lines.append("```")

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


@mcp.tool()
def cortex_index(
    project_dir: str | None = None,
    limit: int | None = None,
    force_reindex: bool = False,
) -> str:
    """Index commits for semantic search.

    Generates embeddings for commits and stores them in the vector database.
    Automatically skips already-indexed commits unless force_reindex=True.

    Args:
        project_dir: Project path
        limit: Max commits to index (None = all pending commits)
        force_reindex: Clear existing index and reindex all commits

    Returns:
        Indexing progress and results
    """
    from cortex_memory.embeddings import OllamaEmbeddings
    from cortex_memory.indexer import CommitIndexer
    from cortex_memory.vector_store import VectorStore

    project = _resolve_project(project_dir)
    cortex_dir = get_cortex_dir(project)

    try:
        # Initialize indexer
        indexer = CommitIndexer(project)

        # Check if Ollama is running
        embeddings = OllamaEmbeddings()
        if not embeddings.test_connection():
            return (
                "## Indexing Failed\n\n"
                "Ollama embedding service is not available.\n\n"
                "**To fix:**\n"
                "1. Install Ollama: https://ollama.ai\n"
                "2. Start Ollama: `ollama serve`\n"
                "3. Pull model: `ollama pull nomic-embed-text`\n"
                "4. Try indexing again"
            )

        lines = ["## Cortex Indexing", ""]

        # Get current progress
        if not force_reindex:
            progress = indexer.get_indexing_progress()
            lines.append(f"**Status:** {progress['indexed']}/{progress['total']} commits indexed ({progress['progress']}%)")
            lines.append(f"**Pending:** {progress['pending']} commits")
            lines.append("")

        # Perform indexing
        if force_reindex:
            lines.append("**Mode:** Full reindex (clearing existing data)")
            lines.append("")
            result = indexer.reindex_all(batch_size=10)
        else:
            lines.append(f"**Mode:** Incremental (limit: {limit or 'all pending'})")
            lines.append("")
            result = indexer.index_new_commits(limit=limit, batch_size=10)

        # Format results
        lines.append("### Results")
        lines.append(f"- Indexed: {result['indexed']} commits")
        lines.append(f"- Failed: {result['failed']} commits")
        lines.append(f"- Skipped: {result['skipped']} commits")

        if result.get("message"):
            lines.append("")
            lines.append(f"_{result['message']}_")

        # Show updated stats
        vector_store = VectorStore(cortex_dir)
        stats = vector_store.get_stats()
        lines.append("")
        lines.append("### Vector Store Stats")
        lines.append(f"- Total indexed: {stats['indexed']}")
        lines.append(f"- Dimensions: {stats['dimensions']}")
        lines.append(f"- Size: {stats['size_mb']} MB")

        return "\n".join(lines)

    except Exception as e:
        return (
            f"## Indexing Error\n\n"
            f"Failed to index commits: {e}\n\n"
            f"Check that Ollama is running and the nomic-embed-text model is available."
        )


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
