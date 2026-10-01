"""Personal study data ("My Gita"): bookmarks, highlights, notes, verse
states and spaced-repetition revision. All rows are user-owned, soft-deleted
and carry updated_at for sync with the mobile app."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import (
    Boolean,
    CheckConstraint,
    DateTime,
    Float,
    ForeignKey,
    Index,
    Integer,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
    text,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, check_in, created_at, deleted_at, updated_at, uuid_pk

USER_FK = "app_user.id"


class Bookmark(Base):
    __tablename__ = "bookmark"
    __table_args__ = (
        # One live bookmark per verse per user; a deleted one may be re-created.
        Index(
            "uq_bookmark_user_verse_live",
            "user_id",
            "verse_id",
            unique=True,
            postgresql_where=text("deleted_at IS NULL"),
        ),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey(USER_FK, ondelete="CASCADE"))
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"))
    collection: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = updated_at()
    deleted_at: Mapped[datetime | None] = deleted_at()


class Highlight(Base):
    """A character range inside one rendered text: either the Sanskrit
    (verse_text_id NULL) or a specific verse_text row."""

    __tablename__ = "highlight"
    __table_args__ = (
        CheckConstraint("start_offset >= 0 AND end_offset > start_offset", name="valid_range"),
        Index("ix_highlight_user_verse", "user_id", "verse_id"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey(USER_FK, ondelete="CASCADE"))
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"))
    verse_text_id: Mapped[uuid.UUID | None] = mapped_column(ForeignKey("verse_text.id"))
    start_offset: Mapped[int] = mapped_column(Integer)
    end_offset: Mapped[int] = mapped_column(Integer)
    color: Mapped[str] = mapped_column(String(20), server_default="gold")
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = updated_at()
    deleted_at: Mapped[datetime | None] = deleted_at()


class Note(Base):
    """Free text attached to a verse, a chapter, or nothing (general journal).
    kind=question marks things to ask the AI teacher or revisit later."""

    __tablename__ = "note"
    __table_args__ = (
        check_in("kind", "kind", ("note", "question", "reflection")),
        CheckConstraint("chapter IS NULL OR verse_id IS NULL", name="single_anchor"),
        Index("ix_note_user_updated", "user_id", "updated_at"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey(USER_FK, ondelete="CASCADE"))
    verse_id: Mapped[str | None] = mapped_column(ForeignKey("verse.id"))
    chapter: Mapped[int | None] = mapped_column(ForeignKey("chapter.number"))
    kind: Mapped[str] = mapped_column(String(12), server_default="note")
    body: Mapped[str] = mapped_column(Text)
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = updated_at()
    deleted_at: Mapped[datetime | None] = deleted_at()


class VerseState(Base):
    __tablename__ = "verse_state"

    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey(USER_FK, ondelete="CASCADE"), primary_key=True)
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"), primary_key=True)
    is_favorite: Mapped[bool] = mapped_column(Boolean, server_default="false")
    is_understood: Mapped[bool] = mapped_column(Boolean, server_default="false")
    needs_revision: Mapped[bool] = mapped_column(Boolean, server_default="false")
    updated_at: Mapped[datetime] = updated_at()


class RevisionItem(Base):
    """A spaced-repetition card. Scheduling fields fit both the fixed
    1-2-4-7-14 day ladder (step) and FSRS (stability/difficulty), so the
    scheduler can be swapped without a migration."""

    __tablename__ = "revision_item"
    __table_args__ = (
        UniqueConstraint("user_id", "verse_id", "card_type"),
        check_in("card_type", "card_type", ("meaning", "concept", "application")),
        check_in("state", "state", ("new", "learning", "review", "relearning", "suspended")),
        CheckConstraint("reps >= 0 AND lapses >= 0 AND step >= 0", name="counters_nonnegative"),
        Index("ix_revision_item_due", "user_id", "due_at"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey(USER_FK, ondelete="CASCADE"))
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"))
    card_type: Mapped[str] = mapped_column(String(12))
    state: Mapped[str] = mapped_column(String(12), server_default="new")
    step: Mapped[int] = mapped_column(SmallInteger, server_default="0")
    stability: Mapped[float | None] = mapped_column(Float)
    difficulty: Mapped[float | None] = mapped_column(Float)
    due_at: Mapped[datetime] = mapped_column(DateTime(timezone=True))
    reps: Mapped[int] = mapped_column(Integer, server_default="0")
    lapses: Mapped[int] = mapped_column(Integer, server_default="0")
    last_reviewed_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = updated_at()
    deleted_at: Mapped[datetime | None] = deleted_at()


class RevisionReview(Base):
    """Append-only review log; lets the scheduler be re-fitted later."""

    __tablename__ = "revision_review"
    __table_args__ = (
        CheckConstraint("rating BETWEEN 1 AND 4", name="rating_range"),  # again/hard/good/easy
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    item_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("revision_item.id", ondelete="CASCADE"), index=True)
    reviewed_at: Mapped[datetime] = created_at()
    rating: Mapped[int] = mapped_column(SmallInteger)
    answer_text: Mapped[str | None] = mapped_column(Text)
    elapsed_days: Mapped[float | None] = mapped_column(Float)
    scheduled_days: Mapped[float | None] = mapped_column(Float)
