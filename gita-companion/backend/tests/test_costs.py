"""Cost measurement (Phase 10): what one question, one user and one device
cost in tokens, database space and bandwidth. Printed as COST lines for
docs/PHASE-10.md; the assertions keep the numbers inside the free tiers'
reach (a prompt that quietly doubles fails here).

Token counts are estimates (no tokenizer download from CI's sandbox):
4 characters per token for ASCII and 1.5 for Devanagari/Telugu, which
over-counts for Llama 3's tokenizer. Real counts are stored with every
answer (ai_message.tokens_in/out); `python -m workers.usage_report` prints
them from a deployed database.
"""

from __future__ import annotations

import json
import statistics
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
import yaml
from gita_content.retrieval import Retriever
from sqlalchemy import text
from sqlalchemy.orm import Session

from app.core.crypto import FieldCipher
from app.modules.ai_tutor.prompts import SYSTEM, user_turn
from app.modules.ai_tutor.retrieval import HYBRID_LIMIT, VerseIndex, build_context
from app.modules.auth.models import AppUser
from app.modules.sync.schemas import SyncRequest
from app.modules.sync.service import SyncService

GOLDEN = Path(__file__).resolve().parents[2] / "content" / "eval" / "golden.yaml"
OUTPUT_TOKENS_TYPICAL = 450  # an answer of ~250 words plus JSON; capped at 1400
RESULTS: dict[str, str] = {}


def tokens(s: str) -> int:
    ascii_chars = sum(1 for c in s if ord(c) < 128)
    return round(ascii_chars / 4 + (len(s) - ascii_chars) / 1.5)


@pytest.fixture(scope="module", autouse=True)
def report():
    yield
    for k, v in RESULTS.items():
        print(f"COST {k}: {v}")


def test_tokens_per_question(seeded, dataset):
    retriever = Retriever(dataset)
    questions = yaml.safe_load(GOLDEN.read_text(encoding="utf-8"))["questions"]
    by_lang: dict[str, list[int]] = {"en": [], "te": []}
    with Session(seeded) as s:
        index = VerseIndex.load(s)
        for q in questions:
            lang = q.get("lang", "en")
            ctx = build_context(s, index, q["q"], pinned_verse_id=None, language=lang, hybrid=retriever)
            prompt = SYSTEM + user_turn(q["q"], ctx, mode="free", language=lang, pinned=None)
            by_lang[lang].append(tokens(prompt))
        pinned = build_context(
            s, index, "Explain this verse.", pinned_verse_id="2.47", language="en", hybrid=retriever
        )
        explain = tokens(
            SYSTEM + user_turn("Explain this verse.", pinned, mode="simple", language="en", pinned="2.47")
        )
    for lang, xs in by_lang.items():
        xs.sort()
        RESULTS[f"prompt tokens, free question ({lang}, p50 / p95, {len(xs)} questions)"] = (
            f"{statistics.median(xs):.0f} / {xs[int(0.95 * (len(xs) - 1))]}"
        )
    RESULTS["prompt tokens, explain a pinned verse (en)"] = str(explain)
    p95 = max(xs[int(0.95 * (len(xs) - 1))] for xs in by_lang.values())
    RESULTS["tokens per question (p95 prompt + typical answer)"] = str(p95 + OUTPUT_TOKENS_TYPICAL)
    RESULTS["passages per free question (hybrid limit)"] = str(HYBRID_LIMIT)
    # A prompt must fit comfortably in free-tier per-minute token limits.
    assert p95 < 6000


def _heavy_user_changes(verse_ids: list[str]) -> dict:
    t0 = datetime(2026, 1, 1, tzinfo=UTC)
    iso = lambda d: (t0 + timedelta(minutes=d)).isoformat()  # noqa: E731
    return {
        "bookmark": [{"verse_id": v, "updated_at": iso(i)} for i, v in enumerate(verse_ids[:100])],
        "verse_state": [
            {"verse_id": v, "understood": True, "updated_at": iso(i)} for i, v in enumerate(verse_ids[:300])
        ],
        "note": [
            {
                "id": str(uuid.uuid4()),
                "verse_id": v,
                "body": "A note about this verse. " * 12,
                "updated_at": iso(i),
            }
            for i, v in enumerate(verse_ids[:200])
        ],
        "revision_item": [
            {"verse_id": v, "card_type": c, "due_at": iso(9000), "updated_at": iso(i)}
            for i, v in enumerate(verse_ids[:150])
            for c in ("meaning", "application")
        ],
        "daily_practice": [
            {
                "date": (t0 + timedelta(days=d)).date().isoformat(),
                "verse_id": verse_ids[d],
                "listened_at": iso(d * 1440),
                "journal": "A few lines of reflection for today. " * 4,
                "updated_at": iso(d * 1440),
            }
            for d in range(365)
        ],
        "verse_read": [
            {"verse_id": v, "first_read_at": iso(i), "last_read_at": iso(i + 5), "read_count": 3}
            for i, v in enumerate(verse_ids)
        ],
        "reading_progress": [
            {"chapter": c, "last_verse_id": f"{c}.1", "updated_at": iso(c)} for c in range(1, 19)
        ],
    }


def test_database_and_sync_size_of_a_heavy_user(seeded, dataset):
    """A year of daily use: every verse read, 300 understood, 200 notes, 300
    revision cards, 365 journal entries."""
    verse_ids = [v["id"] for v in dataset["verses"]]
    changes = _heavy_user_changes(verse_ids)
    cipher = FieldCipher("k" * 40)
    users = 10
    with seeded.connect() as c:
        before = c.execute(text("SELECT pg_database_size(current_database())")).scalar()
    upload_bytes = 0
    for _ in range(users):
        with Session(seeded) as s, s.begin():
            user = AppUser(auth_provider="anonymous", external_subject=uuid.uuid4().hex)
            s.add(user)
            s.flush()
            svc = SyncService(s, user.id, cipher, frozenset(verse_ids))
            for name, records in changes.items():
                for i in range(0, len(records), 100):
                    body = {"cursor": 0, "changes": {name: records[i : i + 100]}}
                    upload_bytes += len(json.dumps(body))
                    SyncService(s, user.id, cipher, frozenset(verse_ids)).run(
                        SyncRequest.model_validate(body)
                    )
            # A new phone pulls everything.
            pulled, cursor, more = 0, 0, True
            while more:
                r = svc._pull(cursor)
                pulled += len(json.dumps(r[0]))
                cursor, more = r[1], r[2]
    with seeded.connect() as c:
        c.execute(text("ANALYZE"))
        after = c.execute(text("SELECT pg_database_size(current_database())")).scalar()
    per_user = (after - before) / users
    RESULTS["database space per heavy user (a year of daily use)"] = f"{per_user / 1024:.0f} kB"
    RESULTS["first full sync, upload / download per heavy user"] = (
        f"{upload_bytes / users / 1024:.0f} kB / {pulled / 1024:.0f} kB (before gzip)"
    )
    free = 512 * 1024 * 1024 - before  # Neon free tier: 0.5 GB per project (verify on neon.tech/pricing)
    RESULTS[f"heavy users in 0.5 GB (content and tests use {before / 1e6:.0f} MB)"] = (
        f"~{free / max(per_user, 1):,.0f}"
    )
    assert per_user < 2 * 1024 * 1024


def test_content_and_audio_bandwidth(seeded):
    with seeded.connect() as c:
        content = c.execute(text("SELECT pg_database_size(current_database())")).scalar()
    pack = Path(__file__).resolve().parents[2] / "mobile" / "assets" / "content" / "gita_content_pack.sqlite"
    if pack.exists():
        RESULTS["content update download"] = f"{pack.stat().st_size / 1e6:.1f} MB (only when content changes)"
    RESULTS["test database incl. content and test users"] = f"{content / 1e6:.0f} MB"


def test_usage_report_runs_against_the_schema(migrated_url, monkeypatch, capsys):
    from workers import usage_report

    monkeypatch.setenv("DATABASE_URL", migrated_url)
    assert usage_report.main(["--days", "7"]) == 0
    out = capsys.readouterr().out
    assert "answers by provider" in out and "database size" in out
