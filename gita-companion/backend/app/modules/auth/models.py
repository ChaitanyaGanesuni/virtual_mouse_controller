"""Users, refresh tokens and per-user settings."""

from __future__ import annotations

import uuid
from datetime import datetime, time

from sqlalchemy import (
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    String,
    Text,
    Time,
    UniqueConstraint,
)
from sqlalchemy.dialects.postgresql import JSONB, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, check_in, created_at, deleted_at, updated_at, uuid_pk

AUTH_PROVIDERS = ("anonymous", "google", "email")


class AppUser(Base):
    __tablename__ = "app_user"
    __table_args__ = (
        check_in("auth_provider", "auth_provider", AUTH_PROVIDERS),
        UniqueConstraint("auth_provider", "external_subject"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    auth_provider: Mapped[str] = mapped_column(String(20))
    # Provider's stable subject id (Google 'sub', email address, or device id for anonymous).
    external_subject: Mapped[str] = mapped_column(Text)
    email: Mapped[str | None] = mapped_column(Text)
    display_name: Mapped[str | None] = mapped_column(Text)
    last_seen_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = updated_at()
    deleted_at: Mapped[datetime | None] = deleted_at()


class RefreshToken(Base):
    """Rotating refresh tokens. Only a hash is stored; reuse of a rotated
    token revokes the whole family (token-theft detection)."""

    __tablename__ = "refresh_token"
    __table_args__ = (Index("ix_refresh_token_family", "family_id"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("app_user.id", ondelete="CASCADE"), index=True)
    token_hash: Mapped[str] = mapped_column(String(64), unique=True)
    family_id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True))
    expires_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    revoked_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at()


class UserSettings(Base):
    """UI language and content languages are independent (e.g. UI=English,
    verse=Sanskrit in Telugu script, explanation=Telugu)."""

    __tablename__ = "user_settings"
    __table_args__ = (
        check_in("verse_script", "verse_script", ("sa", "sa-Latn", "sa-Telu")),
        check_in("theme", "theme", ("system", "light", "dark")),
        CheckConstraint("text_scale BETWEEN 0.75 AND 2.5", name="text_scale_range"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("app_user.id", ondelete="CASCADE"), primary_key=True
    )
    ui_language: Mapped[str] = mapped_column(String(20), server_default="en")
    verse_script: Mapped[str] = mapped_column(String(20), server_default="sa")
    translation_language: Mapped[str] = mapped_column(String(20), server_default="en")
    explanation_language: Mapped[str] = mapped_column(String(20), server_default="en")
    translation_source_id: Mapped[str | None] = mapped_column(ForeignKey("source.id"))
    explanation_source_id: Mapped[str | None] = mapped_column(ForeignKey("source.id"))
    text_scale: Mapped[float] = mapped_column(Float, server_default="1.0")
    theme: Mapped[str] = mapped_column(String(10), server_default="system")
    voice_prefs: Mapped[dict] = mapped_column(JSONB, server_default="{}")
    daily_reminder_time: Mapped[time | None] = mapped_column(Time)
    timezone: Mapped[str] = mapped_column(Text, server_default="UTC")
    updated_at: Mapped[datetime] = updated_at()
