"""Server-side TTS provider abstraction (mirrors the app's TtsProvider).

Used by batch jobs that pre-generate audio (Sanskrit recitation, explanation
audio) and, later, by the API for on-demand synthesis. Adding an engine
means implementing this protocol; nothing else changes.
"""

from __future__ import annotations

import io
import wave
from dataclasses import dataclass, field
from typing import Protocol, runtime_checkable


@dataclass(frozen=True)
class Voice:
    id: str
    language: str  # 'sa', 'te', 'en', ...
    name: str
    gender: str | None = None
    description: str = ""


@dataclass(frozen=True)
class Capabilities:
    languages: frozenset[str]
    native_sanskrit: bool
    streaming: bool
    local: bool
    max_chars: int
    needs_gpu: bool
    license: str


@dataclass(frozen=True)
class SynthesisResult:
    wav: bytes
    sample_rate: int
    seconds: float
    meta: dict = field(default_factory=dict)


@runtime_checkable
class TTSProvider(Protocol):
    id: str
    version: str

    def capabilities(self) -> Capabilities: ...

    def voices(self, language: str | None = None) -> list[Voice]: ...

    def synthesize(self, text: str, voice: Voice, *, rate: float = 1.0) -> SynthesisResult: ...


def wav_bytes(samples, sample_rate: int) -> bytes:
    """16-bit mono PCM WAV from float samples in [-1, 1] (list or numpy array)."""
    buf = io.BytesIO()
    with wave.open(buf, "wb") as w:
        w.setnchannels(1)
        w.setsampwidth(2)
        w.setframerate(sample_rate)
        frames = bytearray()
        for s in samples:
            v = max(-1.0, min(1.0, float(s)))
            frames += int(v * 32767).to_bytes(2, "little", signed=True)
        w.writeframes(bytes(frames))
    return buf.getvalue()


def wav_seconds(data: bytes) -> float:
    with wave.open(io.BytesIO(data), "rb") as w:
        return w.getnframes() / float(w.getframerate())
