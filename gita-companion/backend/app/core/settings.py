"""API server settings, read once from the environment.

Secrets (JWT signing key, database password, LLM keys) exist only on the
server. The mobile app holds nothing but its own short-lived tokens.
"""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

from app.core.config import DEFAULT_DATABASE_URL, normalize_database_url


class SettingsError(RuntimeError):
    pass


@dataclass(frozen=True)
class Settings:
    database_url: str
    jwt_secret: str
    environment: str = "production"  # "production" | "development" | "test"
    access_token_ttl_s: int = 15 * 60
    refresh_token_ttl_s: int = 60 * 24 * 3600
    # AI tutor limits (per user per UTC day / per IP per hour for new accounts).
    tutor_daily_questions: int = 30
    signups_per_ip_per_hour: int = 10
    # Backstop: X-Forwarded-For can be forged, so also cap new accounts overall.
    signups_per_hour_total: int = 300
    # Cloudflare/Render put the client address in X-Forwarded-For.
    trust_forwarded_for: bool = True
    # Content dataset (content format 3) for the tutor's hybrid retrieval.
    content_dataset: Path | None = None

    @staticmethod
    def from_env(env: dict[str, str] | None = None) -> Settings:
        env = dict(os.environ) if env is None else env
        environment = env.get("APP_ENV", "production")
        secret = env.get("JWT_SECRET", "")
        if len(secret) < 32:
            if environment == "production":
                raise SettingsError("JWT_SECRET must be set to a random string of at least 32 characters")
            secret = "development-only-secret-not-for-production-use"
        return Settings(
            database_url=normalize_database_url(env.get("DATABASE_URL", DEFAULT_DATABASE_URL)),
            jwt_secret=secret,
            environment=environment,
            access_token_ttl_s=int(env.get("ACCESS_TOKEN_TTL_S", 15 * 60)),
            refresh_token_ttl_s=int(env.get("REFRESH_TOKEN_TTL_S", 60 * 24 * 3600)),
            tutor_daily_questions=int(env.get("TUTOR_DAILY_QUESTIONS", 30)),
            signups_per_ip_per_hour=int(env.get("SIGNUPS_PER_IP_PER_HOUR", 10)),
            signups_per_hour_total=int(env.get("SIGNUPS_PER_HOUR_TOTAL", 300)),
            trust_forwarded_for=env.get("TRUST_FORWARDED_FOR", "1") == "1",
            content_dataset=_dataset_path(env),
        )


_BACKEND = Path(__file__).resolve().parents[2]


def _dataset_path(env: dict[str, str]) -> Path | None:
    if env.get("CONTENT_DATASET"):
        return Path(env["CONTENT_DATASET"])
    for candidate in (_BACKEND / "content" / "gita.json", _BACKEND.parent / "content" / "data" / "gita.json"):
        if candidate.exists():
            return candidate
    return None
