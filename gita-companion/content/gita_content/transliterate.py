"""Deterministic script conversion of Sanskrit (no AI involved).

Language tags follow BCP-47: `sa` (Devanagari), `sa-Latn` (IAST),
`sa-Telu` (Sanskrit in Telugu script). Adding another script (e.g. Kannada)
is one entry in SCRIPTS.
"""

from __future__ import annotations

from indic_transliteration import sanscript

SCRIPTS: dict[str, str] = {
    "sa-Latn": sanscript.IAST,
    "sa-Telu": sanscript.TELUGU,
}

# indic_transliteration renders dandas in IAST as "|" and "||"; we keep the
# Unicode dandas, which read better next to Latin text and are what printed
# IAST editions use.
_IAST_PUNCT = (("||", "॥"), ("|", "।"))


def transliterate(text: str, tag: str) -> str:
    if tag == "sa":
        return text
    out = sanscript.transliterate(text, sanscript.DEVANAGARI, SCRIPTS[tag])
    if tag == "sa-Latn":
        for a, b in _IAST_PUNCT:
            out = out.replace(a, b)
    return out


def all_scripts(text: str) -> dict[str, str]:
    return {"sa": text, **{tag: transliterate(text, tag) for tag in SCRIPTS}}
