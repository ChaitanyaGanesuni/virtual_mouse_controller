"""Annie Besant, The Bhagavad-Gita (4th ed., G. A. Natesan & Co., Madras, 1922),
from the proofread Wikisource transcription.

Input: a snapshot of the Wikisource "Page:" namespace (one JSON object per
line: page number, revision id, wikitext), fetched by tools/fetch_besant.py.
Output: verse-aligned rows {"chapter", "verse", "text"} for the translation
importer, plus Besant's own Sanskrit for each verse so it can be checked
against the canonical text before anything is trusted.

Each verse in the book is printed as the Sanskrit (ending "॥ N ॥") followed
by the English (ending "(N)"). A verse's English may run over a page break.
Besant's footnotes (<ref>…</ref>) are not part of the translation and are
dropped; her spelling (Dhritarâshtra, Pârtha) is kept as printed.
"""

from __future__ import annotations

import json
import re
from dataclasses import dataclass
from pathlib import Path

FIRST_TEXT_PAGE, LAST_TEXT_PAGE = 11, 274  # book pages 1-264; the rest is front matter and adverts

_NOINCLUDE = re.compile(r"<noinclude>.*?</noinclude>", re.S)
_REF = re.compile(r"<ref[^>/]*>.*?</ref>|<ref[^>]*/>", re.S)
_SA_OPEN = "{{lang block|sa|"
_MARKER_OPEN = "{{float right|"
_MARKER_NUMBER = re.compile(r"\(?(\d+)\)")
_SA_NUMBER = re.compile(r"॥\s*([०-९]+)\s*॥")
_COLOPHON = re.compile(r"इति\s*श्रीमद्भगवद्गीता")


# Verse markers printed wrongly in the book or transcription, checked by hand
# against the Sanskrit printed above the English. (chapter, Sanskrit number)
# → the English marker that follows it.
MARKER_MISPRINTS: dict[tuple[int, int], int] = {
    (17, 19): 20,  # English for the tāmasa austerity is marked "(20)"; the next verse is also "(20)"
    (18, 14): 15,  # "The body, the actor, the various organs…" (adhiṣṭhānaṃ) is marked "(15)"
}


class BesantParseError(ValueError):
    pass


@dataclass(frozen=True)
class BesantVerse:
    chapter: int
    verse: int
    sanskrit: str
    text: str
    pages: tuple[int, ...]


@dataclass(frozen=True)
class _Block:
    begin: int
    stop: int
    body: str

    def group(self, _i: int = 1) -> str:
        return self.body

    def end(self) -> int:
        return self.stop


def _balanced(text: str, opener: str) -> list[_Block]:
    """Every {{opener…}} template, including templates nested inside it."""
    out, i = [], 0
    while (start := text.find(opener, i)) >= 0:
        depth, j = 1, start + len(opener)
        while depth and j < len(text):
            if text.startswith("{{", j):
                depth, j = depth + 1, j + 2
            elif text.startswith("}}", j):
                depth, j = depth - 1, j + 2
            else:
                j += 1
        if depth:
            raise BesantParseError(f"unclosed template {opener!r} at offset {start}")
        out.append(_Block(start, j, text[start + len(opener) : j - 2]))
        i = j
    return out


def _sanskrit_blocks(text: str) -> list[_Block]:
    """{{lang block|sa|…}} with nested templates inside ({{c|सञ्जय उवाच ।}})."""
    return _balanced(text, _SA_OPEN)


def _markers(text: str) -> list[tuple[_Block, int]]:
    """English verse markers: {{float right|{{larger|(N)}}}}. The transcription
    also has {{SIC|(20|(20)}} (a corrected misprint: the last number is the
    right one), {{SIC|{{gap}}|(31)}} and "32)" with the bracket missing."""
    out = []
    for b in _balanced(text, _MARKER_OPEN):
        numbers = _MARKER_NUMBER.findall(b.body)
        if numbers:
            out.append((b, int(numbers[-1])))
    return out


def read_snapshot(path: Path) -> list[dict]:
    return [json.loads(line) for line in path.read_text(encoding="utf-8").splitlines() if line.strip()]


def _dev_int(s: str) -> int:
    return int(s.translate(str.maketrans("०१२३४५६७८९", "0123456789")))


_WRAPPERS = r"(?:sc|small-caps|smallcaps|lang|SIC|sic|larger|smaller|nowrap|em|i|u|c|center|gap)"


def _unwrap(s: str) -> str:
    """Templates that wrap text keep their last argument ({{sc|Eternal}} →
    Eternal, {{SIC|wrong|right}} → right); other templates are layout and go."""
    for _ in range(5):
        s = re.sub(r"\{\{" + _WRAPPERS + r"\|(?:[^{}|]*\|)*([^{}|]*)\}\}", r"\1", s)
        s = re.sub(r"\{\{gap\}\}", " ", s)
    return re.sub(r"\{\{[^{}]*\}\}", " ", s)


def _clean_sanskrit(s: str) -> str:
    s = re.sub(r"\{\{c\|[^{}]*(?:उवाच|ुवाच)[^{}]*\}\}", " ", s)  # speaker headings (…उवाच, श्रीभगवानुवाच)
    return " ".join(_SA_NUMBER.sub("", _unwrap(s)).split())


def _clean_english(s: str) -> str:
    s = _REF.sub("", s)
    s = re.sub(r"\{\{c\|[^{}]*said:?[^{}]*\}\}", " ", s)  # "Sanjaya said:" headings
    # Chapter 11's hymn is set as verse: {{block center|width=350px|<poem>… (N)</poem>}};
    # the verse marker sits inside, so the segment holds only the opener.
    s = re.sub(r"\{\{block center(?:/s)?(?:\|width=[^|{}]*)?\|", " ", s)
    s = re.sub(r"\|?\s*width\s*=\s*\d+(?:px|em|%)\s*\|?", " ", s)
    s = _unwrap(s)
    s = s.replace("{{", " ").replace("}}", " ")  # closing braces of the block around the Sanskrit
    s = re.sub(r"\[\[(?:[^\]|]*\|)?([^\]]*)\]\]", r"\1", s)  # [[link|text]] → text
    s = re.sub(r"'{2,}", "", s)  # ''italic'', '''bold'''
    s = re.sub(r"<br\s*/?>", " ", s)
    s = re.sub(r"<[^>]+>", " ", s)
    s = s.replace("&nbsp;", " ").replace("&#8203;", "")
    s = " ".join(s.split())
    # Two speaker labels are typed inline instead of as headings; the app
    # shows the speaker separately.
    return re.sub(r"^(?:Arjuna|The Blessed Lord|Sanjaya|Dhritarâshtra) said:\s*", "", s)


def parse(pages: list[dict]) -> list[BesantVerse]:
    """Walk the text pages in order, pairing each Sanskrit block with the
    English that follows it up to the "(N)" marker."""
    stream: list[tuple[int, str]] = []
    for p in sorted(pages, key=lambda p: p["n"]):
        if FIRST_TEXT_PAGE <= p["n"] <= LAST_TEXT_PAGE:
            body = _NOINCLUDE.sub("", p["text"])
            # A word hyphenated across a page break ("griev-" | "ed") is one word.
            body = re.sub(r"([a-zâîûêô])-\s*$", "\\1\x01", body)
            stream.append((p["n"], body))

    # One string with page markers, so verses can cross page breaks.
    text = "".join(f"\x00{n}\x00{body}\n" for n, body in stream)

    out: list[BesantVerse] = []
    chapter, pending_sa, pending_num, english_start = 0, None, None, None
    carry = ""
    pos = 0
    events = sorted(
        [(b.begin, "sa", b) for b in _sanskrit_blocks(text)]
        + [(b.begin, "en", (b, n)) for b, n in _markers(text)]
    )
    for start, kind, m in events:
        if start < pos:
            continue
        if kind == "sa":
            body = m.group(1)
            if _COLOPHON.search(body):
                pending_sa, carry = None, ""
                pos = m.end()
                continue
            num = _SA_NUMBER.search(body)
            if not num:
                # The first half of a verse printed at the bottom of a page
                # (the number follows on the next page), or a heading.
                carry = (carry + " " + body) if carry else body
                pos = m.end()
                continue
            body = (carry + " " + body) if carry else body
            carry = ""
            n = _dev_int(num.group(1))
            if n == 1 or (out and out[-1].chapter == chapter and n <= out[-1].verse and n <= 2):
                chapter += 1
            pending_sa, pending_num, english_start = body, n, m.end()
            pos = m.end()
        else:
            m, n = m
            if pending_sa is None or english_start is None:
                raise BesantParseError(f"English verse ({n}) without its Sanskrit near offset {start}")
            if n != pending_num and MARKER_MISPRINTS.get((chapter, pending_num)) == n:
                n = pending_num
            if n != pending_num:
                raise BesantParseError(
                    f"chapter {chapter}: Sanskrit ॥{pending_num}॥ followed by English ({n})"
                )
            segment = text[english_start:start]
            pages_spanned = tuple(int(x) for x in re.findall(r"\x00(\d+)\x00", text[:start])[-1:])
            page_ids = tuple(int(x) for x in re.findall(r"\x00(\d+)\x00", segment)) or pages_spanned
            segment = re.sub(r"\x01\s*\x00\d+\x00\s*", "", segment)
            english = _clean_english(re.sub(r"\x00\d+\x00", " ", segment))
            sanskrit = _clean_sanskrit(pending_sa)
            if not english:
                raise BesantParseError(f"{chapter}.{n}: empty English")
            out.append(BesantVerse(chapter, n, sanskrit, english, page_ids))
            pending_sa, english_start = None, None
            pos = m.end()
    return out


# Besant's edition divides these verses at a different half-line from the
# canonical text (1.20 | 1.21 and 1.27 | 1.28), so her English for them
# covers a slightly different span. Checked by hand; the build fails on any
# other mismatch between her Sanskrit and ours.
KNOWN_DIVISION_DIFFERENCES = frozenset({"1.20", "1.21", "1.28"})
MIN_SIMILARITY = 0.95


def canonical_id(v: BesantVerse) -> str:
    """Besant numbers chapter 13 like the 701-verse editions (Arjuna's
    question is her 13.1, our 13.0)."""
    return f"13.{v.verse - 1}" if v.chapter == 13 else f"{v.chapter}.{v.verse}"


def check_against(verses: list[BesantVerse], sanskrit_by_id: dict[str, str]) -> list[tuple[str, float]]:
    """Unexplained differences between Besant's Sanskrit and the canonical
    text, as (verse id, similarity). Empty means the alignment is sound."""
    from difflib import SequenceMatcher

    from ..romanize import loose
    from ..transliterate import transliterate

    def key(s: str) -> str:
        return loose(transliterate(s, "sa-Latn")).replace(" ", "")

    ids = [canonical_id(v) for v in verses]
    problems: list[tuple[str, float]] = []
    missing = set(sanskrit_by_id) - set(ids)
    problems += [(vid, 0.0) for vid in sorted(missing)]
    for v, vid in zip(verses, ids, strict=True):
        if vid not in sanskrit_by_id:
            problems.append((vid, 0.0))
            continue
        ratio = SequenceMatcher(None, key(v.sanskrit), key(sanskrit_by_id[vid])).ratio()
        if ratio < MIN_SIMILARITY and vid not in KNOWN_DIVISION_DIFFERENCES:
            problems.append((vid, round(ratio, 3)))
    return problems


def to_jsonl_canonical(verses: list[BesantVerse]) -> str:
    """Rows for the translation importer, in canonical numbering."""
    out = []
    for v in verses:
        ch, n = canonical_id(v).split(".")
        out.append(
            json.dumps({"chapter": int(ch), "verse": int(n), "text": v.text}, ensure_ascii=False) + "\n"
        )
    return "".join(out)
