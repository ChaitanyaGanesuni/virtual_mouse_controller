"""Besant (1922) translation: parsing the Wikisource snapshot, alignment with
the canonical Sanskrit, and the committed import file."""

import json
import re
from pathlib import Path

import pytest

from gita_content.sources import besant

ROOT = Path(__file__).resolve().parent.parent
SNAPSHOT = ROOT / "sources" / "besant-1922" / "wikisource-pages.jsonl"
COMMITTED = ROOT / "sources" / "besant-1922" / "besant-1922-en.jsonl"


@pytest.fixture(scope="module")
def verses():
    return besant.parse(besant.read_snapshot(SNAPSHOT))


def test_every_verse_is_found_once(verses):
    ids = [besant.canonical_id(v) for v in verses]
    assert len(ids) == 701 and len(set(ids)) == 701
    assert "13.0" in ids  # Besant's 13.1 (Arjuna's question) is our 13.0


def test_snapshot_records_wikisource_revisions():
    pages = besant.read_snapshot(SNAPSHOT)
    assert len(pages) == 288
    assert all(isinstance(p["revid"], int) and p["revid"] > 0 for p in pages)


def test_alignment_with_the_canonical_sanskrit(verses):
    dataset = json.loads((ROOT / "data" / "gita.json").read_text(encoding="utf-8"))
    assert besant.check_against(verses, {v["id"]: v["sanskrit"] for v in dataset["verses"]}) == []


def test_alignment_check_catches_a_shifted_verse(verses):
    dataset = json.loads((ROOT / "data" / "gita.json").read_text(encoding="utf-8"))
    sanskrit = {v["id"]: v["sanskrit"] for v in dataset["verses"]}
    sanskrit["2.47"], sanskrit["2.48"] = sanskrit["2.48"], sanskrit["2.47"]
    assert {vid for vid, _ in besant.check_against(verses, sanskrit)} == {"2.47", "2.48"}


def test_committed_import_file_is_reproducible(verses):
    assert besant.to_jsonl_canonical(verses) == COMMITTED.read_text(encoding="utf-8")


def test_known_verses(verses):
    by_id = {besant.canonical_id(v): v.text for v in verses}
    assert by_id["2.47"].startswith("Thy business is with the action only, never with its fruits")
    assert by_id["18.66"] == (
        "Abandoning all duties come unto Me alone for shelter; sorrow not, "
        "I will liberate thee from all sins."
    )
    assert by_id["13.0"].startswith("Matter and Spirit, even the Field and the Knower of the Field")


def test_text_is_clean(verses):
    for v in verses:
        assert not re.search(r"[{}|<>\[\]=\x00\x01]", v.text), (v.chapter, v.verse, v.text)
        assert not re.match(r"(Arjuna|Sanjaya|The Blessed Lord|Dhritarâshtra) said", v.text)
        assert "  " not in v.text and v.text == v.text.strip()


def test_words_split_across_pages_are_joined(verses):
    by_id = {besant.canonical_id(v): v.text for v in verses}
    assert "should not be grieved for" in by_id["2.11"]
    assert "with undivided heart" in by_id["9.30"]


def test_misprinted_markers_are_explicit(verses):
    # The book marks the English of 17.19 and 18.14 with the next number; only
    # these listed misprints are accepted.
    assert set(besant.MARKER_MISPRINTS) == {(17, 19), (18, 14)}
    by_id = {besant.canonical_id(v): v.text for v in verses}
    assert by_id["17.19"].startswith("That austerity done under a deluded understanding")
    assert by_id["18.14"].startswith("The body, the actor, the various organs")


def test_unexpected_marker_fails(verses):
    pages = besant.read_snapshot(SNAPSHOT)
    broken = [dict(p) for p in pages]
    for p in broken:
        if p["n"] == 45:
            p["text"] = p["text"].replace(
                "{{float right|{{larger|(47)}}}}", "{{float right|{{larger|(46)}}}}"
            )
    with pytest.raises(besant.BesantParseError):
        besant.parse(broken)
