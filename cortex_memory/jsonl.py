"""Read and parse Cortex JSONL files (commits.jsonl, sessions.jsonl)."""

from __future__ import annotations

import json
import logging
from datetime import datetime
from pathlib import Path
from typing import Optional

from pydantic import BaseModel, field_validator

logger = logging.getLogger(__name__)


class CommitRecord(BaseModel):
    """A single enriched commit from commits.jsonl.

    Fields match bash Layer 0 output:
      h=hash, m=message, f=files, i=insertions, d=deletions,
      b=branch, p=project, t=timestamp
    """

    h: str
    m: str
    f: str = ""
    i: int = 0
    d: int = 0
    b: str = ""
    p: str = ""
    t: str = ""

    @field_validator("i", "d", mode="before")
    @classmethod
    def coerce_int(cls, v: object) -> int:
        if isinstance(v, str):
            try:
                return int(v)
            except ValueError:
                return 0
        return v  # type: ignore[return-value]

    @field_validator("p", mode="before")
    @classmethod
    def coerce_str(cls, v: object) -> str:
        return str(v) if v is not None else ""


class SessionEvent(BaseModel):
    """A session start/end event from sessions.jsonl."""

    type: str  # "start" or "end"
    sid: str = ""
    ts: str = ""
    project: str = ""


def get_cortex_dir(project_dir: str | Path) -> Path:
    """Return the .cortex directory for a project."""
    return Path(project_dir) / ".cortex"


def read_commits(
    path: str | Path,
    since: Optional[str] = None,
) -> list[CommitRecord]:
    """Read commit records from a JSONL file, skipping corrupted lines.

    Args:
        path: Path to commits.jsonl
        since: ISO timestamp cutoff — only return commits after this time
    """
    path = Path(path)
    if not path.is_file():
        return []

    commits: list[CommitRecord] = []
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            record = CommitRecord.model_validate(data)
            if since and record.t and record.t < since:
                continue
            commits.append(record)
        except (json.JSONDecodeError, Exception) as exc:
            logger.debug("Skipping corrupted line %d in %s: %s", lineno, path, exc)
    return commits


def read_sessions(path: str | Path) -> list[SessionEvent]:
    """Read session events from a JSONL file, skipping corrupted lines."""
    path = Path(path)
    if not path.is_file():
        return []

    events: list[SessionEvent] = []
    for lineno, line in enumerate(path.read_text().splitlines(), 1):
        line = line.strip()
        if not line:
            continue
        try:
            data = json.loads(line)
            event = SessionEvent.model_validate(data)
            events.append(event)
        except (json.JSONDecodeError, Exception) as exc:
            logger.debug("Skipping corrupted line %d in %s: %s", lineno, path, exc)
    return events


def get_last_session_end(sessions: list[SessionEvent]) -> Optional[str]:
    """Return the timestamp of the most recent session end event."""
    for event in reversed(sessions):
        if event.type == "end" and event.ts:
            return event.ts
    return None


def count_sessions(sessions: list[SessionEvent]) -> int:
    """Count the number of session starts."""
    return sum(1 for e in sessions if e.type == "start")
