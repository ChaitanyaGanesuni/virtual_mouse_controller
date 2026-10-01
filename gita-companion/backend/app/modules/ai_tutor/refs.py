"""Find Bhagavad Gita references in free text.

Used twice: to read explicit references in a question ("what does 2.47
mean?") and to check every reference an AI answer makes.
"""

from __future__ import annotations

import re
from dataclasses import dataclass

# "2.47", "BG 2:47", "(18.66)." – a trailing full stop must not hide a
# reference, but parts of longer numbers ("1.234", "10.5.3") are not
# references. Ranges: "2.47-48", "8.5–8.6".
_VERSE = re.compile(
    r"(?<!\d)(?<!\d\.)(\d{1,2})\s*[.:]\s*(\d{1,2})"
    r"(?:\s*[-–]\s*(?:(\d{1,2})\s*[.:]\s*)?(\d{1,2}))?(?!\d)(?!\.\d)"
)
# "chapter 2, verse 47", "chapter 2 verse 47", "అధ్యాయం 2, శ్లోకం 47"
_WORDY = re.compile(
    r"(?:chapter|ch\.?|అధ్యాయం|అధ్యాయము)\s*(\d{1,2})\s*,?\s*(?:verse|v\.?|శ్లోకం|శ్లోకము)\s*(\d{1,2})",
    re.IGNORECASE,
)
_CHAPTER = re.compile(r"(?:chapter|అధ్యాయం|అధ్యాయము)\s*(\d{1,2})(?!\s*[.:]\s*\d)", re.IGNORECASE)

MAX_RANGE = 10


@dataclass(frozen=True)
class Ref:
    chapter: int
    verse: int

    @property
    def id(self) -> str:
        return f"{self.chapter}.{self.verse}"


def verse_refs(text: str) -> list[Ref]:
    """Every verse reference in order of appearance, without duplicates.
    Numbers are returned as written; callers decide whether they exist."""
    found: list[tuple[int, Ref]] = []
    for m in _WORDY.finditer(text):
        found.append((m.start(), Ref(int(m.group(1)), int(m.group(2)))))
    for m in _VERSE.finditer(text):
        ch, v = int(m.group(1)), int(m.group(2))
        found.append((m.start(), Ref(ch, v)))
        if m.group(4):
            end_ch = int(m.group(3)) if m.group(3) else ch
            end_v = int(m.group(4))
            if end_ch == ch and v < end_v <= v + MAX_RANGE:
                found += [(m.start(), Ref(ch, x)) for x in range(v + 1, end_v + 1)]
            elif end_ch != ch:
                found.append((m.start(), Ref(end_ch, end_v)))
    out: list[Ref] = []
    for _, r in sorted(found, key=lambda t: t[0]):
        if r not in out:
            out.append(r)
    return out


def chapter_refs(text: str) -> list[int]:
    """Chapters mentioned on their own ("chapter 3"), not as part of a verse reference."""
    spans = [m.span() for m in _WORDY.finditer(text)]
    out: list[int] = []
    for m in _CHAPTER.finditer(text):
        if any(a <= m.start() < b for a, b in spans):
            continue
        n = int(m.group(1))
        if n not in out:
            out.append(n)
    return out
