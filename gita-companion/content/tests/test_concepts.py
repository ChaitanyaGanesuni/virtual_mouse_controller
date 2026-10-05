"""Concept index: lexicon validation, verse linking and query matching."""

import json
import re
from pathlib import Path

import pytest

from gita_content import concepts as cm
from gita_content.romanize import loose

ROOT = Path(__file__).resolve().parent.parent
VECTORS = json.loads((Path(__file__).parent / "query_vectors.json").read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def dataset():
    return json.loads((ROOT / "data" / "gita.json").read_text(encoding="utf-8"))


@pytest.fixture(scope="module")
def linked(dataset):
    iast = {
        v["id"]: next(t["body"] for t in v["texts"] if t["language"] == "sa-Latn") for v in dataset["verses"]
    }
    return cm.link_verses(cm.load_concepts(), iast), iast


def test_every_link_is_backed_by_the_verse_text(linked):
    concepts, iast = linked
    for c in concepts:
        assert c.verses, c.id
        for vid in c.verses:
            text = loose(iast[vid])
            assert any(cm._stem_hits(s, c.exclude, text) for s in (*c.stems, *c.weak)), (c.id, vid)


def test_dataset_concepts_match_the_lexicon(dataset, linked):
    concepts, _ = linked
    assert [c["id"] for c in dataset["concepts"]] == [c.id for c in concepts]
    for row, c in zip(dataset["concepts"], concepts, strict=True):
        assert dict((v, w) for v, w in row["verses"]) == c.verses
        assert max(w for _, w in row["verses"]) == 1.0


def test_exclusions_and_known_links(linked):
    concepts, _ = linked
    by_id = {c.id: c for c in concepts}
    assert "1.21" not in by_id["fear"].verses  # ubhayoḥ = "of both", not bhaya
    assert {"2.62", "2.63", "3.37", "16.21"} <= set(by_id["anger"].verses)
    assert {"4.7", "4.8"} <= set(by_id["incarnation"].verses)
    assert "2.43" not in by_id["incarnation"].verses  # janmakarmaphala is not "janma karma ca me"
    assert "1.2" not in by_id["worship"].verses  # upasaṅgamya = approaching


def test_lexicon_errors_are_reported(tmp_path):
    bad = tmp_path / "c.yaml"
    bad.write_text(
        "concepts:\n  - id: x\n    sa: x\n    en: {name: X, definition: d, terms: [x]}\n"
        "    te: {name: X, terms: [x]}\n    stems: [zzzzqq]\n    related: [nope]\n",
        encoding="utf-8",
    )
    with pytest.raises(cm.ConceptError, match="unknown related"):
        cm.load_concepts(bad)
    bad.write_text(bad.read_text().replace("    related: [nope]\n", ""), encoding="utf-8")
    with pytest.raises(cm.ConceptError, match="matches no verse"):
        cm.link_verses(cm.load_concepts(bad), {"1.1": "dharmaksetre kuruksetre"})


@pytest.mark.parametrize("case", VECTORS["normalize_en"], ids=lambda c: c["text"][:30])
def test_normalize_vectors(case):
    assert cm.normalize_en(case["text"]) == case["expect"]


@pytest.mark.parametrize("case", VECTORS["telugu_stem"], ids=lambda c: c["term"])
def test_telugu_stem_vectors(case):
    assert cm.telugu_stem(case["term"]) == case["expect"]


@pytest.mark.parametrize("case", VECTORS["tokens"], ids=lambda c: c["text"])
def test_token_vectors(case):
    assert cm.tokens(case["text"]) == case["expect"]


@pytest.mark.parametrize("case", VECTORS["match"], ids=lambda c: c["query"][:30])
def test_match_vectors(case):
    assert cm.match_concepts(case["query"], cm.load_concepts()) == case["expect"]


def test_terms_in_dataset_are_normalised(dataset):
    for c in dataset["concepts"]:
        for key in c["terms"]["en"]:
            assert key == key.lower() and not re.search(r"[^a-z ]", key), (c["id"], key)
        assert c["terms"]["te"], c["id"]
