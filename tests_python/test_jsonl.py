"""Tests for cortex_memory.jsonl module."""

from __future__ import annotations

import json
from pathlib import Path

from cortex_memory.jsonl import (
    CommitRecord,
    SessionEvent,
    count_sessions,
    get_cortex_dir,
    get_last_session_end,
    read_commits,
    read_sessions,
)


class TestCommitRecord:
    def test_basic_fields(self):
        c = CommitRecord(h="abc1234", m="test commit")
        assert c.h == "abc1234"
        assert c.m == "test commit"
        assert c.i == 0
        assert c.d == 0

    def test_coerce_int_from_string(self):
        c = CommitRecord(h="abc", m="test", i="42", d="3")
        assert c.i == 42
        assert c.d == 3

    def test_coerce_int_bad_string(self):
        c = CommitRecord(h="abc", m="test", i="bad", d="nope")
        assert c.i == 0
        assert c.d == 0

    def test_coerce_project_from_int(self):
        c = CommitRecord(h="abc", m="test", p=1)
        assert c.p == "1"

    def test_coerce_project_from_none(self):
        c = CommitRecord(h="abc", m="test", p=None)
        assert c.p == ""


class TestReadCommits:
    def test_reads_valid_jsonl(self, tmp_cortex_dir: Path):
        commits = read_commits(tmp_cortex_dir / "commits.jsonl")
        assert len(commits) == 3
        assert commits[0].h == "abc1234"
        assert commits[0].m == "feat: add auth module"
        assert commits[2].b == "feature/cleanup"

    def test_since_filter(self, tmp_cortex_dir: Path):
        commits = read_commits(
            tmp_cortex_dir / "commits.jsonl",
            since="2026-02-08T11:30:00Z",
        )
        assert len(commits) == 1
        assert commits[0].h == "ghi9012"

    def test_missing_file(self, tmp_path: Path):
        commits = read_commits(tmp_path / "nonexistent.jsonl")
        assert commits == []

    def test_corrupted_lines(self, tmp_path: Path):
        f = tmp_path / "bad.jsonl"
        f.write_text(
            '{"h":"abc","m":"good"}\n'
            "this is not json\n"
            '{"h":"def","m":"also good"}\n'
            "another bad line {{{\n"
        )
        commits = read_commits(f)
        assert len(commits) == 2
        assert commits[0].h == "abc"
        assert commits[1].h == "def"

    def test_empty_file(self, tmp_path: Path):
        f = tmp_path / "empty.jsonl"
        f.write_text("")
        assert read_commits(f) == []

    def test_blank_lines(self, tmp_path: Path):
        f = tmp_path / "blanks.jsonl"
        f.write_text('\n\n{"h":"abc","m":"test"}\n\n')
        commits = read_commits(f)
        assert len(commits) == 1


class TestReadSessions:
    def test_reads_valid_sessions(self, tmp_cortex_dir: Path):
        sessions = read_sessions(tmp_cortex_dir / "sessions.jsonl")
        assert len(sessions) == 3
        assert sessions[0].type == "start"
        assert sessions[1].type == "end"

    def test_missing_file(self, tmp_path: Path):
        assert read_sessions(tmp_path / "nope.jsonl") == []


class TestSessionHelpers:
    def test_get_last_session_end(self, tmp_cortex_dir: Path):
        sessions = read_sessions(tmp_cortex_dir / "sessions.jsonl")
        assert get_last_session_end(sessions) == "2026-02-08T10:30:00Z"

    def test_get_last_session_end_no_ends(self):
        sessions = [SessionEvent(type="start", sid="s1", ts="2026-01-01T00:00:00Z")]
        assert get_last_session_end(sessions) is None

    def test_count_sessions(self, tmp_cortex_dir: Path):
        sessions = read_sessions(tmp_cortex_dir / "sessions.jsonl")
        assert count_sessions(sessions) == 2

    def test_count_sessions_empty(self):
        assert count_sessions([]) == 0


class TestGetCortexDir:
    def test_returns_cortex_subdir(self, tmp_path: Path):
        assert get_cortex_dir(tmp_path) == tmp_path / ".cortex"

    def test_string_input(self):
        assert get_cortex_dir("/tmp/myproject") == Path("/tmp/myproject/.cortex")
