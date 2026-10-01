"""Canonical chapter/verse table and verse-reference validation.

Everything that names a verse (content import, AI citations, deep links)
goes through `Canon.resolve()` so that a reference to a verse that does not
exist can never enter the system.
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from functools import cache
from pathlib import Path

import yaml

CANONICAL_DIR = Path(__file__).resolve().parent.parent / "canonical"

EDITION_STANDARD = "standard-700"
EDITION_701 = "edition-701"


@dataclass(frozen=True)
class Chapter:
    number: int
    name_sa: str
    title_en: str
    verse_count: int
    alt_names_sa: tuple[str, ...] = ()
    extra_verses: tuple[int, ...] = ()

    def verse_numbers(self) -> list[int]:
        """All stored verse numbers, including non-canonical extras (e.g. 13.0)."""
        return sorted({*self.extra_verses, *range(1, self.verse_count + 1)})


@dataclass(frozen=True)
class VerseRef:
    chapter: int
    verse: int

    @property
    def id(self) -> str:
        return f"{self.chapter}.{self.verse}"

    def __str__(self) -> str:
        return self.id


class InvalidVerseRef(ValueError):
    pass


_REF_RE = re.compile(r"^\s*(?:bg\s*)?(\d{1,2})\s*[.:\-,\s]\s*(\d{1,2})\s*$", re.IGNORECASE)


@dataclass
class Canon:
    chapters: dict[int, Chapter]
    total_verses: int
    _extra_ids: set[str] = field(default_factory=set)

    @classmethod
    def load(cls, path: Path | None = None) -> Canon:
        data = yaml.safe_load((path or CANONICAL_DIR / "chapters.yaml").read_text(encoding="utf-8"))
        chapters = {
            c["number"]: Chapter(
                number=c["number"],
                name_sa=c["name_sa"],
                title_en=c["title_en"],
                verse_count=c["verse_count"],
                alt_names_sa=tuple(c.get("alt_names_sa", ())),
                extra_verses=tuple(c.get("extra_verses", ())),
            )
            for c in data["chapters"]
        }
        canon = cls(chapters=chapters, total_verses=data["total_verses"])
        canon._check_self()
        return canon

    def _check_self(self) -> None:
        if sorted(self.chapters) != list(range(1, 19)):
            raise ValueError("canonical table must contain chapters 1..18 exactly")
        counted = sum(c.verse_count for c in self.chapters.values())
        if counted != self.total_verses:
            raise ValueError(f"chapter verse counts sum to {counted}, expected {self.total_verses}")
        for c in self.chapters.values():
            for x in c.extra_verses:
                if 1 <= x <= c.verse_count:
                    raise ValueError(f"extra verse {c.number}.{x} collides with a canonical verse")
                self._extra_ids.add(f"{c.number}.{x}")

    def is_canonical(self, ref: VerseRef) -> bool:
        return ref.id not in self._extra_ids

    def all_refs(self, include_extra: bool = True) -> list[VerseRef]:
        refs = []
        for c in self.chapters.values():
            for v in c.verse_numbers():
                ref = VerseRef(c.number, v)
                if include_extra or self.is_canonical(ref):
                    refs.append(ref)
        return refs

    def exists(self, chapter: int, verse: int) -> bool:
        c = self.chapters.get(chapter)
        return c is not None and verse in c.verse_numbers()

    def resolve(self, chapter: int, verse: int, edition: str = EDITION_STANDARD) -> VerseRef:
        """Map a (chapter, verse) in the given edition's numbering to our verse id."""
        if edition == EDITION_701 and chapter == 13:
            verse -= 1  # 701-numbering 13.1 is our 13.0, 13.2 is our 13.1, ...
        elif edition not in (EDITION_STANDARD, EDITION_701):
            raise InvalidVerseRef(f"unknown edition {edition!r}")
        if not self.exists(chapter, verse):
            raise InvalidVerseRef(f"Bhagavad Gita has no verse {chapter}.{verse} ({edition})")
        return VerseRef(chapter, verse)

    def parse(self, text: str, edition: str = EDITION_STANDARD) -> VerseRef:
        """Parse references like '2.47', 'BG 2:47', '2-47'."""
        m = _REF_RE.match(text)
        if not m:
            raise InvalidVerseRef(f"not a verse reference: {text!r}")
        return self.resolve(int(m.group(1)), int(m.group(2)), edition)


@cache
def default_canon() -> Canon:
    return Canon.load()
