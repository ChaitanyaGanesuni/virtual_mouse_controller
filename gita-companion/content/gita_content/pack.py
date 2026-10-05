"""Write the canonical dataset to the mobile SQLite content pack."""

from __future__ import annotations

import sqlite3
from datetime import UTC, datetime
from pathlib import Path

from .romanize import loose

SCHEMA_PATH = Path(__file__).resolve().parent.parent / "schema" / "content_pack.sql"
PACK_SCHEMA_VERSION = 3


def pack_manifest(dataset: dict) -> dict:
    """Small sidecar the app reads to decide whether its installed pack is current."""
    return {
        "pack_schema_version": PACK_SCHEMA_VERSION,
        "content_format": dataset["format"],
        "content_hash": dataset["content_hash"],
        "verse_count": len(dataset["verses"]),
    }


def write_pack(dataset: dict, out: Path, built_at: datetime | None = None) -> Path:
    out.parent.mkdir(parents=True, exist_ok=True)
    tmp = out.with_suffix(".tmp")
    tmp.unlink(missing_ok=True)
    db = sqlite3.connect(tmp)
    try:
        db.executescript(SCHEMA_PATH.read_text(encoding="utf-8"))
        _fill(db, dataset, built_at or datetime.now(UTC))
        db.commit()
        problems = db.execute("PRAGMA foreign_key_check").fetchall()
        if problems:
            raise ValueError(f"foreign key violations in pack: {problems[:5]}")
        if db.execute("PRAGMA integrity_check").fetchone()[0] != "ok":
            raise ValueError("pack failed integrity_check")
        db.execute("VACUUM")
    finally:
        db.close()
    tmp.replace(out)
    return out


def _fill(db: sqlite3.Connection, ds: dict, built_at: datetime) -> None:
    meta = {
        "pack_schema_version": str(PACK_SCHEMA_VERSION),
        "content_format": ds["format"],
        "content_hash": ds["content_hash"],
        "numbering": ds["numbering"],
        "built_at": built_at.isoformat(timespec="seconds"),
    }
    db.executemany("INSERT INTO pack_meta VALUES (?, ?)", meta.items())

    db.executemany(
        "INSERT INTO source VALUES (:id, :kind, :title, :author, :year, :language, :license,"
        " :license_note, :url, :retrieved_commit, :is_ai_generated, :model_id, :prompt_version)",
        ds["sources"],
    )
    for c in ds["chapters"]:
        db.execute("INSERT INTO chapter VALUES (?, ?, ?)", (c["number"], c["name_sa"], c["verse_count"]))
        db.executemany(
            "INSERT INTO chapter_text VALUES (:id, :chapter, :source_id, :kind, :language, :body,"
            " :review_status)",
            [{**t, "chapter": c["number"]} for t in c["texts"]],
        )
    db.executemany(
        "INSERT INTO speaker VALUES (:id, :name_en, :line_sa, :line_sa_latn, :line_sa_telu)",
        ds["speakers"],
    )
    for v in ds["verses"]:
        db.execute(
            "INSERT INTO verse VALUES (?, ?, ?, ?, ?, ?, ?, ?)",
            (
                v["id"],
                v["chapter"],
                v["verse"],
                int(v["is_canonical"]),
                v["speaker"],
                v["sanskrit"],
                v["source_id"],
                v["review_status"],
            ),
        )
        db.executemany(
            "INSERT INTO verse_text VALUES (:id, :verse_id, :source_id, :kind, :language, :body,"
            " :review_status)",
            [{**t, "verse_id": v["id"]} for t in v["texts"]],
        )
        db.executemany(
            "INSERT INTO word_meaning VALUES"
            " (:id, :verse_id, :source_id, :position, :word, :language, :meaning)",
            [{**w, "verse_id": v["id"]} for w in v.get("word_meanings", [])],
        )
        by_lang = {(t["kind"], t["language"]): t["body"] for t in v["texts"]}
        iast = by_lang.get(("transliteration", "sa-Latn"), "")
        telugu = by_lang.get(("transliteration", "sa-Telu"), "")
        translation = " ".join(t["body"] for t in v["texts"] if t["kind"] == "translation")
        explanation = " ".join(t["body"] for t in v["texts"] if t["kind"] in ("simple", "deep", "practical"))
        roman = loose(iast)
        db.execute(
            "INSERT INTO verse_fts VALUES (?, ?, ?, ?, ?, ?, ?)",
            (v["id"], v["sanskrit"], iast, roman, telugu, translation, explanation),
        )
        db.execute(
            "INSERT INTO verse_fts_sub VALUES (?, ?, ?, ?)",
            (v["id"], _no_space(v["sanskrit"]), roman.replace(" ", ""), _no_space(telugu)),
        )
    db.executemany("INSERT INTO verse_alias VALUES (:edition, :ref, :verse_id)", ds["aliases"])

    for c in ds.get("concepts", []):
        db.execute("INSERT INTO concept VALUES (?, ?)", (c["id"], c["term_sa"]))
        db.executemany(
            "INSERT INTO concept_text VALUES (?, ?, ?, ?, ?)",
            [
                (c["id"], c["source_id"], "en", c["names"]["en"], c["definition_en"]),
                (c["id"], c["source_id"], "te", c["names"]["te"], None),
            ],
        )
        strong = {(lang, k) for lang, keys in c["terms"].items() for k in keys}
        db.executemany(
            "INSERT INTO concept_term VALUES (?, ?, ?, ?)",
            [(c["id"], lang, key, 0) for lang, key in sorted(strong)]
            + [
                (c["id"], lang, key, 1)
                for lang, keys in c.get("weak_terms", {}).items()
                for key in keys
                if (lang, key) not in strong
            ],
        )
        db.executemany(
            "INSERT INTO verse_concept VALUES (?, ?, ?, ?)",
            [(vid, c["id"], c["source_id"], w) for vid, w in c["verses"]],
        )
    db.executemany(
        "INSERT INTO concept_related VALUES (?, ?)",
        [(c["id"], r) for c in ds.get("concepts", []) for r in c["related"]],
    )


def _no_space(text: str) -> str:
    # Substring search should work across word breaks inside a half-verse.
    return "\n".join("".join(line.split()) for line in text.splitlines())
