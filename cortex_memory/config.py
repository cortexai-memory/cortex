"""Cortex configuration — reads ~/.cortex/config (INI-like key=value)."""

from __future__ import annotations

import os
from pathlib import Path
from typing import Optional

from pydantic import BaseModel


class CortexConfig(BaseModel):
    """Configuration loaded from ~/.cortex/config."""

    cortex_home: Path
    llm_provider: str = "none"
    llm_model: str = "qwen2.5-coder:7b"
    retention_days: int = 30
    enrichment_prompts: str = ""
    openrouter_key: str = ""
    gemini_key: str = ""
    snapshot_on_exit: bool = True
    snapshot_retention_days: int = 7


def get_cortex_home() -> Path:
    """Return CORTEX_HOME (env var or default ~/.cortex)."""
    return Path(os.environ.get("CORTEX_HOME", Path.home() / ".cortex"))


def load_config(cortex_home: Optional[Path] = None) -> CortexConfig:
    """Load config from cortex_home/config file.

    The config file is a simple key=value format (bash-compatible).
    Lines starting with # are comments. Missing keys use defaults.
    """
    home = cortex_home or get_cortex_home()
    config_path = home / "config"

    values: dict[str, str] = {}
    if config_path.is_file():
        for line in config_path.read_text().splitlines():
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            if "=" in line:
                key, _, value = line.partition("=")
                values[key.strip()] = value.strip()

    return CortexConfig(
        cortex_home=home,
        llm_provider=values.get("llm_provider", "none"),
        llm_model=values.get("llm_model", "qwen2.5-coder:7b"),
        retention_days=int(values.get("retention_days", "30")),
        enrichment_prompts=values.get("enrichment_prompts", ""),
        openrouter_key=values.get("openrouter_key", ""),
        gemini_key=values.get("gemini_key", ""),
        snapshot_on_exit=values.get("snapshot_on_exit", "true").lower() == "true",
        snapshot_retention_days=int(values.get("snapshot_retention_days", "7")),
    )
