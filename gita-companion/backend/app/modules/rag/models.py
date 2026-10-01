"""Retrieval documents for RAG and semantic search (pgvector + full text)."""

from __future__ import annotations

import uuid
from datetime import datetime

from pgvector.sqlalchemy import Vector
from sqlalchemy import CheckConstraint, Computed, ForeignKey, Index, String, Text
from sqlalchemy.dialects.postgresql import JSONB, TSVECTOR, UUID
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, check_in, created_at

# BAAI bge-m3 dense vectors. Changing the embedding model to one with a
# different dimension is a migration plus a full re-index.
EMBEDDING_DIM = 1024

FACETS = ("sanskrit", "translation", "explanation", "word_meanings", "concepts", "commentary", "concept")


class EmbeddingDoc(Base):
    __tablename__ = "embedding_doc"
    __table_args__ = (
        check_in("facet", "facet", FACETS),
        CheckConstraint("verse_id IS NOT NULL OR concept_id IS NOT NULL", name="has_subject"),
        Index(
            "ix_embedding_doc_embedding_hnsw",
            "embedding",
            postgresql_using="hnsw",
            postgresql_ops={"embedding": "vector_cosine_ops"},
        ),
        Index("ix_embedding_doc_tsv", "tsv", postgresql_using="gin"),
        Index("ix_embedding_doc_metadata", "metadata", postgresql_using="gin"),
        Index("ix_embedding_doc_verse", "verse_id", "facet", "language"),
    )

    id: Mapped[uuid.UUID] = mapped_column(UUID(as_uuid=True), primary_key=True)
    verse_id: Mapped[str | None] = mapped_column(ForeignKey("verse.id"))
    concept_id: Mapped[str | None] = mapped_column(ForeignKey("concept.id"))
    facet: Mapped[str] = mapped_column(String(20))
    language: Mapped[str] = mapped_column(String(20))
    source_id: Mapped[str] = mapped_column(ForeignKey("source.id"))
    body: Mapped[str] = mapped_column(Text)
    # 'simple' config: no stemming, works for every script (Sanskrit, Telugu, IAST, English).
    tsv: Mapped[str] = mapped_column(TSVECTOR, Computed("to_tsvector('simple', body)", persisted=True))
    embedding: Mapped[list[float] | None] = mapped_column(Vector(EMBEDDING_DIM))
    embedding_model: Mapped[str | None] = mapped_column(String(120))
    metadata_: Mapped[dict] = mapped_column("metadata", JSONB, server_default="{}")
    created_at: Mapped[datetime] = created_at()
