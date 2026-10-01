"""Build the canonical content set from raw sources.

raw source -> parse/normalise -> renumber -> errata -> validate
           -> cross-check against a second transcription
           -> transliterate -> canonical JSON (+ report)
"""

from __future__ import annotations

import hashlib
import json
import uuid
from dataclasses import dataclass, field
from pathlib import Path

from .canon import EDITION_701, Canon, VerseRef
from .devanagari import SPEAKER_LINES, ParsedVerse, orthographic_key, parse_verse, strict_key
from .enrich import (
    AI_DIR,
    EDITORIAL_DIR,
    ai_source_row,
    load_ai_records,
    load_editorial_overviews,
    verse_ai_texts,
)
from .errata import Errata, apply_errata
from .registry import Registry
from .sources.readers import RawVerse, read_translation_jsonl
from .transliterate import all_scripts, transliterate

CONTENT_FORMAT = "gita-companion-content/2"
SANSKRIT_SOURCE = "bg-sanskrit-gita-json"
VERIFY_SOURCE = "bg-sanskrit-vedicscriptures"
EDITORIAL_SOURCE = "gita-companion-editorial"
SCRIPT_SOURCES = {"sa-Latn": "gc-transliteration-iast", "sa-Telu": "gc-transliteration-telugu"}

# Namespace for deterministic ids: the same text row gets the same UUID in
# every build, in Postgres and in the mobile pack, so user highlights that
# reference a text row survive content updates.
ID_NAMESPACE = uuid.UUID("8f0b6a3e-4c1d-5e2f-9a7b-6c5d4e3f2a1b")

SPEAKER_NAMES_EN = {
    "dhritarashtra": "Dhṛtarāṣṭra",
    "sanjaya": "Sañjaya",
    "arjuna": "Arjuna",
    "krishna": "Śrī Bhagavān (Kṛṣṇa)",
}


def text_id(*parts: object) -> str:
    return str(uuid.uuid5(ID_NAMESPACE, "|".join(map(str, parts))))


class BuildError(ValueError):
    pass


@dataclass
class CrossCheck:
    identical: list[str] = field(default_factory=list)
    orthographic: list[str] = field(default_factory=list)
    equivalent: list[str] = field(default_factory=list)
    variants: list[str] = field(default_factory=list)
    verifier_errors: list[str] = field(default_factory=list)
    unexplained: list[tuple[str, str, str]] = field(default_factory=list)
    unparsable: list[tuple[str, str]] = field(default_factory=list)


def _renumber(raw: RawVerse, canon: Canon) -> VerseRef:
    # Both datasets use the 701-verse numbering (Arjuna's question = 13.1).
    return canon.resolve(raw.chapter, raw.verse, EDITION_701)


def parse_primary(rows: list[RawVerse], canon: Canon) -> tuple[dict[str, ParsedVerse], dict[str, int]]:
    verses: dict[str, ParsedVerse] = {}
    original_numbers: dict[str, int] = {}
    for raw in rows:
        ref = _renumber(raw, canon)
        if ref.id in verses:
            raise BuildError(f"duplicate verse {ref.id}")
        verses[ref.id] = parse_verse(raw.text)
        original_numbers[ref.id] = raw.verse
    expected = {r.id for r in canon.all_refs()}
    missing, extra = expected - verses.keys(), verses.keys() - expected
    if missing or extra:
        raise BuildError(f"verse set mismatch: missing={sorted(missing)} extra={sorted(extra)}")
    return verses, original_numbers


def cross_check(
    verses: dict[str, ParsedVerse], verify_rows: list[RawVerse], canon: Canon, errata: Errata
) -> CrossCheck:
    report = CrossCheck()
    other: dict[str, RawVerse] = {}
    for raw in verify_rows:
        if canon.exists(raw.chapter, raw.verse - (1 if raw.chapter == 13 else 0)):
            other[_renumber(raw, canon).id] = raw
    for vid, v in verses.items():
        if vid not in other:
            report.unparsable.append((vid, "missing in verification source"))
            continue
        try:
            o = parse_verse(other[vid].text, lenient=True)
        except ValueError as e:
            report.unparsable.append((vid, str(e)))
            continue

        def full(p: ParsedVerse) -> str:
            return "".join(([p.speaker_line] if p.speaker_line else []) + p.lines)

        mine, theirs = full(v), full(o)
        if strict_key(mine) == strict_key(theirs):
            report.identical.append(vid)
        elif orthographic_key(mine) == orthographic_key(theirs):
            report.orthographic.append(vid)
        elif vid in errata.equivalent:
            report.equivalent.append(vid)
        elif vid in errata.variants:
            report.variants.append(vid)
        elif vid in errata.verifier_errors:
            report.verifier_errors.append(vid)
        else:
            report.unexplained.append((vid, v.text, o.text))
    return report


def content_hash(payload: dict) -> str:
    blob = json.dumps(payload, ensure_ascii=False, sort_keys=True).encode("utf-8")
    return hashlib.sha256(blob).hexdigest()


def build_dataset(
    primary_rows: list[RawVerse],
    canon: Canon,
    registry: Registry,
    errata: Errata,
    verify_rows: list[RawVerse] | None = None,
    translations: list[tuple[str, Path]] | None = None,
    editorial_dir: Path = EDITORIAL_DIR,
    ai_dir: Path = AI_DIR,
) -> tuple[dict, CrossCheck | None]:
    for sid in (SANSKRIT_SOURCE, EDITORIAL_SOURCE, *SCRIPT_SOURCES.values()):
        registry.shippable(sid)

    verses, original_numbers = parse_primary(primary_rows, canon)
    corrections = apply_errata(verses, errata)

    report = None
    if verify_rows is not None:
        report = cross_check(verses, verify_rows, canon, errata)
        if report.unexplained:
            ids = ", ".join(vid for vid, _, _ in report.unexplained)
            raise BuildError(
                f"{len(report.unexplained)} verse(s) differ from the verification source and are "
                f"not explained in the errata file: {ids}"
            )
        stale = (set(errata.variants) | set(errata.verifier_errors) | set(errata.equivalent)) - {
            *report.variants,
            *report.verifier_errors,
            *report.equivalent,
        }
        if stale:
            raise BuildError(f"errata entries no longer match a difference: {sorted(stale)}")

    chapters = []
    for c in canon.chapters.values():
        chapters.append(
            {
                "number": c.number,
                "name_sa": c.name_sa,
                "verse_count": c.verse_count,
                "texts": [
                    {
                        "id": text_id("chapter", c.number, "name", tag, src),
                        "kind": "name",
                        "language": tag,
                        "source_id": src,
                        "body": transliterate(c.name_sa, tag),
                        "review_status": "unreviewed",
                    }
                    for tag, src in SCRIPT_SOURCES.items()
                ]
                + [
                    {
                        "id": text_id("chapter", c.number, "title", "en", EDITORIAL_SOURCE),
                        "kind": "title",
                        "language": "en",
                        "source_id": EDITORIAL_SOURCE,
                        "body": c.title_en,
                        "review_status": "unreviewed",
                    },
                ],
            }
        )

    # Editorial and AI-generated overviews (summary/theme) per chapter.
    ai_records = load_ai_records(ai_dir)
    ai_sources: dict[str, dict] = {}
    chapter_extra = [
        {**r, "review_status": "unreviewed"} for r in load_editorial_overviews(canon, editorial_dir)
    ]
    for rec in (r for r in ai_records if r["kind"] == "chapter"):
        row = ai_source_row(rec, registry)
        ai_sources[row["id"]] = row
        for kind in ("summary", "theme"):
            chapter_extra.append(
                {
                    "chapter": int(rec["ref"]),
                    "kind": kind,
                    "language": rec["language"],
                    "source_id": row["id"],
                    "body": rec["content"][kind],
                    "review_status": "unreviewed",
                }
            )
    by_chapter = {c["number"]: c for c in chapters}
    for r in chapter_extra:
        if r["source_id"] not in ai_sources:
            registry.shippable(r["source_id"])
        by_chapter[r["chapter"]]["texts"].append(
            {
                "id": text_id("chapter", r["chapter"], r["kind"], r["language"], r["source_id"]),
                **{k: r[k] for k in ("kind", "language", "source_id", "body", "review_status")},
            }
        )

    ai_verse: dict[str, tuple[list[dict], list[dict]]] = {}
    for rec in (r for r in ai_records if r["kind"] == "verse"):
        if not canon.exists(*map(int, rec["ref"].split("."))):
            raise BuildError(f"AI record for unknown verse {rec['ref']}")
        row = ai_source_row(rec, registry)
        ai_sources[row["id"]] = row
        texts, words = verse_ai_texts(rec, row["id"], text_id)
        prev = ai_verse.setdefault(rec["ref"], ([], []))
        prev[0].extend(texts)
        prev[1].extend(words)

    speakers = [
        {
            "id": key,
            "name_en": SPEAKER_NAMES_EN[key],
            **{f"line_{tag.replace('-', '_').lower()}": text for tag, text in all_scripts(line).items()},
        }
        for key, line in SPEAKER_LINES.items()
    ]

    translation_rows = _load_translations(translations or [], canon, registry)

    verse_rows = []
    for ref in canon.all_refs():
        v = verses[ref.id]
        sanskrit = v.text
        # Corrected verses stay "pending" until the errata are signed off.
        status = errata.review if ref.id in corrections else "unreviewed"
        # Transliteration is mechanical, so it is exactly as trustworthy as the
        # Devanagari it was generated from: it inherits that review status.
        texts = [
            {
                "id": text_id(ref.id, "transliteration", tag, src),
                "kind": "transliteration",
                "language": tag,
                "source_id": src,
                "body": transliterate(sanskrit, tag),
                "review_status": status,
            }
            for tag, src in SCRIPT_SOURCES.items()
        ]
        texts += translation_rows.get(ref.id, [])
        ai_texts, word_meanings = ai_verse.get(ref.id, ([], []))
        texts += ai_texts
        verse_rows.append(
            {
                "id": ref.id,
                "chapter": ref.chapter,
                "verse": ref.verse,
                "is_canonical": canon.is_canonical(ref),
                "speaker": v.speaker,
                "sanskrit": sanskrit,
                "source_id": SANSKRIT_SOURCE,
                "review_status": status,
                "corrections": corrections.get(ref.id, []),
                "encoding_repairs": v.fixes,
                "texts": texts,
                "word_meanings": word_meanings,
            }
        )

    aliases = []
    for ref in canon.all_refs():
        if ref.id in original_numbers and ref.chapter == 13:
            aliases.append(
                {"edition": EDITION_701, "ref": f"13.{original_numbers[ref.id]}", "verse_id": ref.id}
            )

    used = {
        SANSKRIT_SOURCE,
        EDITORIAL_SOURCE,
        *SCRIPT_SOURCES.values(),
        *(src for src, _ in (translations or [])),
    }
    body = {
        "numbering": "standard-700",
        "sources": [registry.sources[s].as_row() for s in sorted(used)]
        + [ai_sources[s] for s in sorted(ai_sources)],
        "chapters": chapters,
        "speakers": speakers,
        "verses": verse_rows,
        "aliases": aliases,
    }
    dataset = {"format": CONTENT_FORMAT, "content_hash": content_hash(body), **body}
    return dataset, report


def _load_translations(
    translations: list[tuple[str, Path]], canon: Canon, registry: Registry
) -> dict[str, list[dict]]:
    out: dict[str, list[dict]] = {}
    for source_id, path in translations:
        src = registry.shippable(source_id)
        seen: set[str] = set()
        for chapter, verse, text in read_translation_jsonl(path):
            ref = canon.resolve(chapter, verse)
            if ref.id in seen:
                raise BuildError(f"{source_id}: duplicate translation for {ref.id}")
            if not text.strip():
                raise BuildError(f"{source_id}: empty translation for {ref.id}")
            seen.add(ref.id)
            out.setdefault(ref.id, []).append(
                {
                    "id": text_id(ref.id, "translation", src.language, source_id),
                    "kind": "translation",
                    "language": src.language,
                    "source_id": source_id,
                    "body": " ".join(text.split()),
                    "review_status": "unreviewed",
                }
            )
    return out


def render_report(dataset: dict, report: CrossCheck | None, errata: Errata) -> str:
    verses = dataset["verses"]
    corrected = [v for v in verses if v["corrections"]]
    repaired = [v for v in verses if v["encoding_repairs"]]
    lines = [
        "# Sanskrit text: build and cross-check report",
        "",
        "Generated by `gita-content build`. Do not edit by hand.",
        "",
        f"- Content hash: `{dataset['content_hash']}`",
        f"- Verses: {len(verses)} ({sum(v['is_canonical'] for v in verses)} canonical + "
        f"{sum(not v['is_canonical'] for v in verses)} non-canonical, numbering `{dataset['numbering']}`)",
        f"- Verses with automatic legacy-encoding repairs: {len(repaired)}",
        f"- Verses with documented corrections (errata): {len(corrected)} "
        f"(review status: **{errata.review}**)",
        "",
    ]
    if report:
        lines += [
            "## Cross-check against the second transcription",
            "",
            "| Result | Verses |",
            "|---|---|",
            f"| Identical (ignoring spacing/punctuation) | {len(report.identical)} |",
            f"| Spelling conventions only (avagraha, anusvāra) | {len(report.orthographic)} |",
            f"| Equivalent spellings (listed in errata) | {len(report.equivalent)} |",
            f"| Variant readings, base kept (**needs human review**) | {len(report.variants)} |",
            f"| Verification source in error | {len(report.verifier_errors)} |",
            f"| Unexplained | {len(report.unexplained)} |",
            f"| Could not be compared | {len(report.unparsable)} |",
            "",
        ]
        if report.variants:
            lines += ["### Variant readings needing review", ""]
            for vid in report.variants:
                v = errata.variants[vid]
                lines.append(f"- **{vid}**: kept `{v['kept']}`; other editions: `{v['other']}`")
            lines.append("")
        if report.unparsable:
            lines += ["### Not compared", ""]
            lines += [f"- {vid}: {why}" for vid, why in report.unparsable]
            lines.append("")
    lines += ["## Corrections applied", ""]
    for v in corrected:
        for c in v["corrections"]:
            lines.append(f"- **{v['id']}**: {c}")
    lines += ["", "## Automatic legacy-encoding repairs", ""]
    for v in repaired:
        lines.append(f"- {v['id']}: {'; '.join(v['encoding_repairs'])}")
    lines.append("")
    return "\n".join(lines)
