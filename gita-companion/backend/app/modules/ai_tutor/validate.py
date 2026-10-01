"""Grounding contract for tutor answers, enforced in code.

`check_answer` runs inside the LLM call. Anything it raises goes back to the
model as a repair request, then to the next provider:
- the JSON shape is wrong;
- the answer mentions a verse that does not exist (2.99, 19.1, chapter 20);
- the answer mentions a verse that was not among the passages it was given;
- the answer cites nothing at all (unless it says the question is out of scope);
- the answer is in the wrong language.

`finalize` then cleans what may stay, and records each fix in `flags`:
- citations of missing or unretrieved verses are removed;
- a citation's source must be a passage of that verse, else the verse's
  Sanskrit source is used;
- verses referenced in the text but missing from the citation list are added;
- quotations that do not match any passage lose their quotation marks
  (they are shown as paraphrase).
"""

from __future__ import annotations

import re
import unicodedata
from dataclasses import dataclass, field
from difflib import SequenceMatcher

from app.modules.ai_tutor.refs import chapter_refs, verse_refs
from app.modules.ai_tutor.retrieval import Context, VerseIndex
from app.providers.llm import ValidationFailed

MAX_ANSWER_CHARS = 5000
CONFIDENCE = ("high", "medium", "low")


@dataclass(frozen=True)
class Citation:
    verse: str
    source_id: str


@dataclass
class Answer:
    text: str
    citations: list[Citation]
    confidence: str
    uncertain_points: list[str]
    out_of_scope: bool
    flags: list[str] = field(default_factory=list)


def _telugu_share(text: str) -> float:
    letters = [c for c in text if unicodedata.category(c).startswith("L")]
    if not letters:
        return 0.0
    return sum("ఀ" <= c <= "౿" for c in letters) / len(letters)


def check_references(text: str, ctx: Context, index: VerseIndex, field_name: str) -> None:
    for ch in chapter_refs(text):
        if ch not in index.chapter_counts:
            raise ValidationFailed(f'"{field_name}" mentions chapter {ch}; the Gita has 18 chapters')
    for r in verse_refs(text):
        if r.id not in index.ids:
            raise ValidationFailed(
                f'"{field_name}" mentions verse {r.id}, which does not exist. Remove it, and do not write '
                f'other numbers in the form "number.number"'
            )
        if r.id not in ctx.verse_ids:
            raise ValidationFailed(
                f'"{field_name}" mentions BG {r.id}, which is not among the passages. Use only: '
                f"{', '.join(ctx.verse_ids) or 'no verses'}"
            )


def check_answer(obj: dict, ctx: Context, index: VerseIndex, language: str) -> Answer:
    text = obj.get("answer")
    if not isinstance(text, str) or not text.strip():
        raise ValidationFailed('"answer" must be a non-empty string')
    text = text.strip()
    if len(text) > MAX_ANSWER_CHARS:
        raise ValidationFailed(f'"answer" is too long ({len(text)} characters); make it shorter')

    out_of_scope = obj.get("out_of_scope") is True
    raw_citations = obj.get("citations", [])
    if not isinstance(raw_citations, list):
        raise ValidationFailed('"citations" must be a list')
    uncertain = obj.get("uncertain_points", [])
    if not isinstance(uncertain, list) or not all(isinstance(u, str) for u in uncertain):
        raise ValidationFailed('"uncertain_points" must be a list of strings')
    uncertain = [u.strip() for u in uncertain if u.strip()][:5]
    confidence = obj.get("confidence", "medium")
    if confidence not in CONFIDENCE:
        confidence = "medium"

    check_references(text, ctx, index, "answer")
    for u in uncertain:
        check_references(u, ctx, index, "uncertain_points")

    share = _telugu_share(text)
    if language == "te" and share < 0.5:
        raise ValidationFailed('"answer" must be written in Telugu script')
    if language == "en" and share > 0.05:
        raise ValidationFailed('"answer" must be written in English')

    citations: list[Citation] = []
    for c in raw_citations:
        if isinstance(c, str):
            c = {"verse": c}
        if isinstance(c, dict) and isinstance(c.get("verse"), str):
            vid = c["verse"].strip().removeprefix("BG").strip()
            citations.append(Citation(vid, str(c.get("source_id") or "")))

    answer = Answer(text, citations, confidence, uncertain, out_of_scope)
    if not out_of_scope:
        cited = {c.verse for c in citations} | {r.id for r in verse_refs(text)}
        if not cited & set(ctx.verse_ids):
            raise ValidationFailed(
                "cite at least one of the passages you were given "
                f"({', '.join(ctx.verse_ids) or 'none'}), or set out_of_scope"
            )
    return answer


def finalize(answer: Answer, ctx: Context, index: VerseIndex, sanskrit_source: dict[str, str]) -> Answer:
    kept: list[Citation] = []
    removed = 0
    for c in answer.citations:
        if c.verse not in index.ids or c.verse not in ctx.verse_ids:
            removed += 1
            continue
        allowed = ctx.sources_for(c.verse)
        source = c.source_id if c.source_id in allowed else sanskrit_source[c.verse]
        if all(k.verse != c.verse for k in kept):
            kept.append(Citation(c.verse, source))
    if removed:
        answer.flags.append("citations_removed")
    for r in verse_refs(answer.text):
        if all(k.verse != r.id for k in kept):
            kept.append(Citation(r.id, sanskrit_source[r.id]))
    answer.citations = [] if answer.out_of_scope else kept

    text, unverified = unquote_unverified(answer.text, [p.text for p in ctx.passages])
    if unverified:
        answer.text = text
        answer.flags.append("unverified_quotes")
    return answer


# Straight and curly double quotes, and Telugu/Indic usage of the same marks.
# Single quotes are skipped: they are also apostrophes.
_QUOTE = re.compile(r"[\"“”„]([^\"“”„\n]{8,400})[\"“”„]")


def _norm(s: str) -> str:
    s = unicodedata.normalize("NFC", s).lower()
    s = re.sub(r"[।॥|.,;:!?'\"“”‘’()\[\]\-–—]", " ", s)
    return " ".join(s.split())


def quote_matches(quote: str, sources: list[str], threshold: float = 0.88) -> bool:
    q = _norm(quote)
    if not q:
        return True
    for src in sources:
        s = _norm(src)
        if q in s:
            return True
        n = len(q)
        if n > len(s) + 10:
            continue
        step = max(1, n // 6)
        for i in range(0, max(1, len(s) - n + 1), step):
            if SequenceMatcher(None, q, s[i : i + n]).ratio() >= threshold:
                return True
    return False


def unquote_unverified(text: str, sources: list[str]) -> tuple[str, int]:
    """Remove quotation marks around quotes that match no passage. Short
    quoted words (fewer than 3 words) are left alone: they are terms, not
    quotations."""
    count = 0

    def fix(m: re.Match) -> str:
        nonlocal count
        inner = m.group(1)
        if len(inner.split()) < 3 or quote_matches(inner, sources):
            return m.group(0)
        count += 1
        return inner

    return _QUOTE.sub(fix, text), count
