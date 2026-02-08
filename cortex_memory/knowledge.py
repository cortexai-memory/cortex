"""Knowledge extraction from commits using LLMs."""

from __future__ import annotations

import json
import logging
from typing import Optional

from cortex_memory.jsonl import CommitRecord
from cortex_memory.schemas import BugFix, Decision, KnowledgeEntry, Lesson, Pattern

logger = logging.getLogger(__name__)


class KnowledgeExtractorError(Exception):
    """Raised when knowledge extraction fails."""


class KnowledgeExtractor:
    """Extract structured knowledge from commit messages using LLMs.

    Works with Ollama or other LLM providers to identify decisions, patterns,
    lessons, and bug fixes from commit history.
    """

    def __init__(
        self,
        provider: str = "ollama",
        model: str = "qwen2.5-coder:7b",
        host: str = "http://localhost:11434",
    ):
        """Initialize knowledge extractor.

        Args:
            provider: LLM provider (ollama, openai, anthropic)
            model: Model name
            host: API endpoint (for Ollama)
        """
        self.provider = provider
        self.model = model
        self.host = host
        self._client: Optional[object] = None

    def _get_client(self):
        """Lazy-load LLM client."""
        if self._client is None:
            if self.provider == "ollama":
                try:
                    import ollama
                    self._client = ollama.Client(host=self.host)
                except ImportError as e:
                    raise KnowledgeExtractorError(
                        "ollama package not installed. Install with: pip install ollama"
                    ) from e
            else:
                raise KnowledgeExtractorError(f"Provider '{self.provider}' not supported yet")

        return self._client

    def extract_from_commit(
        self,
        commit: CommitRecord,
        diff: Optional[str] = None,
    ) -> list[KnowledgeEntry]:
        """Extract knowledge from a single commit.

        Args:
            commit: Commit record
            diff: Optional commit diff for context

        Returns:
            List of extracted knowledge entries (may be empty)

        Raises:
            KnowledgeExtractorError: If extraction fails
        """
        # Prepare context for LLM
        context = self._prepare_commit_context(commit, diff)

        # Build prompt
        prompt = self._build_extraction_prompt(context)

        try:
            client = self._get_client()

            # Call LLM
            response = client.chat(
                model=self.model,
                messages=[
                    {
                        "role": "system",
                        "content": (
                            "You are a code analyst. Extract structured knowledge from git commits. "
                            "Identify architectural decisions, patterns, bug fixes, and lessons learned. "
                            "Respond with JSON only, no explanations."
                        ),
                    },
                    {"role": "user", "content": prompt},
                ],
                format="json",
                options={"temperature": 0.3},
            )

            # Parse response
            result = response["message"]["content"]
            entries = self._parse_llm_response(result, commit)

            logger.info(f"Extracted {len(entries)} knowledge entries from commit {commit.h[:8]}")
            return entries

        except Exception as e:
            logger.warning(f"Failed to extract knowledge from commit {commit.h[:8]}: {e}")
            return []

    def _prepare_commit_context(self, commit: CommitRecord, diff: Optional[str]) -> str:
        """Prepare commit context for LLM analysis.

        Args:
            commit: Commit record
            diff: Optional diff

        Returns:
            Formatted context string
        """
        lines = [
            f"Commit: {commit.h}",
            f"Message: {commit.m}",
            f"Branch: {commit.b}",
            f"Files: {commit.f}",
            f"Changes: +{commit.i}/-{commit.d}",
        ]

        if diff:
            lines.append("\nDiff preview:")
            # Limit diff size to avoid context overflow
            diff_lines = diff.splitlines()[:50]
            lines.extend(diff_lines)
            if len(diff.splitlines()) > 50:
                lines.append(f"... ({len(diff.splitlines()) - 50} more lines)")

        return "\n".join(lines)

    def _build_extraction_prompt(self, context: str) -> str:
        """Build LLM prompt for knowledge extraction.

        Args:
            context: Commit context

        Returns:
            Prompt string
        """
        return f"""Analyze this commit and extract any significant knowledge.

{context}

Look for:
- **Decisions**: Architectural choices, technology selections, design patterns adopted
- **Patterns**: Code patterns, conventions, best practices introduced or followed
- **Bug Fixes**: Bugs fixed, root causes, prevention strategies
- **Lessons**: Insights learned, gotchas discovered, things to remember

Respond with JSON:
{{
  "entries": [
    {{
      "type": "decision|pattern|bug_fix|lesson",
      "title": "Brief title",
      "content": "Detailed description",
      "context": "Why this matters (optional)",
      "tags": ["tag1", "tag2"]
    }}
  ]
}}

If nothing significant, return {{"entries": []}}.
Only extract meaningful knowledge, not routine changes."""

    def _parse_llm_response(
        self,
        response: str,
        commit: CommitRecord,
    ) -> list[KnowledgeEntry]:
        """Parse LLM JSON response into knowledge entries.

        Args:
            response: LLM response (JSON string)
            commit: Source commit

        Returns:
            List of knowledge entries
        """
        try:
            data = json.loads(response)
            entries = []

            for item in data.get("entries", []):
                entry_type = item.get("type", "").lower()
                title = item.get("title", "")
                content = item.get("content", "")
                context = item.get("context")
                tags = item.get("tags", [])

                if not title or not content:
                    continue

                # Build common fields
                common = {
                    "title": title,
                    "content": content,
                    "commit_hash": commit.h,
                    "files": commit.f,
                    "tags": ",".join(tags) if tags else None,
                }

                # Create appropriate entry type
                if entry_type == "decision":
                    entries.append(Decision(**common, context=context))
                elif entry_type == "pattern":
                    entries.append(Pattern(**common))
                elif entry_type == "bug_fix":
                    root_cause = item.get("root_cause")
                    prevention = item.get("prevention")
                    entries.append(
                        BugFix(**common, root_cause=root_cause, prevention=prevention)
                    )
                elif entry_type == "lesson":
                    situation = item.get("situation")
                    action = item.get("action")
                    entries.append(Lesson(**common, situation=situation, action=action))
                else:
                    logger.warning(f"Unknown entry type: {entry_type}")

            return entries

        except json.JSONDecodeError as e:
            logger.error(f"Failed to parse LLM response as JSON: {e}")
            return []
        except Exception as e:
            logger.error(f"Failed to parse LLM response: {e}")
            return []

    def batch_extract(
        self,
        commits: list[CommitRecord],
        max_commits: int = 10,
    ) -> list[tuple[CommitRecord, list[KnowledgeEntry]]]:
        """Extract knowledge from multiple commits.

        Args:
            commits: List of commits to analyze
            max_commits: Maximum commits to process

        Returns:
            List of (commit, entries) tuples
        """
        results = []

        for commit in commits[:max_commits]:
            try:
                entries = self.extract_from_commit(commit)
                if entries:
                    results.append((commit, entries))
            except Exception as e:
                logger.warning(f"Failed to extract from commit {commit.h[:8]}: {e}")
                continue

        return results

    def test_connection(self) -> bool:
        """Test if LLM service is available.

        Returns:
            True if service is reachable
        """
        try:
            client = self._get_client()

            # Simple test chat
            response = client.chat(
                model=self.model,
                messages=[{"role": "user", "content": "test"}],
                options={"num_predict": 5},
            )

            return "message" in response
        except Exception as e:
            logger.debug(f"Connection test failed: {e}")
            return False


def simple_pattern_detection(commits: list[CommitRecord]) -> list[Pattern]:
    """Detect patterns from commit messages without LLM.

    Simple rule-based detection for common patterns.

    Args:
        commits: List of commits

    Returns:
        List of detected patterns
    """
    patterns = []

    # Pattern: Conventional commits
    conventional_prefixes = ["feat:", "fix:", "docs:", "test:", "refactor:", "chore:"]
    conventional_count = sum(
        1 for c in commits if any(c.m.lower().startswith(p) for p in conventional_prefixes)
    )

    if conventional_count > len(commits) * 0.6:  # More than 60% use convention
        patterns.append(
            Pattern(
                title="Conventional Commits",
                content="Project uses Conventional Commits specification for commit messages",
                examples="feat:, fix:, docs:, test:, refactor:, chore:",
                frequency=conventional_count,
                tags="convention,commits",
            )
        )

    # Pattern: Test-driven development
    test_files = sum(1 for c in commits if "test" in c.f.lower())
    if test_files > len(commits) * 0.3:  # More than 30% touch tests
        patterns.append(
            Pattern(
                title="Test-Driven Development",
                content="Frequent test file changes suggest TDD or high test coverage practices",
                frequency=test_files,
                tags="testing,tdd",
            )
        )

    return patterns
