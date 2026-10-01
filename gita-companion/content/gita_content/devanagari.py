"""Normalisation and parsing of Devanagari verse text.

Raw datasets differ in danda style ('|', '।।', '॥'), embed verse numbers in
Latin or Devanagari digits, sometimes glue the speaker line ("श्रीभगवानुवाच")
to the verse, and sometimes lose line breaks. This module produces one
canonical shape:

    speaker: "krishna"                     (or None)
    lines:   ["... ।", "... ॥"]            (one half-verse per line)

The verse number is never part of the stored text; the UI renders it.
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field

DANDA = "।"
DOUBLE_DANDA = "॥"
AVAGRAHA = "ऽ"

SPEAKER_LINES = {
    "dhritarashtra": "धृतराष्ट्र उवाच",
    "sanjaya": "सञ्जय उवाच",
    "arjuna": "अर्जुन उवाच",
    "krishna": "श्रीभगवानुवाच",
}

_SPEAKER_PATTERNS = [
    ("dhritarashtra", re.compile(r"धृतराष्ट्र")),
    ("sanjaya", re.compile(r"स[ञं]जय|सञ्जय")),
    ("arjuna", re.compile(r"अर्जुन")),
    ("krishna", re.compile(r"भगवान")),
]

_DIGITS = "0-9०-९"
# "।।1.1।।", "॥२-४७॥", "||2-47||", "।।18.78।", "1.1" (with or without dandas)
_VERSE_NUMBER_RE = re.compile(rf"[।॥|]*\s*[{_DIGITS}]+\s*[.\-]\s*[{_DIGITS}]+\s*[।॥|]*")
# Speaker line at the start: "<name> उवाच" (possibly glued: "श्रीभगवानुवाच").
# "उवाच" after a consonant is written with the vowel sign: भगवान् + उवाच = भगवानुवाच.
_UVACA = "(?:उ|ु)वाच"
_LEADING_SPEAKER_RE = re.compile(rf"^\s*([^।॥\n]{{0,25}}?{_UVACA})\s*[।॥]?\s*")
# A speaker line in the middle of a verse (e.g. "... ।\nअर्जुन उवाच ।\n...").
_INNER_SPEAKER_RE = re.compile(rf"[^\s।॥]*\s?[^\s।॥]*{_UVACA}")
_INVISIBLES = dict.fromkeys(map(ord, "﻿​­"), None)

# Allowed characters in canonical verse text: Devanagari block (minus digits,
# which belong to verse numbers), spaces, newlines.
_ALLOWED_RE = re.compile(r"^[ऀ-॥॰-ॿ \n]*$")


@dataclass
class ParsedVerse:
    speaker: str | None
    lines: list[str]
    inner_speakers: list[str] = field(default_factory=list)
    fixes: list[str] = field(default_factory=list)

    @property
    def text(self) -> str:
        return "\n".join(self.lines)

    @property
    def speaker_line(self) -> str | None:
        return SPEAKER_LINES[self.speaker] if self.speaker else None


class DevanagariError(ValueError):
    pass


# Repairs for damage caused by converting text from legacy (pre-Unicode)
# Devanagari fonts, where glyphs were stored in visual order. Each rule is
# unambiguous in Sanskrit, so it is safe to apply to any source.
_LEGACY_REPAIRS: list[tuple[str, re.Pattern[str], str]] = [
    # The i-mātrā is drawn before a conjunct, so legacy text stores it after
    # the first virāma: श्िच -> श्चि, क्ित -> क्ति, त्ित्र -> त्त्रि.
    ("i-matra reordered after conjunct", re.compile(r"्ि((?:[क-ह]्)*[क-ह])"), r"्\1ि"),
    # "श्रृ" (śrṛ) does not occur in Sanskrit; it is a legacy rendering of "शृ" (śṛ).
    ("श्रृ -> शृ", re.compile(r"श्रृ"), "शृ"),
    # Long vocalic ṝ encoded as short ṛ + nukta.
    ("ृ़ -> ॄ", re.compile(r"ृ़"), "ॄ"),
    # Sanskrit does not use the nukta; a stray one is an encoding artefact.
    ("stray nukta removed", re.compile(r"़"), ""),
]


def repair_legacy_encoding(text: str) -> tuple[str, list[str]]:
    fixes = []
    for label, pattern, repl in _LEGACY_REPAIRS:
        text, n = pattern.subn(repl, text)
        if n:
            fixes.append(f"{label} (x{n})")
    return text, fixes


def basic_normalize(raw: str) -> str:
    text = unicodedata.normalize("NFC", raw).translate(_INVISIBLES)
    text = text.replace(" ", " ").replace("\r", "")
    return text.replace("||", DOUBLE_DANDA).replace("।।", DOUBLE_DANDA).replace("|", DANDA)


def speaker_key(speaker_text: str) -> str | None:
    """Map a "<name> उवाच" line to a speaker key. Returns None for text that
    merely contains the verb (e.g. 2.10 "तमुवाच हृषीकेशः ...")."""
    for key, pattern in _SPEAKER_PATTERNS:
        if pattern.search(speaker_text):
            return key
    return None


_EDITORIAL_NOTE_RE = re.compile(r"\((?:or|var)[^)]*\)")
_LINE_HYPHEN_RE = re.compile(r"-\s+")


def parse_verse(raw: str, lenient: bool = False) -> ParsedVerse:
    """Parse one verse. `lenient` additionally drops editorial variant notes
    such as "(or ...)" and re-joins words hyphenated across pādas; it is used
    only for verification sources, never for text we ship."""
    text, fixes = repair_legacy_encoding(basic_normalize(raw))
    if lenient:
        text = _EDITORIAL_NOTE_RE.sub("", text)
        text = _LINE_HYPHEN_RE.sub("", text)

    stripped = _VERSE_NUMBER_RE.sub(DOUBLE_DANDA, text)
    if stripped != text:
        text = stripped

    speaker = None
    m = _LEADING_SPEAKER_RE.match(text)
    if m and (key := speaker_key(m.group(1))):
        speaker = key
        text = text[m.end() :]

    # Flatten, then split after every danda: one half-verse per line.
    flat = re.sub(r"\s+", " ", text).strip()
    flat = re.sub(rf"\s*([{DANDA}{DOUBLE_DANDA}])", r" \1", flat)
    flat = re.sub(rf"(?:\s*{DOUBLE_DANDA})+", f" {DOUBLE_DANDA}", flat)

    inner_speakers: list[str] = []
    segments = [s.strip() for s in re.split(rf"(?<=[{DANDA}{DOUBLE_DANDA}])", flat) if s.strip()]
    lines: list[str] = []
    for seg in segments:
        body = seg.rstrip(f"{DANDA}{DOUBLE_DANDA} ").strip()
        if not body:
            continue
        if _INNER_SPEAKER_RE.fullmatch(body) and (key := speaker_key(body)):
            inner_speakers.append(key)
            lines.append(SPEAKER_LINES[key])
            continue
        lines.append(seg)

    verse_idx = [i for i, ln in enumerate(lines) if ln not in SPEAKER_LINES.values()]
    if not verse_idx:
        raise DevanagariError(f"no verse text found in {raw!r}")

    # Every half-verse ends in a danda; the last one in a double danda.
    for i in verse_idx:
        ln = lines[i]
        is_last = i == verse_idx[-1]
        want = DOUBLE_DANDA if is_last else DANDA
        if not ln.endswith((DANDA, DOUBLE_DANDA)):
            lines[i] = f"{ln} {want}"
            fixes.append(f"added missing {want!r} to line {i + 1}")
        elif is_last and ln.endswith(DANDA):
            lines[i] = ln[:-1] + DOUBLE_DANDA
            fixes.append("final danda changed to double danda")
        elif not is_last and ln.endswith(DOUBLE_DANDA):
            lines[i] = ln[:-1] + DANDA
            fixes.append(f"inner double danda on line {i + 1} changed to danda")

    for ln in lines:
        if not _ALLOWED_RE.match(ln):
            bad = sorted({ch for ch in ln if not _ALLOWED_RE.match(ch)})
            raise DevanagariError(f"unexpected characters {bad!r} in line {ln!r}")

    return ParsedVerse(speaker=speaker, lines=lines, inner_speakers=inner_speakers, fixes=fixes)


_PUNCT_SPACE_RE = re.compile(rf"[\s{DANDA}{DOUBLE_DANDA}]")
_NASAL_BEFORE_CONSONANT_RE = re.compile(r"[ङञणनम]्(?=[क-ह])")


def strict_key(text: str) -> str:
    """Text with spacing and punctuation removed: equal keys = same words."""
    return _PUNCT_SPACE_RE.sub("", unicodedata.normalize("NFC", text))


def orthographic_key(text: str) -> str:
    """Also ignores avagraha and anusvāra-vs-nasal-consonant spelling choices,
    which are editorial conventions rather than textual differences."""
    key = strict_key(text).replace(AVAGRAHA, "")
    return _NASAL_BEFORE_CONSONANT_RE.sub("ं", key)
