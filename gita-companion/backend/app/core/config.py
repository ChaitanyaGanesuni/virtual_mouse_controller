"""Runtime configuration from the environment. Secrets (database password,
LLM/TTS API keys) only ever live here on the server, never in the app."""

from __future__ import annotations

import os

DEFAULT_DATABASE_URL = "postgresql+psycopg://gita:gita@localhost:5432/gita"


def normalize_database_url(url: str) -> str:
    """Hosted Postgres (Neon, Render, Supabase) hands out postgres:// or
    postgresql:// URLs, which SQLAlchemy maps to psycopg2. We ship psycopg 3."""
    for prefix in ("postgres://", "postgresql://"):
        if url.startswith(prefix):
            return "postgresql+psycopg://" + url[len(prefix) :]
    return url


def database_url() -> str:
    return normalize_database_url(os.environ.get("DATABASE_URL", DEFAULT_DATABASE_URL))
