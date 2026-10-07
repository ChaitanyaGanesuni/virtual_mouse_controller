"""Vector index of the verses in Postgres/pgvector (optional third channel).

One document per verse and English text (translation, explanations), plus
the names of the concepts the verse is linked to, so that a question in
everyday words lands near the verse that teaches it.

    python -m workers.index_embeddings      # (re)index what is missing or stale
"""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from sqlalchemy import select, text
from sqlalchemy.dialects.postgresql import insert
from sqlalchemy.orm import Session

from app.modules.content.models import ConceptText, VerseConcept, VerseText
from app.modules.rag.models import EmbeddingDoc
from app.providers.embeddings import EmbeddingProvider

INDEXED_KINDS = ("translation", "simple", "practical", "deep")
DOC_NAMESPACE = uuid.UUID("6b7f3f2e-2f6b-4c51-9a55-2f8c2b0a7e11")
MIN_CONCEPT_WEIGHT = 0.5


def verse_documents(session: Session) -> Iterator[dict]:
    names = dict(
        session.execute(
            select(ConceptText.concept_id, ConceptText.name).where(ConceptText.language == "en")
        ).all()
    )
    concepts: dict[str, list[str]] = {}
    for vid, cid, w in session.execute(
        select(VerseConcept.verse_id, VerseConcept.concept_id, VerseConcept.weight)
    ):
        if w >= MIN_CONCEPT_WEIGHT and cid in names:
            concepts.setdefault(vid, []).append(names[cid])
    rows = session.scalars(
        select(VerseText).where(VerseText.kind.in_(INDEXED_KINDS), VerseText.language == "en")
    ).all()
    for t in rows:
        facet = "translation" if t.kind == "translation" else "explanation"
        topics = concepts.get(t.verse_id, [])
        body = t.body + (f"\nTopics: {', '.join(sorted(topics))}." if topics else "")
        yield {
            "id": uuid.uuid5(DOC_NAMESPACE, f"{t.verse_id}|{facet}|{t.kind}|en|{t.source_id}"),
            "verse_id": t.verse_id,
            "facet": facet,
            "language": "en",
            "source_id": t.source_id,
            "body": body,
            "metadata_": {"kind": t.kind, "concepts": sorted(topics)},
        }


def index_embeddings(session: Session, provider: EmbeddingProvider, batch: int = 32, log=print) -> int:
    """Embed every document that is new, changed, or embedded by another model."""
    existing = {
        d.id: (d.body, d.embedding_model)
        for d in session.scalars(select(EmbeddingDoc).where(EmbeddingDoc.verse_id.is_not(None)))
    }
    todo = [d for d in verse_documents(session) if existing.get(d["id"]) != (d["body"], provider.model)]
    for i in range(0, len(todo), batch):
        part = todo[i : i + batch]
        vectors = provider.embed([d["body"] for d in part], "document")
        rows = [
            {**d, "embedding": v, "embedding_model": provider.model}
            for d, v in zip(part, vectors, strict=True)
        ]
        stmt = insert(EmbeddingDoc).values(rows)
        session.execute(
            stmt.on_conflict_do_update(
                index_elements=["id"],
                set_={c: stmt.excluded[c] for c in ("body", "embedding", "embedding_model", "metadata")},
            )
        )
        log(f"embedded {min(i + batch, len(todo))}/{len(todo)}")
    return len(todo)


def exhaustive_hnsw(session: Session) -> None:
    """Let the HNSW index keep scanning until the LIMIT is filled.

    By default it stops after ``ef_search`` candidates, so rows dropped by
    the WHERE filter (another embedding model) can leave too few results.
    Iterative scans (pgvector 0.8+) fix that. Applies to this transaction.
    """
    session.execute(text("SET LOCAL hnsw.iterative_scan = strict_order"))


def vector_search(session: Session, provider: EmbeddingProvider, query: str, k: int = 40) -> list[str]:
    """Verse ids nearest to the query (cosine), best first, one per verse."""
    [vector] = provider.embed([query], "query")
    exhaustive_hnsw(session)
    distance = EmbeddingDoc.embedding.cosine_distance(vector)
    rows = session.execute(
        select(EmbeddingDoc.verse_id, distance.label("d"))
        .where(EmbeddingDoc.embedding.is_not(None), EmbeddingDoc.embedding_model == provider.model)
        .order_by(distance)
        .limit(k * 3)
    ).all()
    out: list[str] = []
    for vid, _ in rows:
        if vid not in out:
            out.append(vid)
    return out[:k]
