"""Declarative base, naming conventions and shared column helpers."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import CheckConstraint, DateTime, MetaData, func, text
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import DeclarativeBase, Mapped, mapped_column

# Deterministic constraint names, so Alembic migrations are stable and
# readable ("ck_verse_text_kind", "fk_note_user_id_app_user").
NAMING_CONVENTION = {
    "ix": "ix_%(column_0_label)s",
    "uq": "uq_%(table_name)s_%(column_0_N_name)s",
    "ck": "ck_%(table_name)s_%(constraint_name)s",
    "fk": "fk_%(table_name)s_%(column_0_name)s_%(referred_table_name)s",
    "pk": "pk_%(table_name)s",
}


class Base(DeclarativeBase):
    metadata = MetaData(naming_convention=NAMING_CONVENTION)


def uuid_pk() -> Mapped[uuid.UUID]:
    return mapped_column(UUID(as_uuid=True), primary_key=True, server_default=text("gen_random_uuid()"))


def created_at() -> Mapped[datetime]:
    return mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


def updated_at() -> Mapped[datetime]:
    # Maintained by the set_updated_at() trigger (see migration), so it is
    # correct even for writes that bypass the ORM; the mobile sync relies on it.
    return mapped_column(DateTime(timezone=True), nullable=False, server_default=func.now())


def deleted_at() -> Mapped[datetime | None]:
    # Soft delete: sync clients must learn about deletions.
    return mapped_column(DateTime(timezone=True), nullable=True)


def check_in(name: str, column: str, values: tuple[str, ...] | list[str]) -> CheckConstraint:
    quoted = ", ".join("'" + v.replace("'", "''") + "'" for v in values)
    return CheckConstraint(f"{column} IN ({quoted})", name=name)


REVIEW_STATUSES = ("unreviewed", "pending", "reviewed", "rejected")
SPEAKERS = ("dhritarashtra", "sanjaya", "arjuna", "krishna")

# Kinds of text attached to a verse. Kept identical to the mobile content
# pack schema (content/schema/content_pack.sql).
VERSE_TEXT_KINDS = (
    "transliteration",
    "literal_translation",
    "translation",
    "simple",
    "deep",
    "practical",
    "story",
    "child",
    "sanskrit_terms",
    "commentary",
)
SOURCE_KINDS = (
    "scripture",
    "translation",
    "commentary",
    "transliteration",
    "editorial",
    "ai",
    "dataset",
    "recording",
)

# Tables whose updated_at is maintained by trigger (user-owned, synced data
# and mutable content). Used by the migration.
UPDATED_AT_TABLES = (
    "verse_text",
    "chapter_text",
    "app_user",
    "user_settings",
    "bookmark",
    "highlight",
    "note",
    "verse_state",
    "reading_progress",
    "listening_progress",
    "ai_conversation",
    "daily_practice",
    "revision_item",
)
