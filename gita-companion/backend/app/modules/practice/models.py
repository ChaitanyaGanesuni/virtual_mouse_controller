"""Daily practice: Today's verse -> listen -> understand -> reflect -> apply -> journal."""

from __future__ import annotations

import uuid
from datetime import date, datetime

from sqlalchemy import Date, DateTime, ForeignKey, Text, UniqueConstraint
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, created_at, deleted_at, updated_at, uuid_pk


class DailyPractice(Base):
    __tablename__ = "daily_practice"
    __table_args__ = (UniqueConstraint("user_id", "practice_date"),)

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("app_user.id", ondelete="CASCADE"))
    practice_date: Mapped[date] = mapped_column(Date)  # in the user's timezone
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"))
    listened_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    understood_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    reflected_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    applied_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    # Private journal text. Never sent to an LLM unless the user explicitly asks.
    journal_text: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = updated_at()
    deleted_at: Mapped[datetime | None] = deleted_at()
