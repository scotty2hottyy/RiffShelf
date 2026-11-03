"""Environment configuration for the standalone service."""

import os
from dataclasses import dataclass


@dataclass(frozen=True)
class Settings:
    docs_enabled: bool = True

    @classmethod
    def from_environment(cls) -> "Settings":
        value = os.environ.get("RIFFSHELF_DOCS_ENABLED", "true").strip().lower()
        if value not in {"true", "false"}:
            raise ValueError("RIFFSHELF_DOCS_ENABLED must be true or false")
        return cls(docs_enabled=value == "true")
