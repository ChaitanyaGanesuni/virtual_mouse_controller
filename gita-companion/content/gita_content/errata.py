"""Apply the documented Sanskrit errata (corrections/sanskrit-errata.yaml)."""

from __future__ import annotations

from collections import Counter
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from .devanagari import SPEAKER_LINES, ParsedVerse, strict_key

ERRATA_PATH = Path(__file__).resolve().parent.parent / "corrections" / "sanskrit-errata.yaml"


class ErrataError(ValueError):
    pass


@dataclass
class Errata:
    review: str
    errata: list[dict]
    variants: dict[str, dict] = field(default_factory=dict)
    verifier_errors: dict[str, dict] = field(default_factory=dict)
    equivalent: dict[str, dict] = field(default_factory=dict)

    @classmethod
    def load(cls, path: Path = ERRATA_PATH) -> Errata:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        return cls(
            review=data.get("review", "pending"),
            errata=data.get("errata", []),
            variants={v["verse"]: v for v in data.get("variants", [])},
            verifier_errors={v["verse"]: v for v in data.get("verifier_errors", [])},
            equivalent={v["verse"]: v for v in data.get("equivalent", [])},
        )

    def corrected_verse_ids(self) -> set[str]:
        ids = set()
        for e in self.errata:
            ids.update(e["verses"] if e.get("kind") == "restructure" else [e["verse"]])
        return ids


def _letters(v: ParsedVerse) -> Counter:
    parts = ([v.speaker_line] if v.speaker_line else []) + v.lines
    return Counter(strict_key("".join(parts)))


def apply_errata(verses: dict[str, ParsedVerse], errata: Errata) -> dict[str, list[str]]:
    """Mutates `verses` in place. Returns {verse_id: [applied correction reasons]}."""
    applied: dict[str, list[str]] = {}
    for e in errata.errata:
        kind = e.get("kind", "replace")
        if kind == "replace":
            vid = e["verse"]
            if vid not in verses:
                raise ErrataError(f"erratum for unknown verse {vid}")
            v = verses[vid]
            hits = [i for i, ln in enumerate(v.lines) if e["find"] in ln]
            total = sum(ln.count(e["find"]) for ln in v.lines)
            if total != 1:
                raise ErrataError(f"{vid}: expected exactly one occurrence of {e['find']!r}, found {total}")
            i = hits[0]
            v.lines[i] = v.lines[i].replace(e["find"], e["replace"])
            applied.setdefault(vid, []).append(e["reason"])
        elif kind == "restructure":
            ids = e["verses"]
            if set(e["result"]) != set(ids):
                raise ErrataError(f"restructure {ids}: result must cover exactly {ids}")
            before = sum((_letters(verses[i]) for i in ids), Counter())
            new = {
                i: ParsedVerse(speaker=r["speaker"], lines=list(r["lines"])) for i, r in e["result"].items()
            }
            for v in new.values():
                if v.speaker is not None and v.speaker not in SPEAKER_LINES:
                    raise ErrataError(f"restructure {ids}: unknown speaker {v.speaker!r}")
                v.inner_speakers = [k for ln in v.lines for k, s in SPEAKER_LINES.items() if ln == s]
            after = sum((_letters(v) for v in new.values()), Counter())
            if before != after:
                diff = (before - after) + (after - before)
                raise ErrataError(f"restructure {ids} changes the text, not just its layout: {dict(diff)}")
            for i, v in new.items():
                v.fixes = verses[i].fixes
                verses[i] = v
                applied.setdefault(i, []).append(" ".join(e["reason"].split()))
        else:
            raise ErrataError(f"unknown erratum kind {kind!r}")
    return applied
