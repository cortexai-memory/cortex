"""Knowledge base schemas for decisions, patterns, lessons, and bug fixes."""

from __future__ import annotations

from datetime import datetime, timezone
from enum import Enum
from typing import Optional

from pydantic import BaseModel, Field


class KnowledgeCategory(str, Enum):
    """Knowledge entry categories."""

    DECISION = "decision"
    PATTERN = "pattern"
    BUG_FIX = "bug_fix"
    LESSON = "lesson"
    NOTE = "note"


class Decision(BaseModel):
    """Architectural or technical decision record."""

    id: Optional[str] = None
    title: str = Field(..., description="Brief decision title")
    content: str = Field(..., description="Detailed decision rationale")
    category: str = Field(default=KnowledgeCategory.DECISION, description="Always 'decision'")
    context: Optional[str] = Field(None, description="Why this decision was needed")
    consequences: Optional[str] = Field(None, description="Implications of this decision")
    alternatives: Optional[str] = Field(None, description="Other options considered")
    commit_hash: Optional[str] = Field(None, description="Related commit")
    files: Optional[str] = Field(None, description="Affected files (comma-separated)")
    tags: Optional[str] = Field(None, description="Tags for categorization (comma-separated)")
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ"),
        description="Creation timestamp",
    )

    def to_dict(self) -> dict[str, object]:
        """Convert to dict for storage."""
        return self.model_dump(exclude_none=False)


class Pattern(BaseModel):
    """Codebase pattern or convention."""

    id: Optional[str] = None
    title: str = Field(..., description="Pattern name")
    content: str = Field(..., description="Pattern description and usage")
    category: str = Field(default=KnowledgeCategory.PATTERN, description="Always 'pattern'")
    examples: Optional[str] = Field(None, description="Code examples")
    files: Optional[str] = Field(None, description="Files exhibiting this pattern")
    frequency: Optional[int] = Field(None, description="How often pattern appears")
    tags: Optional[str] = Field(None, description="Tags (comma-separated)")
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    def to_dict(self) -> dict[str, object]:
        """Convert to dict for storage."""
        return self.model_dump(exclude_none=False)


class BugFix(BaseModel):
    """Bug fix record with root cause and prevention."""

    id: Optional[str] = None
    title: str = Field(..., description="Bug summary")
    content: str = Field(..., description="Bug description and fix")
    category: str = Field(default=KnowledgeCategory.BUG_FIX, description="Always 'bug_fix'")
    root_cause: Optional[str] = Field(None, description="Why the bug happened")
    prevention: Optional[str] = Field(None, description="How to prevent similar bugs")
    commit_hash: Optional[str] = Field(None, description="Fix commit")
    files: Optional[str] = Field(None, description="Files involved (comma-separated)")
    severity: Optional[str] = Field(None, description="critical | high | medium | low")
    tags: Optional[str] = Field(None, description="Tags (comma-separated)")
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    def to_dict(self) -> dict[str, object]:
        """Convert to dict for storage."""
        return self.model_dump(exclude_none=False)


class Lesson(BaseModel):
    """Lesson learned from development experience."""

    id: Optional[str] = None
    title: str = Field(..., description="Lesson summary")
    content: str = Field(..., description="What was learned")
    category: str = Field(default=KnowledgeCategory.LESSON, description="Always 'lesson'")
    situation: Optional[str] = Field(None, description="Context where lesson was learned")
    action: Optional[str] = Field(None, description="What to do in similar situations")
    commit_hash: Optional[str] = Field(None, description="Related commit")
    tags: Optional[str] = Field(None, description="Tags (comma-separated)")
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    def to_dict(self) -> dict[str, object]:
        """Convert to dict for storage."""
        return self.model_dump(exclude_none=False)


class Note(BaseModel):
    """General note or reminder."""

    id: Optional[str] = None
    title: str = Field(..., description="Note title")
    content: str = Field(..., description="Note content")
    category: str = Field(default=KnowledgeCategory.NOTE, description="Always 'note'")
    files: Optional[str] = Field(None, description="Related files (comma-separated)")
    tags: Optional[str] = Field(None, description="Tags (comma-separated)")
    created_at: str = Field(
        default_factory=lambda: datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    )

    def to_dict(self) -> dict[str, object]:
        """Convert to dict for storage."""
        return self.model_dump(exclude_none=False)


# Type alias for any knowledge entry
KnowledgeEntry = Decision | Pattern | BugFix | Lesson | Note


def create_entry(
    category: str,
    title: str,
    content: str,
    **kwargs,
) -> KnowledgeEntry:
    """Factory function to create knowledge entries.

    Args:
        category: Entry category (decision, pattern, bug_fix, lesson, note)
        title: Entry title
        content: Entry content
        **kwargs: Additional fields specific to the category

    Returns:
        Appropriate knowledge entry instance

    Raises:
        ValueError: If category is invalid
    """
    category = category.lower()

    if category == KnowledgeCategory.DECISION:
        return Decision(title=title, content=content, **kwargs)
    elif category == KnowledgeCategory.PATTERN:
        return Pattern(title=title, content=content, **kwargs)
    elif category == KnowledgeCategory.BUG_FIX:
        return BugFix(title=title, content=content, **kwargs)
    elif category == KnowledgeCategory.LESSON:
        return Lesson(title=title, content=content, **kwargs)
    elif category == KnowledgeCategory.NOTE:
        return Note(title=title, content=content, **kwargs)
    else:
        raise ValueError(
            f"Invalid category: {category}. "
            f"Must be one of: {', '.join(KnowledgeCategory.__members__.values())}"
        )
