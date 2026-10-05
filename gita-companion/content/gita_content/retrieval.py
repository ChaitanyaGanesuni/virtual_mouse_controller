"""Reference retriever: question → ranked verses, with no network and no model.

Three channels, fused with Reciprocal Rank Fusion:
1. explicit references in the question ("2.47", "chapter 2 verse 47") come first;
2. concepts: the question's words matched to the concept index (concepts.py),
   scored by each concept's verse weights;
3. lexical: BM25 over the English translation and explanations (stemmed) and
   the loose-romanised Sanskrit (so "karmanye" or "sthitaprajna" work too).

The server uses this module directly; the app implements the same channels
over its SQLite pack. Both are measured on the golden set (eval/golden.yaml).
An embedding channel can be added on the server (backend), but the golden-set
targets are met without one.
"""

from __future__ import annotations

import math
import re
from collections import Counter
from dataclasses import dataclass

from .concepts import ConceptIndex, is_telugu, normalize_en, tokens
from .romanize import loose

RRF_K = 60
BM25_K1, BM25_B = 1.2, 0.75
CHANNEL_WEIGHTS = {"explicit": 2.0, "concept": 1.0, "lexical": 1.0, "vector": 1.0}
# When the question clearly maps to concepts, keywords are supporting evidence.
LEXICAL_WEIGHT_WITH_CONCEPTS = 0.5
# The Gita teaches in passages (6.10-14 on meditation, 14.5-9 on the gunas):
# a verse gains this share of its neighbours' average concept score.
PASSAGE_SMOOTHING = 0.5
# Concept expansion: the English words of the concepts a question is about
# also go to the lexical channel, at this weight ("results" also finds
# Besant's "fruits"; "happiness" also finds "joy" and "bliss").
EXPANSION_WEIGHT = 0.5
# Sanskrit typed in Roman letters is matched inside the joined-up text of
# each verse ("vadhikaraste" inside "karmanyevadhikaraste"), at this weight.
SANSKRIT_WEIGHT = 1.5
MIN_SANSKRIT_TOKEN = 5

STOPWORDS = frozenset(
    """a about above after again against all am an and any are as at be because been before being below
    between both but by can could did do does doing down during each few for from further had has have
    having he her here hers herself him himself his how i if in into is it its itself just me more most my
    myself no nor not now of off on once only or other our ours ourselves out over own same she should so
    some such than that the their theirs them themselves then there these they this those through to too
    under until up very was we were what when where which while who whom why will with would you your
    yours yourself yourselves thee thou thy thine o shall unto ye hath doth what's i'm can't don't
    gita bhagavad krishna arjuna verse verses chapter say says said tell teach teaches according""".split()
)

_REF = re.compile(
    r"(?:chapter\s*(\d{1,2})\s*,?\s*verse\s*(\d{1,2}))|(?<![\d.])(\d{1,2})\s*[.:]\s*(\d{1,2})(?![\d])",
    re.IGNORECASE,
)


@dataclass(frozen=True)
class Hit:
    verse_id: str
    score: float
    channels: tuple[str, ...]
    concepts: tuple[str, ...]


class Retriever:
    """Built from the dataset alone (content format 3), like the app's search."""

    def __init__(self, dataset: dict):
        self.index = ConceptIndex.from_rows(dataset.get("concepts", []))
        self.verse_ids = [v["id"] for v in dataset["verses"]]
        self._known = set(self.verse_ids)
        self._concept_verses = {e.id: e.verses for e in self.index.entries}
        self._sanskrit = {}
        docs: dict[str, list[str]] = {}
        for v in dataset["verses"]:
            words: list[str] = []
            for t in v["texts"]:
                if t["kind"] == "transliteration" and t["language"] == "sa-Latn":
                    words += loose(t["body"]).split()
                    self._sanskrit[v["id"]] = loose(t["body"]).replace(" ", "")
                elif t["language"] == "en" and t["kind"] != "transliteration":
                    words += [w for w in normalize_en(t["body"]) if w not in STOPWORDS]
                elif t["language"] == "te":
                    words += [w for w in tokens(t["body"]) if is_telugu(w)]
            docs[v["id"]] = words
        self._tf = {vid: Counter(ws) for vid, ws in docs.items()}
        self._len = {vid: len(ws) for vid, ws in docs.items()}
        self._avg = sum(self._len.values()) / max(1, len(self._len))
        df: Counter[str] = Counter()
        for c in self._tf.values():
            df.update(c.keys())
        n = len(self._tf)
        self._idf = {w: math.log(1 + (n - f + 0.5) / (f + 0.5)) for w, f in df.items()}

    # -- channels --------------------------------------------------------------

    def explicit(self, query: str) -> list[str]:
        out = []
        for m in _REF.finditer(query):
            ch, v = (m.group(1), m.group(2)) if m.group(1) else (m.group(3), m.group(4))
            vid = f"{int(ch)}.{int(v)}"
            if vid in self._known and vid not in out:
                out.append(vid)
        return out

    def concept_scores(self, query: str) -> tuple[dict[str, float], dict[str, float]]:
        matched = self.index.match(query)
        scores: dict[str, float] = {}
        for cid, qw in matched.items():
            for vid, w in self._concept_verses.get(cid, {}).items():
                scores[vid] = scores.get(vid, 0.0) + qw * w
        if PASSAGE_SMOOTHING and scores:
            # Average of the two neighbours (same chapter), so a verse inside a
            # passage on the topic outranks a passing mention elsewhere.
            smoothed = {}
            for vid in set(scores) | {n for v in scores for n in self._neighbours(v)}:
                neighbours = self._neighbours(vid)
                around = sum(scores.get(n, 0.0) for n in neighbours) / 2
                smoothed[vid] = scores.get(vid, 0.0) + PASSAGE_SMOOTHING * around
            scores = smoothed
        return scores, matched

    def _neighbours(self, vid: str) -> list[str]:
        ch, v = vid.split(".")
        return [n for n in (f"{ch}.{int(v) - 1}", f"{ch}.{int(v) + 1}") if n in self._known]

    def lexical_scores(self, query: str, expand: dict[str, float] | None = None) -> dict[str, float]:
        raw = tokens(query)
        weights: dict[str, float] = {}
        for w in normalize_en(query):
            if w not in STOPWORDS:
                weights[w] = 1.0
        for t in raw:
            if is_telugu(t):
                weights[t] = 1.0
        for cid, qw in (expand or {}).items():
            entry = self.index.by_id.get(cid)
            if entry is None or qw < 1.0:
                continue
            for lang, key in entry.strong:
                if lang == "en" and key != entry.sa_key:
                    for w in key:
                        if w not in STOPWORDS:
                            weights.setdefault(w, EXPANSION_WEIGHT)
        scores: dict[str, float] = {}
        for w, qw in weights.items():
            idf = self._idf.get(w)
            if idf is None:
                continue
            for vid, tf in self._tf.items():
                f = tf.get(w)
                if f:
                    denom = f + BM25_K1 * (1 - BM25_B + BM25_B * self._len[vid] / self._avg)
                    scores[vid] = scores.get(vid, 0.0) + qw * idf * f * (BM25_K1 + 1) / denom
        # Sanskrit in Roman letters: substring of the verse's joined-up text.
        roman = [w for w in loose(" ".join(t for t in raw if not is_telugu(t))).split()]
        for w in dict.fromkeys(roman):
            if len(w) < MIN_SANSKRIT_TOKEN or w in self._idf:
                continue
            hits = [vid for vid, text in self._sanskrit.items() if w in text]
            if not hits or len(hits) > len(self._sanskrit) // 10:
                continue
            idf = math.log(1 + len(self._sanskrit) / len(hits))
            for vid in hits:
                scores[vid] = scores.get(vid, 0.0) + SANSKRIT_WEIGHT * idf
        return scores

    # -- fusion ------------------------------------------------------------------

    def search(self, query: str, k: int = 8, extra: dict[str, list[str]] | None = None) -> list[Hit]:
        """`extra`: rankings from channels outside this module (the server's
        vector search), fused like the others."""
        concept, matched = self.concept_scores(query)
        rankings = {
            "explicit": self.explicit(query),
            "concept": _ranked(concept),
            "lexical": _ranked(self.lexical_scores(query, matched)),
            **{name: [v for v in ranked if v in self._known] for name, ranked in (extra or {}).items()},
        }
        fused: dict[str, float] = {}
        via: dict[str, list[str]] = {}
        has_concepts = any(w == 1.0 for w in matched.values())
        for channel, ranked in rankings.items():
            w = CHANNEL_WEIGHTS.get(channel, 1.0)
            if channel == "lexical" and has_concepts:
                w = LEXICAL_WEIGHT_WITH_CONCEPTS
            for rank, vid in enumerate(ranked[:200]):
                fused[vid] = fused.get(vid, 0.0) + w / (RRF_K + rank + 1)
                via.setdefault(vid, []).append(channel)
        order = sorted(fused, key=lambda v: (-fused[v], self.verse_ids.index(v)))
        direct = tuple(c for c, w in matched.items() if w == 1.0)
        return [
            Hit(
                vid,
                round(fused[vid], 6),
                tuple(via[vid]),
                tuple(c for c in direct if vid in self._concept_verses.get(c, {})),
            )
            for vid in order[:k]
        ]


def _ranked(scores: dict[str, float]) -> list[str]:
    return [vid for vid, _ in sorted(scores.items(), key=lambda kv: (-kv[1], _order(kv[0])))]


def _order(vid: str) -> tuple[int, int]:
    a, b = vid.split(".")
    return int(a), int(b)
