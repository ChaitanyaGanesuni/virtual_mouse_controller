"""Import a content build (content/data/gita.json) into Postgres.

Idempotent: re-importing the same or a newer build upserts every row by its
stable id, so it is safe to run on every deploy.

    python -m app.modules.content.seed ../content/data/gita.json
"""

from __future__ import annotations

import json
import sys
from pathlib import Path

from sqlalchemy import Engine, create_engine, delete
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.core.config import database_url
from app.modules.content.models import (
    Chapter,
    ChapterText,
    Concept,
    ConceptText,
    ContentRelease,
    Source,
    Speaker,
    Verse,
    VerseAlias,
    VerseConcept,
    VerseText,
    WordMeaning,
)

SUPPORTED_FORMATS = {"gita-companion-content/1", "gita-companion-content/2", "gita-companion-content/3"}


class ContentImportError(ValueError):
    pass


def _upsert(session: Session, model, rows: list[dict], keys: list[str]) -> None:
    if not rows:
        return
    stmt = insert(model).values(rows)
    updatable = {c: stmt.excluded[c] for c in rows[0] if c not in keys}
    stmt = (
        stmt.on_conflict_do_update(index_elements=keys, set_=updatable)
        if updatable
        else (stmt.on_conflict_do_nothing(index_elements=keys))
    )
    session.execute(stmt)


def import_dataset(session: Session, ds: dict) -> int:
    if ds.get("format") not in SUPPORTED_FORMATS:
        raise ContentImportError(f"unsupported content format {ds.get('format')!r}")

    _upsert(session, Source, ds["sources"], ["id"])
    _upsert(
        session,
        Chapter,
        [
            {"number": c["number"], "name_sa": c["name_sa"], "verse_count": c["verse_count"]}
            for c in ds["chapters"]
        ],
        ["number"],
    )
    _upsert(
        session,
        ChapterText,
        [
            {k: t[k] for k in ("id", "kind", "language", "source_id", "body", "review_status")}
            | {"chapter": c["number"]}
            for c in ds["chapters"]
            for t in c["texts"]
        ],
        ["id"],
    )
    _upsert(session, Speaker, ds["speakers"], ["id"])

    verse_cols = (
        "id",
        "chapter",
        "verse",
        "is_canonical",
        "speaker",
        "sanskrit",
        "source_id",
        "review_status",
    )
    verses = [{k: v[k] for k in verse_cols} for v in ds["verses"]]
    for i in range(0, len(verses), 200):
        _upsert(session, Verse, verses[i : i + 200], ["id"])

    texts = [
        {k: t[k] for k in ("id", "kind", "language", "source_id", "body", "review_status")}
        | {"verse_id": v["id"]}
        for v in ds["verses"]
        for t in v["texts"]
    ]
    for i in range(0, len(texts), 500):
        _upsert(session, VerseText, texts[i : i + 500], ["id"])

    words = [
        {
            "id": w["id"],
            "verse_id": v["id"],
            "source_id": w["source_id"],
            "position": w["position"],
            "word_sa": w["word"],
            "language": w["language"],
            "meaning": w["meaning"],
        }
        for v in ds["verses"]
        for w in v.get("word_meanings", [])
    ]
    for i in range(0, len(words), 500):
        _upsert(session, WordMeaning, words[i : i + 500], ["id"])

    _upsert(session, VerseAlias, ds["aliases"], ["edition", "ref"])
    _import_concepts(session, ds.get("concepts", []))
    _upsert(
        session,
        ContentRelease,
        [{"content_hash": ds["content_hash"], "format": ds["format"], "verse_count": len(ds["verses"])}],
        ["content_hash"],
    )
    return len(verses)


def _import_concepts(session: Session, rows: list[dict]) -> None:
    """Concept index (format 3). Links are replaced, not merged: a link that a
    newer build no longer makes must disappear."""
    if not rows:
        return
    _upsert(session, Concept, [{"id": c["id"], "term_sa": c["term_sa"]} for c in rows], ["id"])
    _upsert(
        session,
        ConceptText,
        [
            {
                "concept_id": c["id"],
                "source_id": c["source_id"],
                "language": lang,
                "name": c["names"][lang],
                "definition": c["definition_en"] if lang == "en" else None,
            }
            for c in rows
            for lang in ("en", "te")
        ],
        ["concept_id", "source_id", "language"],
    )
    sources = {c["source_id"] for c in rows}
    session.execute(delete(VerseConcept).where(VerseConcept.source_id.in_(sources)))
    links = [
        {"verse_id": vid, "concept_id": c["id"], "source_id": c["source_id"], "weight": w}
        for c in rows
        for vid, w in c["verses"]
    ]
    for i in range(0, len(links), 1000):
        session.execute(insert(VerseConcept).values(links[i : i + 1000]))


def main(argv: list[str] | None = None, engine: Engine | None = None) -> int:
    args = argv if argv is not None else sys.argv[1:]
    if len(args) != 1:
        print("usage: python -m app.modules.content.seed path/to/gita.json", file=sys.stderr)
        return 2
    ds = json.loads(Path(args[0]).read_text(encoding="utf-8"))
    engine = engine or create_engine(database_url())
    with Session(engine) as session, session.begin():
        n = import_dataset(session, ds)
    print(f"imported {n} verses (content hash {ds['content_hash'][:12]})")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
