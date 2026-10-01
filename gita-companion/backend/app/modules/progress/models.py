"""Reading and listening progress.

"Chapter 2 — 14 of 72 verses" = count(verse_read) for that chapter.
Listening resumes from (manifest, chunk, position) after the app is closed.
"""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, Float, ForeignKey, Integer, String
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, created_at, updated_at

USER_FK = "app_user.id"


class VerseRead(Base):
    __tablename__ = "verse_read"
    __table_args__ = (CheckConstraint("read_count > 0", name="read_count_positive"),)

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey(USER_FK, ondelete="CASCADE"), primary_key=True)
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"), primary_key=True)
    first_read_at: Mapped[datetime] = created_at()
    last_read_at: Mapped[datetime] = created_at()
    read_count: Mapped[int] = mapped_column(Integer, server_default="1")


class ReadingProgress(Base):
    __tablename__ = "reading_progress"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey(USER_FK, ondelete="CASCADE"), primary_key=True)
    chapter: Mapped[int] = mapped_column(ForeignKey("chapter.number"), primary_key=True)
    last_verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"))
    updated_at: Mapped[datetime] = updated_at()


class ListeningProgress(Base):
    __tablename__ = "listening_progress"
    __table_args__ = (
        CheckConstraint("position_seconds >= 0", name="position_nonnegative"),
        CheckConstraint("speed IN (0.75, 1.0, 1.25, 1.5, 1.75, 2.0)", name="speed_allowed"),
    )

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey(USER_FK, ondelete="CASCADE"), primary_key=True)
    manifest_id: Mapped[str] = mapped_column(ForeignKey("audio_manifest.id"), primary_key=True)
    manifest_version: Mapped[int] = mapped_column(Integer)
    chapter: Mapped[int | None] = mapped_column(ForeignKey("chapter.number"))
    verse_id: Mapped[str | None] = mapped_column(ForeignKey("verse.id"))
    audio_chunk_id: Mapped[str] = mapped_column(String(160))
    position_seconds: Mapped[float] = mapped_column(Float, server_default="0")
    speed: Mapped[float] = mapped_column(Float, server_default="1.0")
    completed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    updated_at: Mapped[datetime] = updated_at()
