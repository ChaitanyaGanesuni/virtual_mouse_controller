"""Scripture content: chapters, verses and every text attached to them.

Design: `verse` holds only invariant facts plus the Devanagari text.
Everything else (transliterations, translations, explanations, commentary,
AI explanations) is a `verse_text` row tagged with kind, language and
source. A new translation, commentary or language is new rows, never a
schema change. Mirrors content/schema/content_pack.sql.
"""

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
    func,
)
from sqlalchemy.dialects.postgresql import UUID
from sqlalchemy.orm import Mapped, mapped_column, relationship

from app.core.db import (
    REVIEW_STATUSES,
    SOURCE_KINDS,
    SPEAKERS,
    VERSE_TEXT_KINDS,
    Base,
    check_in,
    created_at,
    updated_at,
)


class Source(Base):
    """Licence register entry. Every text row points at one."""

    __tablename__ = "source"
    __table_args__ = (check_in("kind", "kind", SOURCE_KINDS),)

    id: Mapped[str] = mapped_column(String(80), primary_key=True)
    kind: Mapped[str] = mapped_column(String(20))
    title: Mapped[str] = mapped_column(Text)
    author: Mapped[str] = mapped_column(Text)
    year: Mapped[int | None] = mapped_column(SmallInteger)
    language: Mapped[str] = mapped_column(String(20))
    license: Mapped[str] = mapped_column(Text)
    license_note: Mapped[str] = mapped_column(Text, server_default="")
    url: Mapped[str | None] = mapped_column(Text)
    retrieved_commit: Mapped[str | None] = mapped_column(String(64))
    tradition: Mapped[str | None] = mapped_column(Text)
    is_ai_generated: Mapped[bool] = mapped_column(Boolean, server_default="false")
    model_id: Mapped[str | None] = mapped_column(Text)
    prompt_version: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = created_at()


class Chapter(Base):
    __tablename__ = "chapter"
    __table_args__ = (
        CheckConstraint("number BETWEEN 1 AND 18", name="number_range"),
        CheckConstraint("verse_count > 0", name="verse_count_positive"),
    )

    number: Mapped[int] = mapped_column(SmallInteger, primary_key=True, autoincrement=False)
    name_sa: Mapped[str] = mapped_column(Text)
    verse_count: Mapped[int] = mapped_column(SmallInteger)

    verses: Mapped[list[Verse]] = relationship(back_populates="chapter_ref", order_by="Verse.verse")


class ChapterText(Base):
    __tablename__ = "chapter_text"
    __table_args__ = (
        check_in("kind", "kind", ("name", "title", "summary", "theme")),
        check_in("review_status", "review_status", REVIEW_STATUSES),
        UniqueConstraint("chapter", "source_id", "kind", "language"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    chapter: Mapped[int] = mapped_column(ForeignKey("chapter.number"))
    source_id: Mapped[str] = mapped_column(ForeignKey("source.id"))
    kind: Mapped[str] = mapped_column(String(20))
    language: Mapped[str] = mapped_column(String(20))
    body: Mapped[str] = mapped_column(Text)
    review_status: Mapped[str] = mapped_column(String(12), server_default="unreviewed")
    updated_at: Mapped[datetime] = updated_at()


class Speaker(Base):
    __tablename__ = "speaker"
    __table_args__ = (check_in("id", "id", SPEAKERS),)

    id: Mapped[str] = mapped_column(String(20), primary_key=True)
    name_en: Mapped[str] = mapped_column(Text)
    line_sa: Mapped[str] = mapped_column(Text)
    line_sa_latn: Mapped[str] = mapped_column(Text)
    line_sa_telu: Mapped[str] = mapped_column(Text)


class Verse(Base):
    """One verse. id is '<chapter>.<verse>' (e.g. '2.47'); 13.0 is the one
    non-canonical verse (Arjuna's question, 13.1 in 701-verse editions).
    A trigger rejects verse numbers beyond the chapter's verse count."""

    __tablename__ = "verse"
    __table_args__ = (
        UniqueConstraint("chapter", "verse"),
        CheckConstraint("verse >= 0", name="verse_nonnegative"),
        CheckConstraint("id = chapter::text || '.' || verse::text", name="id_matches_ref"),
        CheckConstraint("is_canonical OR verse = 0", name="only_verse_zero_noncanonical"),
        check_in("review_status", "review_status", REVIEW_STATUSES),
    )

    id: Mapped[str] = mapped_column(String(8), primary_key=True)
    chapter: Mapped[int] = mapped_column(ForeignKey("chapter.number"))
    verse: Mapped[int] = mapped_column(SmallInteger)
    is_canonical: Mapped[bool] = mapped_column(Boolean)
    speaker: Mapped[str | None] = mapped_column(ForeignKey("speaker.id"))
    sanskrit: Mapped[str] = mapped_column(Text)
    source_id: Mapped[str] = mapped_column(ForeignKey("source.id"))
    review_status: Mapped[str] = mapped_column(String(12), server_default="unreviewed")

    chapter_ref: Mapped[Chapter] = relationship(back_populates="verses")
    texts: Mapped[list[VerseText]] = relationship(back_populates="verse")


class VerseAlias(Base):
    """References in other numbering editions, e.g. ('edition-701', '13.2') -> '13.1'."""

    __tablename__ = "verse_alias"

    edition: Mapped[str] = mapped_column(String(40), primary_key=True)
    ref: Mapped[str] = mapped_column(String(8), primary_key=True)
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"))


class VerseText(Base):
    __tablename__ = "verse_text"
    __table_args__ = (
        check_in("kind", "kind", VERSE_TEXT_KINDS),
        check_in("review_status", "review_status", REVIEW_STATUSES),
        UniqueConstraint("verse_id", "source_id", "kind", "language"),
        Index("ix_verse_text_lookup", "verse_id", "kind", "language"),
    )

    # Deterministic UUIDv5 from the content pipeline: the same row has the
    # same id in Postgres and in the mobile pack, across content releases.
    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"))
    source_id: Mapped[str] = mapped_column(ForeignKey("source.id"))
    kind: Mapped[str] = mapped_column(String(20))
    language: Mapped[str] = mapped_column(String(20))
    body: Mapped[str] = mapped_column(Text)
    review_status: Mapped[str] = mapped_column(String(12), server_default="unreviewed")
    reviewed_by: Mapped[str | None] = mapped_column(Text)
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = updated_at()

    verse: Mapped[Verse] = relationship(back_populates="texts")


class WordMeaning(Base):
    __tablename__ = "word_meaning"
    __table_args__ = (
        UniqueConstraint("verse_id", "source_id", "language", "position"),
        CheckConstraint("position >= 0", name="position_nonnegative"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"))
    source_id: Mapped[str] = mapped_column(ForeignKey("source.id"))
    position: Mapped[int] = mapped_column(SmallInteger)
    word_sa: Mapped[str] = mapped_column(Text)
    language: Mapped[str] = mapped_column(String(20))
    meaning: Mapped[str] = mapped_column(Text)


class Concept(Base):
    __tablename__ = "concept"

    id: Mapped[str] = mapped_column(String(60), primary_key=True)  # 'karma-yoga'
    term_sa: Mapped[str | None] = mapped_column(Text)


class ConceptText(Base):
    __tablename__ = "concept_text"

    concept_id: Mapped[str] = mapped_column(ForeignKey("concept.id"), primary_key=True)
    source_id: Mapped[str] = mapped_column(ForeignKey("source.id"), primary_key=True)
    language: Mapped[str] = mapped_column(String(20), primary_key=True)
    name: Mapped[str] = mapped_column(Text)
    definition: Mapped[str | None] = mapped_column(Text)


class VerseConcept(Base):
    __tablename__ = "verse_concept"

    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"), primary_key=True)
    concept_id: Mapped[str] = mapped_column(ForeignKey("concept.id"), primary_key=True)
    source_id: Mapped[str] = mapped_column(ForeignKey("source.id"), primary_key=True)
    weight: Mapped[float] = mapped_column(Float, server_default="1.0")


class VerseRelation(Base):
    __tablename__ = "verse_relation"
    __table_args__ = (
        check_in("relation", "relation", ("parallel", "elaborates", "contrasts", "continues")),
        CheckConstraint("from_verse <> to_verse", name="not_self"),
    )

    from_verse: Mapped[str] = mapped_column(ForeignKey("verse.id"), primary_key=True)
    to_verse: Mapped[str] = mapped_column(ForeignKey("verse.id"), primary_key=True)
    relation: Mapped[str] = mapped_column(String(20), primary_key=True)
    source_id: Mapped[str] = mapped_column(ForeignKey("source.id"))


class ContentRelease(Base):
    """One row per imported content build (gita.json content_hash)."""

    __tablename__ = "content_release"

    content_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    format: Mapped[str] = mapped_column(String(60))
    verse_count: Mapped[int] = mapped_column(Integer)
    imported_at: Mapped[datetime] = mapped_column(DateTime(timezone=True), server_default=func.now())
