"""Retrieval: which passages the tutor may use to answer.

Sources of candidate verses, in priority order:
1. the verse the conversation is pinned to, with its neighbours;
2. verses and chapters named in the question ("2.47", "chapter 3"), and
   verses cited earlier in the conversation;
3. hybrid search (gita_content.retrieval): the concept index, keywords in
   the translation and explanations, Sanskrit typed in Roman letters, and,
   when an embedding model is configured, vector search;
4. only if 1-3 found nothing: verse numbers suggested by the model
   itself. The model then sees the real text of those verses, and the
   answer may cite only what it was shown.

Every passage carries an ID like "BG 2.47 | sanskrit | bg-sanskrit-gita-json".
The answer validator accepts citations only of verses passed here.
"""

from __future__ import annotations

from collections.abc import Callable
from dataclasses import dataclass, field

from gita_content.retrieval import Retriever
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.modules.ai_tutor.refs import chapter_refs, verse_refs
from app.modules.content.models import Chapter, ChapterText, Source, Verse, VerseText

MAX_VERSES = 8
HYBRID_LIMIT = 6  # 3 when the conversation is about one verse
SUGGEST_LIMIT = 5

# Text kinds the tutor may read, best first. Transliteration helps the model
# read the Sanskrit; explanations are AI-written and labelled as such.
TEXT_KINDS = ("translation", "literal_translation", "simple", "practical", "deep", "commentary")
SEARCHABLE_KINDS = (*TEXT_KINDS, "story", "child")


@dataclass(frozen=True)
class Passage:
    pid: str
    verse_id: str | None
    chapter: int
    kind: str
    language: str
    source_id: str
    text: str
    is_ai: bool


@dataclass
class Context:
    passages: list[Passage] = field(default_factory=list)
    verse_ids: list[str] = field(default_factory=list)
    methods: list[str] = field(default_factory=list)

    def sources_for(self, verse_id: str) -> set[str]:
        return {p.source_id for p in self.passages if p.verse_id == verse_id}


@dataclass(frozen=True)
class VerseIndex:
    """The canonical verse table, loaded once per process."""

    ids: frozenset[str]
    chapter_counts: dict[int, int]

    @staticmethod
    def load(session: Session) -> VerseIndex:
        ids = frozenset(session.scalars(select(Verse.id)))
        counts = {n: c for n, c in session.execute(select(Chapter.number, Chapter.verse_count))}
        return VerseIndex(ids, counts)

    def neighbours(self, verse_id: str) -> list[str]:
        ch, v = (int(x) for x in verse_id.split("."))
        return [f"{ch}.{n}" for n in (v - 1, v + 1) if f"{ch}.{n}" in self.ids]


def build_context(
    session: Session,
    index: VerseIndex,
    question: str,
    *,
    pinned_verse_id: str | None,
    language: str,
    carry: list[str] | None = None,
    hybrid: Retriever | None = None,
    vector: Callable[[str], list[str]] | None = None,
    suggest: Callable[[str], list[str]] | None = None,
) -> Context:
    """`carry`: verses cited earlier in the conversation, so follow-up
    questions ("and the next verse?") can still refer to them."""
    ctx = Context()

    def add(ids: list[str], method: str) -> None:
        added = False
        for vid in ids:
            if vid in index.ids and vid not in ctx.verse_ids and len(ctx.verse_ids) < MAX_VERSES:
                ctx.verse_ids.append(vid)
                added = True
        if added and method not in ctx.methods:
            ctx.methods.append(method)

    if pinned_verse_id:
        add([pinned_verse_id, *index.neighbours(pinned_verse_id)], "pinned")
    add([r.id for r in verse_refs(question)], "explicit")
    add(list(reversed(carry or [])), "conversation")
    chapters = [c for c in chapter_refs(question) if c in index.chapter_counts]
    if hybrid is not None:
        extra = {"vector": vector(question)} if vector is not None else None
        limit = HYBRID_LIMIT // 2 if pinned_verse_id else HYBRID_LIMIT
        add([h.verse_id for h in hybrid.search(question, k=limit, extra=extra)], "hybrid")
    if suggest is not None and not ctx.verse_ids and not chapters:
        add(suggest(question)[:SUGGEST_LIMIT], "suggested")

    ctx.passages = _verse_passages(session, ctx.verse_ids, language) + _chapter_passages(
        session, chapters, language
    )
    return ctx


def _verse_passages(session: Session, verse_ids: list[str], language: str) -> list[Passage]:
    if not verse_ids:
        return []
    ai_sources = set(session.scalars(select(Source.id).where(Source.is_ai_generated)))
    verses = {v.id: v for v in session.scalars(select(Verse).where(Verse.id.in_(verse_ids)))}
    texts = session.scalars(
        select(VerseText).where(
            VerseText.verse_id.in_(verse_ids),
            (VerseText.kind.in_(TEXT_KINDS) & VerseText.language.in_({language, "en"}))
            | ((VerseText.kind == "transliteration") & (VerseText.language == "sa-Latn")),
        )
    ).all()
    by_verse: dict[str, list[VerseText]] = {}
    for t in texts:
        by_verse.setdefault(t.verse_id, []).append(t)

    order = {k: i for i, k in enumerate(("transliteration", *TEXT_KINDS))}
    out: list[Passage] = []
    for vid in verse_ids:
        v = verses[vid]
        out.append(
            Passage(
                f"BG {vid} | sanskrit | {v.source_id}",
                vid,
                v.chapter,
                "sanskrit",
                "sa",
                v.source_id,
                v.sanskrit,
                False,
            )
        )
        chosen = sorted(
            by_verse.get(vid, []),
            # The requested language first, then English; then by kind.
            key=lambda t: (order[t.kind], t.language != language),
        )
        seen_kinds: set[tuple[str, str]] = set()
        for t in chosen:
            if (t.kind, t.language) in seen_kinds or len(seen_kinds) >= 4:
                continue
            seen_kinds.add((t.kind, t.language))
            out.append(
                Passage(
                    f"BG {vid} | {t.kind} | {t.source_id}",
                    vid,
                    v.chapter,
                    t.kind,
                    t.language,
                    t.source_id,
                    t.body,
                    t.source_id in ai_sources,
                )
            )
    return out


def _chapter_passages(session: Session, chapters: list[int], language: str) -> list[Passage]:
    if not chapters:
        return []
    ai_sources = set(session.scalars(select(Source.id).where(Source.is_ai_generated)))
    rows = session.scalars(
        select(ChapterText)
        .where(
            ChapterText.chapter.in_(chapters[:2]),
            ChapterText.kind.in_(("title", "theme", "summary")),
            ChapterText.language.in_({language, "en"}),
        )
        .order_by(ChapterText.chapter, ChapterText.kind)
    ).all()
    return [
        Passage(
            f"BG chapter {t.chapter} | {t.kind} | {t.source_id}",
            None,
            t.chapter,
            t.kind,
            t.language,
            t.source_id,
            t.body,
            t.source_id in ai_sources,
        )
        for t in rows
    ]
