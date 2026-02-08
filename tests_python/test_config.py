"""Tests for cortex_memory.config module."""

from __future__ import annotations

import os
from pathlib import Path

from cortex_memory.config import CortexConfig, get_cortex_home, load_config


class TestGetCortexHome:
    def test_default(self, monkeypatch):
        monkeypatch.delenv("CORTEX_HOME", raising=False)
        home = get_cortex_home()
        assert home == Path.home() / ".cortex"

    def test_env_override(self, monkeypatch):
        monkeypatch.setenv("CORTEX_HOME", "/tmp/custom-cortex")
        assert get_cortex_home() == Path("/tmp/custom-cortex")


class TestLoadConfig:
    def test_loads_from_file(self, tmp_cortex_home: Path):
        config = load_config(tmp_cortex_home)
        assert config.llm_provider == "none"
        assert config.llm_model == "qwen2.5-coder:7b"
        assert config.retention_days == 30

    def test_defaults_when_no_file(self, tmp_path: Path):
        config = load_config(tmp_path)
        assert config.llm_provider == "none"
        assert config.cortex_home == tmp_path

    def test_handles_comments_and_blanks(self, tmp_path: Path):
        config_file = tmp_path / "config"
        config_file.write_text(
            "# This is a comment\n"
            "\n"
            "llm_provider=ollama\n"
            "# Another comment\n"
            "retention_days=60\n"
        )
        config = load_config(tmp_path)
        assert config.llm_provider == "ollama"
        assert config.retention_days == 60

    def test_all_fields(self, tmp_path: Path):
        config_file = tmp_path / "config"
        config_file.write_text(
            "llm_provider=openrouter\n"
            "llm_model=gpt-4\n"
            "retention_days=90\n"
            "enrichment_prompts=commit,decisions\n"
            "openrouter_key=sk-test\n"
            "snapshot_on_exit=false\n"
            "snapshot_retention_days=14\n"
        )
        config = load_config(tmp_path)
        assert config.llm_provider == "openrouter"
        assert config.llm_model == "gpt-4"
        assert config.retention_days == 90
        assert config.enrichment_prompts == "commit,decisions"
        assert config.openrouter_key == "sk-test"
        assert config.snapshot_on_exit is False
        assert config.snapshot_retention_days == 14
