import uuid

import pytest
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.content.models import Chapter, ContentRelease, Verse, VerseAlias, VerseText
from app.modules.content.seed import ContentImportError, import_dataset


def count(session, model) -> int:
    return session.scalar(select(func.count()).select_from(model))


def test_import_counts(session, dataset):
    assert count(session, Verse) == 701
    assert count(session, Chapter) == 18
    assert count(session, VerseText) == 701 * 2
    assert count(session, VerseAlias) == 35
    release = session.get(ContentRelease, dataset["content_hash"])
    assert release is not None and release.verse_count == 701


def test_import_is_idempotent(session, dataset):
    import_dataset(session, dataset)
    session.flush()
    assert count(session, Verse) == 701
    assert count(session, VerseText) == 701 * 2


def test_import_rejects_unknown_format(session, dataset):
    with pytest.raises(ContentImportError):
        import_dataset(session, {**dataset, "format": "something-else/9"})


def test_verse_and_texts(session):
    v = session.get(Verse, "2.47")
    assert v.chapter_ref.verse_count == 72
    assert v.sanskrit.startswith("कर्मण्येवाधिकारस्ते")
    by_lang = {t.language: t.body for t in v.texts}
    assert by_lang["sa-Latn"].startswith("karmaṇyevādhikāraste")
    assert by_lang["sa-Telu"].startswith("కర్మణ్యేవాధికారస్తే")
    assert len(session.get(Chapter, 2).verses) == 72


def test_alias_resolves_701_numbering(session):
    assert session.get(VerseAlias, ("edition-701", "13.2")).verse_id == "13.1"


def _insert_verse(session: Session, vid: str, chapter: int, verse: int, canonical: bool = True):
    session.add(
        Verse(
            id=vid,
            chapter=chapter,
            verse=verse,
            is_canonical=canonical,
            sanskrit="x",
            source_id="bg-sanskrit-gita-json",
            review_status="unreviewed",
        )
    )
    session.flush()


@pytest.mark.parametrize(
    "vid,chapter,verse,canonical,error",
    [
        ("2.73", 2, 73, True, "outside chapter 2"),  # beyond the chapter's verse count (trigger)
        ("19.1", 19, 1, True, "fk_verse_chapter_chapter"),  # no chapter 19
        ("2.0", 2, 0, True, "outside chapter 2"),  # verse 0 must be non-canonical
        ("2.5", 2, 50, True, "ck_verse_id_matches_ref"),  # id must equal chapter.verse
        ("2.80", 2, 80, False, "ck_verse_only_verse_zero_noncanonical"),
    ],
)
def test_invalid_verses_are_rejected(session, vid, chapter, verse, canonical, error):
    with pytest.raises(IntegrityError, match=error):
        _insert_verse(session, vid, chapter, verse, canonical)


def test_verse_text_kind_and_status_are_checked(session):
    session.add(
        VerseText(
            id=uuid.uuid4(),
            verse_id="2.47",
            source_id="gita-companion-editorial",
            kind="gossip",
            language="en",
            body="x",
            review_status="unreviewed",
        )
    )
    with pytest.raises(IntegrityError, match="ck_verse_text_kind"):
        session.flush()


def test_one_text_per_verse_source_kind_language(session):
    existing = session.scalars(select(VerseText).where(VerseText.verse_id == "2.47")).first()
    session.add(
        VerseText(
            id=uuid.uuid4(),
            verse_id="2.47",
            source_id=existing.source_id,
            kind=existing.kind,
            language=existing.language,
            body="duplicate",
            review_status="unreviewed",
        )
    )
    with pytest.raises(IntegrityError, match="uq_verse_text"):
        session.flush()


def test_text_requires_registered_source(session):
    session.add(
        VerseText(
            id=uuid.uuid4(),
            verse_id="2.47",
            source_id="not-registered",
            kind="translation",
            language="en",
            body="x",
            review_status="unreviewed",
        )
    )
    with pytest.raises(IntegrityError, match="fk_verse_text_source_id_source"):
        session.flush()


def test_review_status_survives_import(session):
    statuses = dict(
        session.execute(text("select id, review_status from verse where id in ('1.1','16.20')")).all()
    )
    assert statuses == {"1.1": "unreviewed", "16.20": "pending"}


def test_import_ai_source_and_word_meanings(session, dataset):
    import copy

    from app.modules.content.models import Source, WordMeaning

    ds = copy.deepcopy(dataset)
    ai = {
        "id": "ai-groq-test-model-verse-explain-v1",
        "kind": "ai",
        "title": "AI",
        "author": "test-model via groq",
        "year": None,
        "language": "mul",
        "license": "AI-generated text",
        "license_note": "",
        "url": None,
        "retrieved_commit": None,
        "is_ai_generated": True,
        "model_id": "test-model",
        "prompt_version": "verse-explain-v1",
    }
    ds["sources"].append(ai)
    v = next(v for v in ds["verses"] if v["id"] == "2.47")
    v["word_meanings"] = [
        {
            "id": str(uuid.uuid4()),
            "source_id": ai["id"],
            "language": "en",
            "position": 0,
            "word": "karmaṇi",
            "meaning": "in action",
        },
    ]
    import_dataset(session, ds)
    session.flush()
    src = session.get(Source, ai["id"])
    assert src.is_ai_generated and src.model_id == "test-model"
    w = session.scalars(select(WordMeaning).where(WordMeaning.verse_id == "2.47")).one()
    assert (w.word_sa, w.meaning) == ("karmaṇi", "in action")
