"""Concept index: everyday words → Gita concepts → verses.

The editorial lexicon (editorial/concepts.yaml) gives each concept the
English and Telugu words people use for it, and the Sanskrit stems the Gita
uses. A verse is linked to a concept only if one of the stems occurs in its
(canonical, loose-romanised) text, so no verse number is ever asserted by
hand. Weights favour verses that contain more, and rarer, concept stems.

Query matching (`match_concepts`) must behave identically in the app; the
normalisation rules live in `normalize_en` / `telugu_stem`, and
tests/query_vectors.json holds the shared test vectors.
"""

from __future__ import annotations

import math
import re
import unicodedata
from dataclasses import dataclass, field
from pathlib import Path

import yaml

from .enrich import EDITORIAL_DIR
from .romanize import loose

CONCEPTS_FILE = EDITORIAL_DIR / "concepts.yaml"
WEAK_FACTOR = 0.5
MAX_WORDS = 3
IDF_POWER = 1.0  # softer powers (0.25-0.75) were tried and scored worse
RELATED_FACTOR = 0.35
# Generic words ("god", "work", "mind") point to a concept only weakly.
WEAK_TERM_FACTOR = 0.35


class ConceptError(ValueError):
    pass


@dataclass(frozen=True)
class Concept:
    id: str
    sa: str
    name_en: str
    name_te: str
    definition_en: str
    terms_en: tuple[str, ...]
    terms_te: tuple[str, ...]
    weak_en: tuple[str, ...]
    weak_te: tuple[str, ...]
    stems: tuple[str, ...]
    weak: tuple[str, ...]
    exclude: tuple[str, ...]
    related: tuple[str, ...]
    verses: dict[str, float] = field(default_factory=dict, compare=False)


def load_concepts(path: Path = CONCEPTS_FILE) -> list[Concept]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    out: list[Concept] = []
    for raw in data["concepts"]:
        try:
            c = Concept(
                id=raw["id"],
                sa=raw["sa"],
                name_en=raw["en"]["name"],
                name_te=raw["te"]["name"],
                definition_en=raw["en"]["definition"],
                terms_en=tuple(raw["en"]["terms"]),
                terms_te=tuple(raw["te"]["terms"]),
                weak_en=tuple(raw["en"].get("weak", [])),
                weak_te=tuple(raw["te"].get("weak", [])),
                stems=tuple(raw.get("stems", [])),
                weak=tuple(raw.get("weak", [])),
                exclude=tuple(raw.get("exclude", [])),
                related=tuple(raw.get("related", [])),
            )
        except KeyError as e:
            raise ConceptError(f"concept {raw.get('id')}: missing {e}") from None
        for s in (*c.stems, *c.weak):
            try:
                re.compile(s)
            except re.error as e:
                raise ConceptError(f"concept {c.id}: bad stem {s!r}: {e}") from None
        out.append(c)
    ids = [c.id for c in out]
    if len(ids) != len(set(ids)):
        raise ConceptError("duplicate concept ids")
    for c in out:
        for r in c.related:
            if r not in ids or r == c.id:
                raise ConceptError(f"concept {c.id}: unknown related concept {r!r}")
    return out


# ---- verse linking -------------------------------------------------------------


def _stem_hits(stem: str, exclude: tuple[str, ...], text: str) -> bool:
    """A stem with a space matches a phrase in the whole verse; otherwise it
    is a pattern searched inside each word, and a word containing one of the
    concept's exclusions does not count."""
    if " " in stem:
        return stem in text
    return any(re.search(stem, w) and not any(e in w for e in exclude) for w in text.split())


def link_verses(concepts: list[Concept], iast_by_verse: dict[str, str]) -> list[Concept]:
    """Fill each concept's verse weights (0-1, the best verse of a concept = 1).

    Each distinct word of the verse that matches one of the concept's stems
    adds that stem's idf = ln(1 + N / df) (× 0.5 for weak stems; the best
    stem if several match the same word; at most MAX_WORDS words count).
    Phrase stems count once. Weights are then divided by the concept maximum.
    """
    texts = {vid: loose(t) for vid, t in iast_by_verse.items()}
    n = len(texts)
    dead: list[str] = []
    for c in concepts:
        stems = [(s, 1.0) for s in c.stems] + [(s, WEAK_FACTOR) for s in c.weak]
        idf: dict[str, float] = {}
        for stem, factor in stems:
            df = sum(1 for t in texts.values() if _stem_hits(stem, c.exclude, t))
            if not df:
                dead.append(f"{c.id}:{stem}")
                continue
            idf[stem] = math.log(1 + n / df) ** IDF_POWER * factor
        scores: dict[str, float] = {}
        for vid, text in texts.items():
            word_scores: dict[str, float] = {}
            for stem, w in idf.items():
                if " " in stem:
                    if stem in text:
                        word_scores[stem] = max(word_scores.get(stem, 0.0), w)
                    continue
                for word in set(text.split()):
                    if re.search(stem, word) and not any(e in word for e in c.exclude):
                        word_scores[word] = max(word_scores.get(word, 0.0), w)
            if word_scores:
                scores[vid] = sum(sorted(word_scores.values(), reverse=True)[:MAX_WORDS])
        if not scores:
            raise ConceptError(f"concept {c.id} matches no verse")
        top = max(scores.values())
        c.verses.clear()
        c.verses.update({vid: round(s / top, 3) for vid, s in scores.items()})
    if dead:
        raise ConceptError("stems that match no verse (fix or remove them): " + ", ".join(dead))
    return concepts


# ---- query understanding ---------------------------------------------------------
# The app ports these functions exactly (lib/core/search/concepts.dart).

_TOKEN = re.compile(r"(?:[^\W\d_]|[ऀ-ൿ])+")
_TE_SUFFIXES = ("ాలు", "లు", "ము", "ం", "ు")


def _stem_en(w: str) -> str:
    if len(w) <= 3:
        return w
    if w.endswith("ies") and len(w) > 4:
        return w[:-3] + "y"
    if w.endswith("ied") and len(w) > 4:
        return w[:-3] + "y"
    if w.endswith("ness") and len(w) > 6:
        return w[:-4]
    if w.endswith("ing") and len(w) > 5:
        w = w[:-3]
        return w[:-1] if len(w) > 2 and w[-1] == w[-2] and w[-1] not in "lsz" else w
    if w.endswith("ed") and len(w) > 4:
        w = w[:-2]
        return w[:-1] if len(w) > 2 and w[-1] == w[-2] and w[-1] not in "lsz" else w
    if w.endswith("ly") and len(w) > 5:
        return w[:-2]
    if w.endswith(("sses", "ches", "shes", "xes")):
        return w[:-2]
    if w.endswith("s") and not w.endswith(("ss", "us", "is")):
        return w[:-1]
    return w


# Latin letters with diacritics → plain letters (yajña → yajna, Kṛṣṇa → krsna,
# Besant's Pârtha → partha). An explicit table, not Unicode decomposition,
# because Telugu vowel signs are combining marks too and must stay.
_LATIN_FOLD = str.maketrans(
    "āáàâäãīíìîïūúùûüēéèêëōóòôöṛṝḷḹṅñṇṭḍśṣṃṁḥçṯḏ",
    "aaaaaaiiiiiuuuuueeeeeooooorrllnnntdssmmhctd",
)


def tokens(text: str) -> list[str]:
    s = unicodedata.normalize("NFC", text.lower().replace("’", "'")).translate(_LATIN_FOLD)
    s = re.sub(r"'s\b", "", s)
    return _TOKEN.findall(s)


def is_telugu(token: str) -> bool:
    return any("ఀ" <= ch <= "౿" for ch in token)


def normalize_en(text: str) -> list[str]:
    return [_stem_en(t) for t in tokens(text) if not is_telugu(t)]


def telugu_stem(term: str) -> str:
    """Drop one common ending so "కోపం" also matches "కోపాన్ని", "కోపంతో"."""
    for suf in _TE_SUFFIXES:
        if term.endswith(suf) and len(term) - len(suf) >= 2:
            return term[: -len(suf)]
    return term


def term_key(term: str, language: str) -> tuple[str, ...]:
    """How a lexicon term is stored for matching (the pack stores this)."""
    if language == "te":
        return tuple(telugu_stem(t) for t in tokens(term))
    return tuple(normalize_en(term))


def _matches(key: tuple[str, ...], query: list[str], language: str) -> bool:
    if not key or len(key) > len(query):
        return False
    for i in range(len(query) - len(key) + 1):
        window = query[i : i + len(key)]
        if language == "te":
            if all(q.startswith(k) for q, k in zip(window, key, strict=True)):
                return True
        elif tuple(window) == key:
            return True
    return False


def concept_keys(c: Concept, weak: bool = False) -> list[tuple[str, tuple[str, ...]]]:
    if weak:
        keys = [("en", term_key(t, "en")) for t in c.weak_en] + [("te", term_key(t, "te")) for t in c.weak_te]
    else:
        keys = [("en", term_key(t, "en")) for t in (*c.terms_en, c.name_en)]
        keys += [("en", tuple(loose(c.sa).split()))]  # "krodha", "karma yoga" typed in Roman letters
        keys += [("te", term_key(t, "te")) for t in (*c.terms_te, c.name_te)]
    return [(lang, k) for lang, k in dict.fromkeys(keys) if k]


def match_concepts(query: str, concepts: list[Concept]) -> dict[str, float]:
    """Concepts the query is about: 1.0 for a direct match, RELATED_FACTOR
    for concepts related to a direct match."""
    raw = tokens(query)
    en = [_stem_en(t) for t in raw if not is_telugu(t)]
    loose_q = loose(" ".join(t for t in raw if not is_telugu(t))).split()
    te = [t for t in raw if is_telugu(t)]

    def hit(c: Concept, weak: bool) -> bool:
        for lang, key in concept_keys(c, weak):
            q = te if lang == "te" else en
            if _matches(key, q, lang) or (lang == "en" and not weak and _matches(key, loose_q, lang)):
                return True
        return False

    direct = {c.id: 1.0 for c in concepts if hit(c, weak=False)}
    by_id = {c.id: c for c in concepts}
    out = dict(direct)
    for cid in direct:
        for r in by_id[cid].related:
            out.setdefault(r, RELATED_FACTOR)
    for c in concepts:
        if c.id not in out and hit(c, weak=True):
            out[c.id] = WEAK_TERM_FACTOR
    return out


def concept_rows(concepts: list[Concept], source_id: str) -> list[dict]:
    """Dataset rows (content format 3)."""
    return [
        {
            "id": c.id,
            "term_sa": c.sa,
            "source_id": source_id,
            "names": {"en": c.name_en, "te": c.name_te},
            "definition_en": c.definition_en,
            "terms": {
                "en": _unique(
                    [" ".join(term_key(t, "en")) for t in (*c.terms_en, c.name_en)]
                    + [" ".join(loose(c.sa).split())]
                ),
                "te": _unique([" ".join(term_key(t, "te")) for t in (*c.terms_te, c.name_te)]),
            },
            "weak_terms": {
                "en": _unique([" ".join(term_key(t, "en")) for t in c.weak_en]),
                "te": _unique([" ".join(term_key(t, "te")) for t in c.weak_te]),
            },
            "related": list(c.related),
            "verses": sorted(([v, w] for v, w in c.verses.items()), key=lambda x: (-x[1], _order(x[0]))),
        }
        for c in concepts
    ]


def _unique(keys: list[str]) -> list[str]:
    return [k for k in dict.fromkeys(keys) if k]


def _order(vid: str) -> tuple[int, int]:
    a, b = vid.split(".")
    return int(a), int(b)
