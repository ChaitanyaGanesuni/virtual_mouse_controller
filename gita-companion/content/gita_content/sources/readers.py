from __future__ import annotations

import json
import re
from collections.abc import Iterator
from dataclasses import dataclass
from pathlib import Path


@dataclass(frozen=True)
class RawVerse:
    chapter: int
    verse: int
    text: str


def read_gita_json(verse_json: Path) -> Iterator[RawVerse]:
    """gita/gita `data/verse.json`. Only the Devanagari `text` field is read;
    the dataset's transliteration, word meanings and translations are ignored
    on purpose (unclear provenance, see sources.yaml)."""
    for row in json.loads(verse_json.read_text(encoding="utf-8")):
        yield RawVerse(int(row["chapter_number"]), int(row["verse_number"]), row["text"])


_SLOK_FILE_RE = re.compile(r"bhagavadgita_chapter_(\d+)_slok_(\d+)\.json$")


def read_vedicscriptures(slok_dir: Path) -> Iterator[RawVerse]:
    """vedicscriptures/bhagavad-gita-data `slok/*.json`. Only `slok` is read."""
    for path in sorted(slok_dir.glob("bhagavadgita_chapter_*_slok_*.json")):
        m = _SLOK_FILE_RE.search(path.name)
        if not m:
            continue
        row = json.loads(path.read_text(encoding="utf-8"))
        yield RawVerse(int(m.group(1)), int(m.group(2)), row["slok"])


def read_translation_jsonl(path: Path) -> Iterator[tuple[int, int, str]]:
    """Verse-aligned translation import format, one JSON object per line:
    {"chapter": 2, "verse": 47, "text": "..."}"""
    for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
        if not line.strip():
            continue
        try:
            row = json.loads(line)
            yield int(row["chapter"]), int(row["verse"]), str(row["text"])
        except (ValueError, KeyError, TypeError) as e:
            raise ValueError(f"{path}:{n}: invalid translation row: {e}") from e
