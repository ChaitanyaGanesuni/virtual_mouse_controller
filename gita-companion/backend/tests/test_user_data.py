import time
import uuid
from datetime import UTC, datetime, timedelta

import pytest
from sqlalchemy import func, select, text
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from app.modules.ai_tutor.models import AIConversation, AIMessage
from app.modules.audio.models import AudioAsset, AudioChunk, AudioManifest
from app.modules.auth.models import AppUser, UserSettings
from app.modules.practice.models import DailyPractice
from app.modules.progress.models import ListeningProgress
from app.modules.rag.models import EMBEDDING_DIM, EmbeddingDoc
from app.modules.study.models import Bookmark, Highlight, Note, RevisionItem, RevisionReview


@pytest.fixture
def user(session) -> AppUser:
    u = AppUser(auth_provider="anonymous", external_subject=f"device-{uuid.uuid4()}")
    session.add(u)
    session.flush()
    return u


def flush_fails(session, obj, match):
    session.add(obj)
    with pytest.raises(IntegrityError, match=match):
        session.flush()


def test_settings_defaults_and_independent_languages(session, user):
    s = UserSettings(user_id=user.id, ui_language="en", verse_script="sa-Telu", explanation_language="te")
    session.add(s)
    session.flush()
    session.refresh(s)
    assert (s.theme, s.text_scale, s.translation_language) == ("system", 1.0, "en")


def test_settings_reject_unknown_script(session, user):
    flush_fails(
        session, UserSettings(user_id=user.id, verse_script="klingon"), "ck_user_settings_verse_script"
    )


def test_one_bookmark_row_per_verse(session, user):
    """Deleting a bookmark sets deleted_at; bookmarking again clears it, so
    two devices syncing the same verse meet on one row."""
    b = Bookmark(user_id=user.id, verse_id="2.47")
    session.add(b)
    session.flush()
    b.deleted_at = datetime.now(UTC)
    session.flush()
    flush_fails(session, Bookmark(user_id=user.id, verse_id="2.47"), "uq_bookmark_user_id_verse_id")


def test_highlight_range_must_be_valid(session, user):
    flush_fails(
        session,
        Highlight(user_id=user.id, verse_id="2.47", start_offset=10, end_offset=10),
        "ck_highlight_valid_range",
    )


def test_note_has_at_most_one_anchor(session, user):
    flush_fails(session, Note(user_id=user.id, verse_id="2.47", chapter=2, body="x"), "ck_note_single_anchor")


def test_listening_progress_resume_fields(session, user):
    session.add(AudioManifest(id="ch2-recitation-sa-v1", scope="recitation", chapter=2, language="sa"))
    session.flush()
    p = ListeningProgress(
        user_id=user.id,
        manifest_id="ch2-recitation-sa-v1",
        manifest_version=1,
        chapter=2,
        verse_id="2.14",
        audio_chunk_id="ch2-recitation-sa-v1/c0014",
        position_seconds=3.5,
        speed=1.25,
    )
    session.add(p)
    session.flush()
    p.speed = 1.3
    with pytest.raises(IntegrityError, match="ck_listening_progress_speed_allowed"):
        session.flush()


def test_audio_asset_hash_must_be_sha256(session):
    flush_fails(
        session,
        AudioAsset(
            audio_hash="abc",
            provider="device",
            provider_version="1",
            voice_id="v",
            language="en",
            codec="wav",
            storage_key="k",
        ),
        "ck_audio_asset_hash_is_sha256",
    )


def test_audio_chunks_are_ordered_and_cascade(session):
    session.add(AudioManifest(id="m1", scope="verse", verse_id="2.47", language="en"))
    session.flush()
    session.add_all(
        [
            AudioChunk(id="m1/c0", manifest_id="m1", seq=0, text="a", est_seconds=2.0),
            AudioChunk(id="m1/c1", manifest_id="m1", seq=1, text="b", est_seconds=2.0),
        ]
    )
    session.flush()
    flush_fails(
        session,
        AudioChunk(id="m1/c1b", manifest_id="m1", seq=1, text="dup", est_seconds=1.0),
        "uq_audio_chunk_manifest_id",
    )
    session.rollback()


def test_revision_rating_range(session, user):
    item = RevisionItem(
        user_id=user.id, verse_id="2.47", card_type="meaning", due_at=datetime.now(UTC) + timedelta(days=1)
    )
    session.add(item)
    session.flush()
    flush_fails(session, RevisionReview(item_id=item.id, rating=5), "ck_revision_review_rating_range")


def test_one_daily_practice_per_day(session, user):
    today = datetime.now(UTC).date()
    session.add(DailyPractice(user_id=user.id, practice_date=today, verse_id="2.47"))
    session.flush()
    flush_fails(
        session,
        DailyPractice(user_id=user.id, practice_date=today, verse_id="3.19"),
        "uq_daily_practice_user_id",
    )


def test_assistant_message_must_record_model(session, user):
    conv = AIConversation(user_id=user.id, pinned_verse_id="2.47", mode="practical")
    session.add(conv)
    session.flush()
    flush_fails(
        session,
        AIMessage(conversation_id=conv.id, role="assistant", content="..."),
        "ck_ai_message_assistant_has_model",
    )


def test_deleting_user_cascades(session, user):
    session.add_all(
        [
            UserSettings(user_id=user.id),
            Bookmark(user_id=user.id, verse_id="1.1"),
            Note(user_id=user.id, verse_id="1.1", body="x"),
        ]
    )
    session.flush()
    uid = user.id
    session.execute(text("delete from app_user where id = :id"), {"id": uid})
    session.expunge_all()
    for model in (UserSettings, Bookmark, Note):
        assert session.scalar(select(func.count()).select_from(model).where(model.user_id == uid)) == 0


def test_vector_search_and_generated_tsvector(session):
    def vec(i: int) -> list[float]:
        v = [0.0] * EMBEDDING_DIM
        v[i] = 1.0
        return v

    for i, vid in enumerate(["2.47", "2.48", "3.19"]):
        session.add(
            EmbeddingDoc(
                id=uuid.uuid4(),
                verse_id=vid,
                facet="translation",
                language="en",
                source_id="gita-companion-editorial",
                body=f"verse {vid} about action",
                embedding=vec(i),
                embedding_model="test",
            )
        )
    session.flush()
    nearest = session.scalars(
        select(EmbeddingDoc.verse_id).order_by(EmbeddingDoc.embedding.cosine_distance(vec(1))).limit(1)
    ).one()
    assert nearest == "2.48"
    hits = session.scalars(
        select(EmbeddingDoc.verse_id).where(
            EmbeddingDoc.tsv.op("@@")(func.plainto_tsquery("simple", "action"))
        )
    ).all()
    assert len(hits) == 3


def test_updated_at_is_maintained_by_trigger(seeded):
    with Session(seeded) as s, s.begin():
        u = AppUser(auth_provider="anonymous", external_subject=f"device-{uuid.uuid4()}")
        s.add(u)
        s.flush()
        uid, created = u.id, u.updated_at
    try:
        time.sleep(0.01)
        with Session(seeded) as s, s.begin():
            s.execute(text("update app_user set display_name = 'x' where id = :id"), {"id": uid})
        with Session(seeded) as s:
            assert s.get(AppUser, uid).updated_at > created
    finally:
        with Session(seeded) as s, s.begin():
            s.execute(text("delete from app_user where id = :id"), {"id": uid})
