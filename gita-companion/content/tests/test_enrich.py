import json
import sqlite3

import pytest

from gita_content.build import build_dataset
from gita_content.enrich import EnrichError, ai_source_id, load_ai_records
from gita_content.pack import write_pack

GOOD_VERSE = {
    "simple": "You have a right to act, but not to the fruits of action.",
    "deep": "Deep explanation.",
    "practical": "At work, give full effort and let go of anxiety about results.",
    "story": "A gardener waters the seed.",
    "child": "Do your homework well.",
    "word_meanings": [{"word": "karmaṇi", "meaning": "in action"}, {"word": "eva", "meaning": "only"}],
    "sanskrit_terms": [{"term": "karma", "meaning": "action"}],
    "uncertain": [],
}


def record(kind="verse", ref="2.47", language="en", provider="groq", model="llama-x", content=None, **kw):
    return {
        "key": f"{kind}:{ref}:{language}",
        "kind": kind,
        "ref": ref,
        "language": language,
        "prompt_version": "verse-explain-v1" if kind == "verse" else "chapter-overview-v1",
        "provider": provider,
        "model": model,
        "generated_at": "2026-10-01T00:00:00+00:00",
        "content": content or GOOD_VERSE,
        **kw,
    }


def write_jsonl(directory, *records, name="verse-explanations.jsonl"):
    directory.mkdir(exist_ok=True)
    with (directory / name).open("a", encoding="utf-8") as f:
        for r in records:
            f.write(json.dumps(r, ensure_ascii=False) + "\n")
    return directory


def build(raw_rows, canon, registry, no_errata, ai_dir):
    return build_dataset(raw_rows, canon, registry, no_errata, ai_dir=ai_dir)[0]


def test_editorial_overviews_cover_all_chapters(dataset):
    for c in dataset["chapters"]:
        kinds = {(t["kind"], t["language"]) for t in c["texts"]}
        assert {("summary", "en"), ("theme", "en")} <= kinds, c["number"]
        assert all(
            t["review_status"] == "unreviewed" for t in c["texts"] if t["kind"] in ("summary", "theme")
        )


def test_ai_verse_record_becomes_labelled_texts(raw_rows, canon, registry, no_errata, tmp_path):
    ds = build(raw_rows, canon, registry, no_errata, write_jsonl(tmp_path / "ai", record()))
    sid = ai_source_id("groq", "llama-x", "verse-explain-v1")
    src = next(s for s in ds["sources"] if s["id"] == sid)
    assert src["is_ai_generated"] and src["kind"] == "ai" and src["model_id"] == "llama-x"
    v = next(v for v in ds["verses"] if v["id"] == "2.47")
    kinds = {t["kind"] for t in v["texts"] if t["source_id"] == sid}
    assert kinds == {"simple", "deep", "practical", "story", "child", "sanskrit_terms"}
    assert all(t["review_status"] == "unreviewed" for t in v["texts"] if t["source_id"] == sid)
    assert [w["word"] for w in v["word_meanings"]] == ["karmaṇi", "eva"]


def test_latest_record_wins(tmp_path):
    d = write_jsonl(tmp_path, record(model="old"), record(model="new"))
    assert [r["model"] for r in load_ai_records(d)] == ["new"]


def test_unknown_provider_is_rejected(raw_rows, canon, registry, no_errata, tmp_path):
    with pytest.raises(EnrichError, match="not allowed"):
        build(
            raw_rows, canon, registry, no_errata, write_jsonl(tmp_path / "ai", record(provider="shady-api"))
        )


def test_unknown_verse_and_malformed_records_are_rejected(raw_rows, canon, registry, no_errata, tmp_path):
    with pytest.raises(ValueError, match=r"unknown verse 2\.73"):
        build(raw_rows, canon, registry, no_errata, write_jsonl(tmp_path / "a", record(ref="2.73")))
    (tmp_path / "b").mkdir()
    (tmp_path / "b" / "x.jsonl").write_text('{"kind": "verse"}\n')
    with pytest.raises(EnrichError, match="malformed"):
        load_ai_records(tmp_path / "b")


def test_ai_chapter_overview(raw_rows, canon, registry, no_errata, tmp_path):
    rec = record(kind="chapter", ref="2", language="te", content={"summary": "సారాంశం", "theme": "విషయం"})
    ds = build(
        raw_rows,
        canon,
        registry,
        no_errata,
        write_jsonl(tmp_path / "ai", rec, name="chapter-overviews.jsonl"),
    )
    texts = next(c for c in ds["chapters"] if c["number"] == 2)["texts"]
    assert {(t["kind"], t["language"]) for t in texts} >= {
        ("summary", "te"),
        ("theme", "te"),
        ("summary", "en"),
    }


def test_pack_v2_has_word_meanings_and_searchable_explanations(
    raw_rows, canon, registry, no_errata, tmp_path
):
    ds = build(raw_rows, canon, registry, no_errata, write_jsonl(tmp_path / "ai", record()))
    db = sqlite3.connect(write_pack(ds, tmp_path / "p.sqlite"))
    assert db.execute("select count(*) from word_meaning where verse_id = '2.47'").fetchone()[0] == 2
    hits = db.execute("select verse_id from verse_fts where explanation match 'anxiety'").fetchall()
    assert hits == [("2.47",)]
    with pytest.raises(sqlite3.IntegrityError):
        db.execute(
            "insert into source (id, kind, title, author, language, license, is_ai_generated)"
            " values ('x', 'ai', 't', 'a', 'en', 'l', 1)"
        )
