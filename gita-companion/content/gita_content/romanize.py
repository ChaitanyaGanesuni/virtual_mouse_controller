"""Loose ASCII romanisation for search.

People type Sanskrit without diacritics and with informal spellings
("karmanye", "phaleshu", "kadachana", "krishna"). Both the indexed text and
the user's query go through `loose()`, so the two meet in the middle. The
mobile app must port this function exactly; tests/test_romanize.py holds the
shared test vectors.

The folding is deliberately lossy (ś, ṣ, s all become "s"; c and ch both
become "ch"): it is only ever used for matching, never for display.
"""

from __future__ import annotations

import re
import unicodedata

_IAST = [
    ("ch", "\x01"),  # IAST 'ch' (छ) protected before 'c' is expanded
    ("c", "ch"),
    ("\x01", "ch"),
    ("ś", "s"),
    ("ṣ", "s"),
    ("ṝ", "ri"),
    ("ṛ", "ri"),
    ("ḹ", "li"),
    ("ḷ", "li"),
    ("ṅ", "n"),
    ("ñ", "n"),
    ("ṇ", "n"),
    ("ṃ", "m"),
    ("ṁ", "m"),
    ("ḥ", "h"),
]
_INFORMAL = [
    ("chh", "ch"),
    ("sh", "s"),
    ("x", "ks"),
    ("w", "v"),
    ("ee", "i"),
    ("oo", "u"),
    ("aa", "a"),
    ("ii", "i"),
    ("uu", "u"),
]


def loose(text: str) -> str:
    s = unicodedata.normalize("NFC", text.lower())
    for a, b in _IAST:
        s = s.replace(a, b)
    # Remaining diacritics (ā ī ū ṭ ḍ ...) are simply dropped.
    s = unicodedata.normalize("NFKD", s)
    s = "".join(ch for ch in s if not unicodedata.combining(ch))
    s = re.sub(r"['’ऽ]", "", s)
    s = re.sub(r"[^a-z0-9]+", " ", s)
    for a, b in _INFORMAL:
        s = s.replace(a, b)
    return " ".join(s.split())
