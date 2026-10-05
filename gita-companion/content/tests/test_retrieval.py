"""Reference retriever and the golden-set evaluation."""

import json
from pathlib import Path

import pytest

from gita_content import evaluate as ev
from gita_content.concepts import load_concepts
from gita_content.retrieval import Retriever

ROOT = Path(__file__).resolve().parent.parent


@pytest.fixture(scope="module")
def retriever():
    dataset = json.loads((ROOT / "data" / "gita.json").read_text(encoding="utf-8"))
    return Retriever(dataset, load_concepts())


def top(retriever, q, k=8):
    return [h.verse_id for h in retriever.search(q, k=k)]


def test_explicit_references_come_first(retriever):
    assert top(retriever, "What does 18.66 say?")[0] == "18.66"
    assert top(retriever, "explain chapter 2, verse 47")[0] == "2.47"


def test_sanskrit_typed_in_roman_letters(retriever):
    assert top(retriever, "karmanye vadhikaraste")[0] == "2.47"
    assert "2.54" in top(retriever, "sthitaprajna", k=3)


def test_hits_explain_why(retriever):
    hit = retriever.search("how do I control anger")[0]
    assert "concept" in hit.channels and "anger" in hit.concepts


def test_telugu_questions(retriever):
    assert {"2.62", "2.63"} & set(top(retriever, "కోపాన్ని ఎలా నియంత్రించాలి?"))


def test_golden_set_is_valid(retriever):
    golden = ev.load_golden()
    assert len(golden) >= 80
    known = set(retriever.verse_ids)
    for g in golden:
        assert g["expect"] and set(g["expect"]) <= known, g["q"]
        assert g.get("lang", "en") in ("en", "te")


def test_golden_set_scores_do_not_regress(retriever):
    results = ev.evaluate(lambda q: top(retriever, q), ev.load_golden())
    stats = ev.summary(results)
    assert ev.below(stats, ev.FLOORS) == [], stats
