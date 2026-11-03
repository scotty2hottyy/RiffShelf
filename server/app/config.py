"""Environment configuration for the standalone service."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    docs_enabled: bool = True
    songsterr_timeout_seconds: float = 8.0
    search_rate_limit_per_minute: int = 30

    @classmethod
    def from_environment(cls) -> "Settings":
        value = os.environ.get("RIFFSHELF_DOCS_ENABLED", "true").strip().lower()
        if value not in {"true", "false"}:
            raise ValueError("RIFFSHELF_DOCS_ENABLED must be true or false")
        timeout = float(os.environ.get("RIFFSHELF_SONGSTERR_TIMEOUT_SECONDS", "8"))
        limit = int(os.environ.get("RIFFSHELF_SEARCH_RATE_LIMIT_PER_MINUTE", "30"))
        if not 0 < timeout <= 60:
            raise ValueError("RIFFSHELF_SONGSTERR_TIMEOUT_SECONDS must be between 0 and 60")
        if limit < 1:
            raise ValueError("RIFFSHELF_SEARCH_RATE_LIMIT_PER_MINUTE must be positive")
        return cls(docs_enabled=value == "true", songsterr_timeout_seconds=timeout,
                   search_rate_limit_per_minute=limit)
