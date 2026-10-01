"""Runtime configuration from the environment. Secrets (database password,
LLM/TTS API keys) only ever live here on the server, never in the app."""

from __future__ import annotations

import os

DEFAULT_DATABASE_URL = "postgresql+psycopg://gita:gita@localhost:5432/gita"


def database_url() -> str:
    return os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL)
