"""Validators for generated content. A validator returns the cleaned value or
raises ValidationFailed with a message the model can act on when repairing."""

from __future__ import annotations

import re
import unicodedata

from gita_content.canon import Canon, InvalidVerseRef
from gita_content.romanize import loose

from app.providers.llm import ValidationFailed

VERSE_MODES = ("simple", "deep", "practical", "story", "child")

# Character limits, generous around the word ranges asked for in the prompt
# (Telugu takes more characters per word than English).
LIMITS = {
    "simple": (150, 1600),
    "deep": (300, 3600),
    "practical": (200, 2600),
    "story": (200, 2400),
    "child": (120, 1500),
    "summary": (300, 3200),
    "theme": (20, 400),
}

# "2.47", "BG 2:47", "(18.66)." – a trailing full stop must not hide a reference,
# but parts of longer numbers ("1.234", "10.5.3") are not references.
_REF_RE = re.compile(r"(?<!\d)(?<!\d\.)(\d{1,2})\s*[.:]\s*(\d{1,2})(?!\d)(?!\.\d)")


def _text(obj: dict, key: str) -> str:
    value = obj.get(key)
    if not isinstance(value, str) or not value.strip():
        raise ValidationFailed(f'"{key}" must be a non-empty string')
    value = " ".join(value.split()) if key in ("theme",) else value.strip()
    lo, hi = LIMITS[key]
    if not lo <= len(value) <= hi:
        raise ValidationFailed(f'"{key}" has {len(value)} characters; it must be between {lo} and {hi}')
    return value


def check_references(text: str, canon: Canon, field: str, allowed_chapter: int | None = None) -> None:
    for m in _REF_RE.finditer(text):
        ch, v = int(m.group(1)), int(m.group(2))
        try:
            canon.resolve(ch, v)
        except InvalidVerseRef:
            raise ValidationFailed(
                f'"{field}" mentions verse {ch}.{v}, which does not exist; remove it'
            ) from None
        if allowed_chapter is not None and ch != allowed_chapter:
            raise ValidationFailed(
                f'"{field}" mentions {ch}.{v}; only verses of chapter {allowed_chapter} are allowed'
            )


def _telugu_share(text: str) -> float:
    letters = [c for c in text if unicodedata.category(c).startswith("L")]
    if not letters:
        return 0.0
    return sum("ఀ" <= c <= "౿" for c in letters) / len(letters)


def check_language(text: str, language: str, field: str) -> None:
    share = _telugu_share(text)
    if language == "te" and share < 0.6:
        raise ValidationFailed(f'"{field}" must be written in Telugu script')
    if language == "en" and share > 0.05:
        raise ValidationFailed(f'"{field}" must be written in English')


def verse_forms(iast: str) -> tuple[str, ...]:
    """Compact loose forms of a verse for word lookup: as written, and with
    each avagraha restored to the elided 'a' (saṅgo'stu -> saṅgo astu)."""
    return (
        loose(iast).replace(" ", ""),
        loose(iast.replace("'", "a").replace("’", "a")).replace(" ", ""),
    )


def _occurs_in(word: str, forms: tuple[str, ...]) -> bool:
    """True if `word` (usually given in its dictionary/pausal form) occurs in
    the verse. Sandhi changes word endings (adhikāraḥ -> adhikāras-te,
    karmaṇi eva -> karmaṇy eva), so the last two letters may differ; the
    stem before them must appear verbatim."""
    w = loose(word).replace(" ", "")
    if len(w) < 2:
        return False
    stem = w if len(w) <= 3 else w[: max(3, len(w) - 2)]
    return any(stem in f for f in forms)


def validate_verse(obj: dict, *, iast: str, language: str, canon: Canon) -> dict:
    out: dict = {}
    for key in VERSE_MODES:
        value = _text(obj, key)
        check_language(value, language, key)
        check_references(value, canon, key)
        out[key] = value

    compact = verse_forms(iast)
    words = obj.get("word_meanings")
    if not isinstance(words, list) or len(words) < 3:
        raise ValidationFailed('"word_meanings" must be a list with at least 3 entries')
    cleaned_words = []
    for i, w in enumerate(words):
        if (
            not isinstance(w, dict)
            or not isinstance(w.get("word"), str)
            or not isinstance(w.get("meaning"), str)
        ):
            raise ValidationFailed(f'"word_meanings"[{i}] must be {{"word": ..., "meaning": ...}}')
        if not _occurs_in(w["word"], compact):
            raise ValidationFailed(f'"word_meanings"[{i}]: "{w["word"]}" does not appear in this verse')
        if not w["meaning"].strip():
            raise ValidationFailed(f'"word_meanings"[{i}] has an empty meaning')
        cleaned_words.append({"word": w["word"].strip(), "meaning": w["meaning"].strip()})
    out["word_meanings"] = cleaned_words

    terms = obj.get("sanskrit_terms")
    if not isinstance(terms, list) or not 1 <= len(terms) <= 4:
        raise ValidationFailed('"sanskrit_terms" must be a list of 1 to 4 entries')
    cleaned_terms = []
    for i, t in enumerate(terms):
        if (
            not isinstance(t, dict)
            or not isinstance(t.get("term"), str)
            or not isinstance(t.get("meaning"), str)
        ):
            raise ValidationFailed(f'"sanskrit_terms"[{i}] must be {{"term": ..., "meaning": ...}}')
        if not _occurs_in(t["term"], compact):
            raise ValidationFailed(f'"sanskrit_terms"[{i}]: "{t["term"]}" does not appear in this verse')
        check_language(t["meaning"], language, f"sanskrit_terms[{i}].meaning")
        cleaned_terms.append({"term": t["term"].strip(), "meaning": t["meaning"].strip()})
    out["sanskrit_terms"] = cleaned_terms

    out["uncertain"] = _uncertain(obj)
    return out


def validate_chapter(obj: dict, *, chapter: int, language: str, canon: Canon) -> dict:
    out = {}
    for key in ("summary", "theme"):
        value = _text(obj, key)
        check_language(value, language, key)
        check_references(value, canon, key, allowed_chapter=chapter)
        out[key] = value
    out["uncertain"] = _uncertain(obj)
    return out


def _uncertain(obj: dict) -> list[str]:
    value = obj.get("uncertain", [])
    if not isinstance(value, list) or not all(isinstance(x, str) for x in value):
        raise ValidationFailed('"uncertain" must be a list of strings')
    return [x.strip() for x in value if x.strip()]
