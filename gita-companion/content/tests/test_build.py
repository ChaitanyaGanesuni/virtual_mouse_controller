import json
import sqlite3

import pytest

from gita_content.build import BuildError, build_dataset, content_hash, text_id
from gita_content.devanagari import parse_verse
from gita_content.errata import Errata, ErrataError, apply_errata
from gita_content.pack import write_pack
from gita_content.registry import Registry, RegistryError
from gita_content.romanize import loose
from gita_content.sources.readers import RawVerse

# --- invariants of the committed dataset -------------------------------------


def test_dataset_matches_canon(dataset, canon):
    ids = [v["id"] for v in dataset["verses"]]
    assert ids == [r.id for r in canon.all_refs()]
    assert sum(v["is_canonical"] for v in dataset["verses"]) == 700
    assert [v["id"] for v in dataset["verses"] if not v["is_canonical"]] == ["13.0"]


def test_dataset_hash_is_reproducible(dataset):
    body = {k: v for k, v in dataset.items() if k not in ("format", "content_hash")}
    assert content_hash(body) == dataset["content_hash"]


def test_every_verse_is_well_formed(dataset):
    for v in dataset["verses"]:
        lines = v["sanskrit"].split("\n")
        assert lines[-1].endswith(" ॥"), v["id"]
        assert not any(ch.isdigit() for ch in v["sanskrit"]), v["id"]
        assert "़" not in v["sanskrit"] and "्ि" not in v["sanskrit"], v["id"]
        langs = {(t["kind"], t["language"]) for t in v["texts"]}
        assert {("transliteration", "sa-Latn"), ("transliteration", "sa-Telu")} <= langs


def test_every_text_has_a_registered_shippable_source(dataset, registry):
    shipped = {s["id"] for s in dataset["sources"]}
    used = {v["source_id"] for v in dataset["verses"]}
    used |= {t["source_id"] for v in dataset["verses"] for t in v["texts"]}
    used |= {t["source_id"] for c in dataset["chapters"] for t in c["texts"]}
    assert used <= shipped
    for sid in used:
        registry.shippable(sid)


def test_ai_drafted_text_is_flagged(dataset):
    sources = {s["id"]: s for s in dataset["sources"]}
    assert sources["gita-companion-editorial"]["is_ai_generated"] is True
    assert sources["bg-sanskrit-gita-json"]["is_ai_generated"] is False


def test_corrected_verses_await_review(dataset):
    corrected = {v["id"]: v for v in dataset["verses"] if v["corrections"]}
    assert {"1.20", "1.21", "1.28", "16.20"} <= corrected.keys()
    assert all(v["review_status"] == "pending" for v in corrected.values())
    assert corrected["16.20"]["sanskrit"].startswith("आसुरीं")


def test_speakers(dataset):
    by_id = {v["id"]: v for v in dataset["verses"]}
    assert by_id["1.1"]["speaker"] == "dhritarashtra"
    assert by_id["2.11"]["speaker"] == "krishna"
    assert by_id["13.0"]["speaker"] == "arjuna"
    assert by_id["1.21"]["speaker"] == "arjuna"
    assert by_id["1.20"]["speaker"] is None
    assert "अर्जुन उवाच" in by_id["1.28"]["sanskrit"]


def test_aliases_cover_chapter_13(dataset):
    aliases = {(a["edition"], a["ref"]): a["verse_id"] for a in dataset["aliases"]}
    assert aliases[("edition-701", "13.1")] == "13.0"
    assert aliases[("edition-701", "13.35")] == "13.34"
    assert len(aliases) == 35


def test_text_ids_are_deterministic():
    assert text_id("2.47", "translation", "en", "x") == text_id("2.47", "translation", "en", "x")
    assert text_id("2.47", "translation", "en", "x") != text_id("2.48", "translation", "en", "x")


# --- building from raw rows ------------------------------------------------


def test_build_from_raw_reproduces_text(raw_rows, canon, registry, no_errata, dataset):
    built, _ = build_dataset(raw_rows, canon, registry, no_errata)
    assert [v["sanskrit"] for v in built["verses"]] == [v["sanskrit"] for v in dataset["verses"]]


def test_build_rejects_missing_verse(raw_rows, canon, registry, no_errata):
    with pytest.raises(BuildError, match="missing"):
        build_dataset(raw_rows[:-1], canon, registry, no_errata)


def test_build_rejects_duplicate_verse(raw_rows, canon, registry, no_errata):
    with pytest.raises(BuildError, match="duplicate"):
        build_dataset([*raw_rows, raw_rows[0]], canon, registry, no_errata)


def test_unexplained_difference_fails_the_build(raw_rows, canon, registry, no_errata):
    verify = list(raw_rows)
    i = next(i for i, r in enumerate(verify) if (r.chapter, r.verse) == (2, 47))
    verify[i] = RawVerse(2, 47, verify[i].text.replace("फलेषु", "फलैषु"))
    with pytest.raises(BuildError, match=r"2\.47"):
        build_dataset(raw_rows, canon, registry, no_errata, verify_rows=verify)


def test_identical_verification_passes(raw_rows, canon, registry, no_errata):
    _, report = build_dataset(raw_rows, canon, registry, no_errata, verify_rows=raw_rows)
    assert len(report.identical) == 701 and not report.unexplained


def test_translation_import(raw_rows, canon, registry, no_errata, tmp_path):
    reg = Registry(dict(registry.sources))
    path = tmp_path / "t.jsonl"
    path.write_text(
        json.dumps({"chapter": 2, "verse": 47, "text": "  Thy right is to work only.  "})
        + "\n"
        + json.dumps({"chapter": 13, "verse": 34, "text": "Last verse of thirteen."})
        + "\n",
        encoding="utf-8",
    )
    built, _ = build_dataset(
        raw_rows, canon, reg, no_errata, translations=[("gita-companion-editorial", path)]
    )
    v = next(v for v in built["verses"] if v["id"] == "2.47")
    t = [t for t in v["texts"] if t["kind"] == "translation"]
    assert t[0]["body"] == "Thy right is to work only."


@pytest.mark.parametrize(
    "row,error",
    [
        ({"chapter": 2, "verse": 73, "text": "x"}, "no verse 2.73"),
        ({"chapter": 2, "verse": 47, "text": "  "}, "empty"),
    ],
)
def test_translation_import_rejects_bad_rows(raw_rows, canon, registry, no_errata, tmp_path, row, error):
    path = tmp_path / "t.jsonl"
    path.write_text(json.dumps(row) + "\n", encoding="utf-8")
    with pytest.raises(ValueError, match=error):
        build_dataset(raw_rows, canon, registry, no_errata, translations=[("gita-companion-editorial", path)])


def test_unregistered_or_verify_only_sources_cannot_ship(registry):
    with pytest.raises(RegistryError, match="not in the licence register"):
        registry.shippable("prabhupada-bbt")
    with pytest.raises(RegistryError, match="verify-only"):
        registry.shippable("bg-sanskrit-vedicscriptures")
    with pytest.raises(RegistryError, match="planned"):
        registry.shippable("besant-1922-en")


# --- errata ------------------------------------------------------------------


def _replace(find):
    return Errata("pending", [{"verse": "1.1", "find": find, "replace": "x", "reason": "r"}])


def test_erratum_must_match_exactly_once():
    with pytest.raises(ErrataError, match="found 0"):
        apply_errata({"1.1": parse_verse("क ख ग ।।1.1।।")}, _replace("घ"))
    with pytest.raises(ErrataError, match="found 2"):
        apply_errata({"1.1": parse_verse("क क ग ।।1.1।।")}, _replace("क"))
    with pytest.raises(ErrataError, match="unknown verse"):
        apply_errata({}, _replace("क"))


def test_restructure_may_move_but_not_change_text():
    def verses():
        return {"1.1": parse_verse("क ख।ग घ।।1.1।।"), "1.2": parse_verse("ङ च।।1.2।।")}

    move = {
        "kind": "restructure",
        "verses": ["1.1", "1.2"],
        "reason": "r",
        "result": {
            "1.1": {"speaker": None, "lines": ["क ख ॥"]},
            "1.2": {"speaker": None, "lines": ["ग घ ।", "ङ च ॥"]},
        },
    }
    vs = verses()
    apply_errata(vs, Errata("pending", [move]))
    assert vs["1.2"].lines == ["ग घ ।", "ङ च ॥"]

    move["result"]["1.2"]["lines"] = ["ग घ ।", "ङ छ ॥"]
    with pytest.raises(ErrataError, match="changes the text"):
        apply_errata(verses(), Errata("pending", [move]))


# --- SQLite pack ---------------------------------------------------------------


@pytest.fixture(scope="module")
def pack(dataset, tmp_path_factory):
    path = write_pack(dataset, tmp_path_factory.mktemp("pack") / "pack.sqlite")
    db = sqlite3.connect(path)
    yield db
    db.close()


def test_pack_contents(pack, dataset):
    assert pack.execute("select count(*) from verse").fetchone()[0] == 701
    assert pack.execute("select count(*) from verse_text").fetchone()[0] == 701 * 2
    meta = dict(pack.execute("select key, value from pack_meta"))
    assert meta["content_hash"] == dataset["content_hash"]
    assert pack.execute("PRAGMA foreign_key_check").fetchall() == []


def test_pack_rejects_bad_verse_id(pack):
    with pytest.raises(sqlite3.IntegrityError):
        pack.execute(
            "insert into verse values ('2.99', 2, 47, 1, null, 'x', 'bg-sanskrit-gita-json', 'unreviewed')"
        )


@pytest.mark.parametrize(
    "table,column,query,expected",
    [
        ("verse_fts", "roman_loose", loose("phaleshu"), "2.47"),
        ("verse_fts", "roman_loose", loose("dharmakshetre"), "1.1"),
        ("verse_fts", "iast", "phalesu", "2.47"),
        ("verse_fts", "sanskrit", "फलेषु", "2.47"),
        ("verse_fts", "telugu_script", "ఫలేషు", "2.47"),
        ("verse_fts_sub", "sanskrit", "धिकार", "2.47"),
        ("verse_fts_sub", "roman_loose", "vadhikara", "2.47"),
    ],
)
def test_pack_search(pack, table, column, query, expected):
    rows = pack.execute(f"select verse_id from {table} where {column} match ?", (f'"{query}"',)).fetchall()
    assert expected in [r[0] for r in rows]


def test_pack_manifest(dataset):
    from gita_content.pack import PACK_SCHEMA_VERSION, pack_manifest

    m = pack_manifest(dataset)
    assert m == {
        "pack_schema_version": PACK_SCHEMA_VERSION,
        "content_format": "gita-companion-content/1",
        "content_hash": dataset["content_hash"],
        "verse_count": 701,
    }
