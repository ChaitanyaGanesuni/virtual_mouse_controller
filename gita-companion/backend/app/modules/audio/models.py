"""Audio assets (content-addressed cache) and long-form playback manifests.

audio_hash = sha256(normalized text | language | provider | provider_version
                    | voice | synthesis_rate)
Playback speed is applied by the player and is deliberately NOT part of the
hash; only synthesis-level rate (e.g. the slow recitation variant) is.
"""

from __future__ import annotations

from datetime import datetime

from sqlalchemy import (
    BigInteger,
    CheckConstraint,
    Float,
    ForeignKey,
    Integer,
    SmallInteger,
    String,
    Text,
    UniqueConstraint,
)
from sqlalchemy.orm import Mapped, mapped_column

from app.core.db import Base, check_in, created_at

MANIFEST_SCOPES = ("verse", "chapter", "explanation", "recitation", "answer")


class AudioAsset(Base):
    __tablename__ = "audio_asset"
    __table_args__ = (
        CheckConstraint("audio_hash ~ '^[0-9a-f]{64}$'", name="hash_is_sha256"),
        CheckConstraint("synthesis_rate > 0", name="rate_positive"),
        CheckConstraint("duration_seconds IS NULL OR duration_seconds >= 0", name="duration_nonnegative"),
        check_in("origin", "origin", ("tts", "recording")),
    )

    audio_hash: Mapped[str] = mapped_column(String(64), primary_key=True)
    origin: Mapped[str] = mapped_column(String(12), server_default="tts")
    provider: Mapped[str] = mapped_column(String(60))
    provider_version: Mapped[str] = mapped_column(String(60))
    voice_id: Mapped[str] = mapped_column(String(120))
    language: Mapped[str] = mapped_column(String(20))
    synthesis_rate: Mapped[float] = mapped_column(Float, server_default="1.0")
    codec: Mapped[str] = mapped_column(String(20))  # 'opus', 'mp3', 'wav'
    storage_key: Mapped[str] = mapped_column(Text)
    duration_seconds: Mapped[float | None] = mapped_column(Float)
    byte_size: Mapped[int | None] = mapped_column(BigInteger)
    source_id: Mapped[str | None] = mapped_column(ForeignKey("source.id"))  # licence of voice/recording
    created_at: Mapped[datetime] = created_at()


class AudioManifest(Base):
    """An ordered playlist of chunks for one listenable unit (a verse, a
    chapter, an explanation ...). Versioned: regenerating text creates a new
    version so saved listening positions can be migrated or reset."""

    __tablename__ = "audio_manifest"
    __table_args__ = (
        check_in("scope", "scope", MANIFEST_SCOPES),
        CheckConstraint("version > 0", name="version_positive"),
    )

    id: Mapped[str] = mapped_column(String(120), primary_key=True)  # 'ch2-explanation-te-v3'
    scope: Mapped[str] = mapped_column(String(20))
    chapter: Mapped[int | None] = mapped_column(ForeignKey("chapter.number"))
    verse_id: Mapped[str | None] = mapped_column(ForeignKey("verse.id"))
    section: Mapped[str | None] = mapped_column(String(40))
    language: Mapped[str] = mapped_column(String(20))
    version: Mapped[int] = mapped_column(Integer, server_default="1")
    created_at: Mapped[datetime] = created_at()


class AudioChunk(Base):
    __tablename__ = "audio_chunk"
    __table_args__ = (
        UniqueConstraint("manifest_id", "seq"),
        CheckConstraint("seq >= 0", name="seq_nonnegative"),
        CheckConstraint("est_seconds > 0", name="est_positive"),
    )

    id: Mapped[str] = mapped_column(String(160), primary_key=True)  # '<manifest>/c0001'
    manifest_id: Mapped[str] = mapped_column(ForeignKey("audio_manifest.id", ondelete="CASCADE"))
    seq: Mapped[int] = mapped_column(SmallInteger)
    verse_id: Mapped[str | None] = mapped_column(ForeignKey("verse.id"))
    section: Mapped[str | None] = mapped_column(String(40))
    text: Mapped[str] = mapped_column(Text)
    # NULL until synthesized; filled when the asset exists.
    audio_hash: Mapped[str | None] = mapped_column(ForeignKey("audio_asset.audio_hash"))
    est_seconds: Mapped[float] = mapped_column(Float)
