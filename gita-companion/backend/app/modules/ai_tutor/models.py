"""AI teacher conversations, validated citations and the answer cache."""

from __future__ import annotations

import uuid
from datetime import datetime

from sqlalchemy import Boolean, CheckConstraint, DateTime, ForeignKey, Index, Integer, String, Text
from sqlalchemy.dialects.postgresql import JSONB
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, check_in, created_at, deleted_at, updated_at, uuid_pk

EXPLANATION_MODES = ("simple", "deep", "practical", "story", "child", "sanskrit_terms", "free")


class AIConversation(Base):
    __tablename__ = "ai_conversation"
    __table_args__ = (
        check_in("mode", "mode", EXPLANATION_MODES),
        Index("ix_ai_conversation_user_updated", "user_id", "updated_at"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    user_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("app_user.id", ondelete="CASCADE"))
    title: Mapped[str | None] = mapped_column(Text)
    # Conversations started from the verse screen keep that verse as context.
    pinned_verse_id: Mapped[str | None] = mapped_column(ForeignKey("verse.id"))
    mode: Mapped[str] = mapped_column(String(20), server_default="free")
    language: Mapped[str] = mapped_column(String(20), server_default="en")
    summary: Mapped[str | None] = mapped_column(Text)  # rolling summary for long chats
    created_at: Mapped[datetime] = created_at()
    updated_at: Mapped[datetime] = updated_at()
    deleted_at: Mapped[datetime | None] = deleted_at()


class AIMessage(Base):
    __tablename__ = "ai_message"
    __table_args__ = (
        check_in("role", "role", ("user", "assistant", "system")),
        CheckConstraint(
            "role <> 'assistant' OR (model_id IS NOT NULL AND provider IS NOT NULL)",
            name="assistant_has_model",
        ),
        Index("ix_ai_message_conversation", "conversation_id", "created_at"),
    )

    id: Mapped[uuid.UUID] = uuid_pk()
    conversation_id: Mapped[uuid.UUID] = mapped_column(ForeignKey("ai_conversation.id", ondelete="CASCADE"))
    role: Mapped[str] = mapped_column(String(10))
    content: Mapped[str] = mapped_column(Text)
    mode: Mapped[str | None] = mapped_column(String(20))
    provider: Mapped[str | None] = mapped_column(String(40))
    model_id: Mapped[str | None] = mapped_column(String(120))
    prompt_version: Mapped[str | None] = mapped_column(String(40))
    tokens_in: Mapped[int | None] = mapped_column(Integer)
    tokens_out: Mapped[int | None] = mapped_column(Integer)
    # Points the model said it is unsure about; shown to the user.
    uncertain_points: Mapped[list] = mapped_column(JSONB, server_default="[]")
    # confidence, validation flags, retrieval methods, support note.
    meta: Mapped[dict] = mapped_column(JSONB, server_default="{}")
    created_at: Mapped[datetime] = created_at()


class AICitation(Base):
    """A verse cited by an assistant message. `validated` = the reference
    exists in the canonical table AND was among the retrieved passages."""

    __tablename__ = "ai_citation"

    message_id: Mapped[uuid.UUID] = mapped_column(
        ForeignKey("ai_message.id", ondelete="CASCADE"), primary_key=True
    )
    verse_id: Mapped[str] = mapped_column(ForeignKey("verse.id"), primary_key=True)
    source_id: Mapped[str | None] = mapped_column(ForeignKey("source.id"))
    validated: Mapped[bool] = mapped_column(Boolean)


class AIAnswerCache(Base):
    """Explanation / answer cache.
    cache_key = sha256(verse_id | mode | language | normalized question | prompt_version).
    The model that produced the answer is stored in model_id; any approved
    model may serve a cached answer."""

    __tablename__ = "ai_answer_cache"
    __table_args__ = (
        CheckConstraint("cache_key ~ '^[0-9a-f]{64}$'", name="key_is_sha256"),
        CheckConstraint("hit_count >= 0", name="hits_nonnegative"),
    )

    cache_key: Mapped[str] = mapped_column(String(64), primary_key=True)
    verse_id: Mapped[str | None] = mapped_column(ForeignKey("verse.id"), index=True)
    mode: Mapped[str] = mapped_column(String(20))
    language: Mapped[str] = mapped_column(String(20))
    prompt_version: Mapped[str] = mapped_column(String(40))
    model_id: Mapped[str] = mapped_column(String(120))
    question: Mapped[str | None] = mapped_column(Text)
    answer: Mapped[dict] = mapped_column(JSONB)
    hit_count: Mapped[int] = mapped_column(Integer, server_default="0")
    created_at: Mapped[datetime] = created_at()
    expires_at: Mapped[datetime | None] = mapped_column(DateTime(timezone=True))
