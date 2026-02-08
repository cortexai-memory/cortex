"""Tests for schemas module."""

import pytest

from cortex_memory.schemas import (
    BugFix,
    Decision,
    KnowledgeCategory,
    Lesson,
    Note,
    Pattern,
    create_entry,
)


class TestKnowledgeModels:
    """Test knowledge entry models."""

    def test_decision_basic(self):
        """Test basic decision creation."""
        decision = Decision(
            title="Use PostgreSQL",
            content="Chose PostgreSQL for better JSON support",
        )
        assert decision.title == "Use PostgreSQL"
        assert decision.category == KnowledgeCategory.DECISION
        assert decision.created_at is not None

    def test_pattern_basic(self):
        """Test basic pattern creation."""
        pattern = Pattern(
            title="Repository Pattern",
            content="Use repository pattern for data access",
        )
        assert pattern.title == "Repository Pattern"
        assert pattern.category == KnowledgeCategory.PATTERN

    def test_bug_fix_basic(self):
        """Test basic bug fix creation."""
        bug = BugFix(
            title="Fix null pointer",
            content="Fixed null pointer in auth module",
            root_cause="Missing null check",
            prevention="Add validation",
        )
        assert bug.title == "Fix null pointer"
        assert bug.category == KnowledgeCategory.BUG_FIX
        assert bug.root_cause == "Missing null check"

    def test_lesson_basic(self):
        """Test basic lesson creation."""
        lesson = Lesson(
            title="Always test edge cases",
            content="Edge cases often reveal bugs",
        )
        assert lesson.title == "Always test edge cases"
        assert lesson.category == KnowledgeCategory.LESSON

    def test_note_basic(self):
        """Test basic note creation."""
        note = Note(
            title="TODO: Refactor auth",
            content="Auth module needs cleanup",
        )
        assert note.title == "TODO: Refactor auth"
        assert note.category == KnowledgeCategory.NOTE

    def test_to_dict(self):
        """Test conversion to dict."""
        decision = Decision(
            title="Test",
            content="Content",
            context="Context",
            tags="tag1,tag2",
        )
        d = decision.to_dict()
        assert d["title"] == "Test"
        assert d["category"] == "decision"
        assert d["tags"] == "tag1,tag2"

    def test_create_entry_decision(self):
        """Test factory function for decisions."""
        entry = create_entry(
            category="decision",
            title="Test Decision",
            content="Content",
        )
        assert isinstance(entry, Decision)
        assert entry.title == "Test Decision"

    def test_create_entry_pattern(self):
        """Test factory function for patterns."""
        entry = create_entry(
            category="pattern",
            title="Test Pattern",
            content="Content",
        )
        assert isinstance(entry, Pattern)

    def test_create_entry_invalid(self):
        """Test factory with invalid category."""
        with pytest.raises(ValueError, match="Invalid category"):
            create_entry(
                category="invalid",
                title="Test",
                content="Content",
            )
