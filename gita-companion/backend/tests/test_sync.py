"""Study-data sync and account recovery over HTTP."""

from __future__ import annotations

import json
import uuid
from datetime import UTC, datetime, timedelta
from pathlib import Path

import pytest
from cryptography.exceptions import InvalidTag
from sqlalchemy import text

from app.core.crypto import FieldCipher
from app.core.settings import Settings, SettingsError
from tests.conftest import signup

KEY = "k" * 40


def ts(minutes: float = 0) -> str:
    base = datetime(2026, 1, 6, 8, 0, tzinfo=UTC)
    return (base + timedelta(minutes=minutes)).isoformat()


def sync(client, tokens, changes=None, cursor=0, status=200) -> dict:
    r = client.post("/v1/sync", json={"cursor": cursor, "changes": changes or {}}, headers=tokens["headers"])
    assert r.status_code == status, r.text
    return r.json()


def pull_all(client, tokens) -> dict:
    out: dict[str, list] = {}
    cursor, more = 0, True
    while more:
        body = sync(client, tokens, cursor=cursor)
        for k, v in body["changes"].items():
            out.setdefault(k, []).extend(v)
        cursor, more = body["cursor"], body["more"]
    return out


def recover(client, code) -> dict:
    r = client.post("/v1/auth/recover", json={"recovery_code": code})
    assert r.status_code == 200, r.text
    t = r.json()
    t["headers"] = {"Authorization": f"Bearer {t['access_token']}"}
    return t


@pytest.fixture
def text_id(dataset) -> str:
    """A verse_text id of 2.47 (same in the app's pack and on the server)."""
    v = next(v for v in dataset["verses"] if v["id"] == "2.47")
    return next(t["id"] for t in v["texts"] if t["kind"] == "translation")


def full_changes(text_id: str) -> dict:
    note_id, hl_id, review_id = (str(uuid.uuid4()) for _ in range(3))
    return {
        "bookmark": [{"verse_id": "2.47", "updated_at": ts()}],
        "verse_state": [{"verse_id": "2.47", "favorite": True, "needs_revision": True, "updated_at": ts()}],
        "highlight": [
            {"id": hl_id, "verse_id": "2.47", "text_id": text_id, "start": 4, "end": 20, "updated_at": ts()}
        ],
        "note": [
            {
                "id": note_id,
                "verse_id": "2.47",
                "kind": "question",
                "body": "Why no fruits?",
                "updated_at": ts(),
            }
        ],
        "revision_item": [
            {
                "verse_id": "2.47",
                "card_type": "meaning",
                "step": 2,
                "due_at": ts(60 * 24 * 4),
                "updated_at": ts(),
            }
        ],
        "revision_review": [
            {"id": review_id, "verse_id": "2.47", "card_type": "meaning", "rating": 3, "reviewed_at": ts()}
        ],
        "daily_practice": [
            {
                "date": "2026-10-06",
                "verse_id": "2.47",
                "listened_at": ts(),
                "journal": "Calm today.",
                "updated_at": ts(),
            }
        ],
        "verse_read": [{"verse_id": "2.47", "first_read_at": ts(), "last_read_at": ts(5), "read_count": 2}],
        "reading_progress": [{"chapter": 2, "last_verse_id": "2.47", "updated_at": ts()}],
    }


def test_data_survives_reinstall_with_the_recovery_code(make_client, seeded, text_id):
    """The Phase 8 exit criterion, over HTTP: device 1 syncs everything;
    a new installation signs in with the recovery code and gets it all back."""
    client, _ = make_client(data_encryption_key=KEY)
    phone = signup(client)
    sent = full_changes(text_id)
    body = sync(client, phone, sent)
    assert body["applied"] == 9 and body["rejected"] == 0

    code = client.post("/v1/auth/recovery-code", headers=phone["headers"]).json()["recovery_code"]
    assert len(code) == 29 and code.count("-") == 5

    # Reinstall: a fresh anonymous account first, then recovery.
    signup(client)
    restored = recover(client, code.lower().replace("-", " "))
    assert restored["user_id"] == phone["user_id"]
    got = pull_all(client, restored)
    assert [b["verse_id"] for b in got["bookmark"]] == ["2.47"]
    assert got["verse_state"][0]["favorite"] and got["verse_state"][0]["needs_revision"]
    hl = got["highlight"][0]
    assert (hl["id"], hl["text_id"], hl["start"], hl["end"], hl["color"]) == (
        sent["highlight"][0]["id"],
        text_id,
        4,
        20,
        "gold",
    )
    assert got["note"][0]["body"] == "Why no fruits?" and got["note"][0]["kind"] == "question"
    assert got["revision_item"][0]["step"] == 2
    assert got["revision_review"][0]["rating"] == 3
    assert got["daily_practice"][0]["journal"] == "Calm today."
    assert got["verse_read"][0]["read_count"] == 2
    assert got["reading_progress"][0]["last_verse_id"] == "2.47"

    # Private text is encrypted at rest.
    with seeded.connect() as c:
        body_db = c.execute(
            text("SELECT body FROM note WHERE id = :i"), {"i": sent["note"][0]["id"]}
        ).scalar()
        journal_db = c.execute(
            text("SELECT journal_text FROM daily_practice WHERE user_id = :u"), {"u": phone["user_id"]}
        ).scalar()
    assert body_db.startswith("v1:") and "fruits" not in body_db
    assert journal_db.startswith("v1:") and "Calm" not in journal_db


def test_recovery_codes(make_client):
    client, _ = make_client()
    t = signup(client)
    first = client.post("/v1/auth/recovery-code", headers=t["headers"]).json()["recovery_code"]
    second = client.post("/v1/auth/recovery-code", headers=t["headers"]).json()["recovery_code"]
    assert first != second
    # A new code replaces the old one.
    assert client.post("/v1/auth/recover", json={"recovery_code": first}).status_code == 401
    assert recover(client, second)["user_id"] == t["user_id"]
    # Letters that look alike are read the same way (O as 0, I/L as 1).
    assert recover(client, second.replace("0", "O").replace("1", "l"))["user_id"] == t["user_id"]
    bad = client.post("/v1/auth/recover", json={"recovery_code": "AAAA-AAAA-AAAA-AAAA-AAAA-AAAA"})
    assert bad.status_code == 401
    assert client.post("/v1/auth/recovery-code").status_code == 401  # needs sign-in
    # A deleted account cannot be recovered.
    client.delete("/v1/me", headers=t["headers"])
    assert client.post("/v1/auth/recover", json={"recovery_code": second}).status_code == 401


def test_last_write_wins_and_the_loser_gets_the_winner(make_client):
    client, _ = make_client()
    a = signup(client)
    note = str(uuid.uuid4())
    sync(client, a, {"note": [{"id": note, "body": "v2", "updated_at": ts(10)}]})
    cursor = sync(client, a)["cursor"]

    # An older edit arrives later (offline device): rejected, and the server
    # version is sent back even though it is before the cursor.
    body = sync(client, a, {"note": [{"id": note, "body": "v1", "updated_at": ts(5)}]}, cursor=cursor)
    assert body["rejected"] == 1
    assert [n["body"] for n in body["changes"]["note"]] == ["v2"]

    body = sync(client, a, {"note": [{"id": note, "body": "v3", "updated_at": ts(20)}]}, cursor=cursor)
    assert body["applied"] == 1 and [n["body"] for n in body["changes"]["note"]] == ["v3"]


def test_clock_in_the_future_is_clamped(make_client):
    client, _ = make_client()
    a = signup(client)
    future = (datetime.now(UTC) + timedelta(days=365)).isoformat()
    sync(client, a, {"bookmark": [{"verse_id": "3.19", "updated_at": future}]})
    got = pull_all(client, a)["bookmark"][0]
    assert datetime.fromisoformat(got["updated_at"]) < datetime.now(UTC) + timedelta(minutes=6)
    # A normal later edit (unbookmarking) still wins.
    now = datetime.now(UTC) + timedelta(minutes=10)
    sync(client, a, {"bookmark": [{"verse_id": "3.19", "updated_at": now.isoformat(), "deleted": True}]})
    assert pull_all(client, a)["bookmark"][0]["deleted"] is True


def test_deletions_reach_other_devices_and_bookmarks_meet_on_one_row(make_client):
    client, _ = make_client()
    a = signup(client)
    code = client.post("/v1/auth/recovery-code", headers=a["headers"]).json()["recovery_code"]
    b = recover(client, code)
    sync(client, a, {"bookmark": [{"verse_id": "2.47", "updated_at": ts(1)}]})
    sync(client, b, {"bookmark": [{"verse_id": "2.47", "updated_at": ts(2)}]})  # same verse, other device
    cursor_b = sync(client, b)["cursor"]
    sync(client, a, {"bookmark": [{"verse_id": "2.47", "updated_at": ts(3), "deleted": True}]})
    body = sync(client, b, cursor=cursor_b)
    assert [(x["verse_id"], x["deleted"]) for x in body["changes"]["bookmark"]] == [("2.47", True)]
    assert len(pull_all(client, a)["bookmark"]) == 1


def test_paging_returns_every_change_once(make_client):
    client, _ = make_client()
    a = signup(client)
    notes = [{"id": str(uuid.uuid4()), "body": f"n{i}", "updated_at": ts(i)} for i in range(620)]
    sync(client, a, {"note": notes[:400]})
    sync(client, a, {"note": notes[400:]})
    first = sync(client, a)
    assert first["more"] is True and len(first["changes"]["note"]) == 500
    second = sync(client, a, cursor=first["cursor"])
    assert second["more"] is False
    ids = [n["id"] for n in first["changes"]["note"] + second["changes"]["note"]]
    assert sorted(ids) == sorted(n["id"] for n in notes)
    assert sync(client, a, cursor=second["cursor"])["changes"]["note"] == []


def test_accounts_are_isolated(make_client):
    client, _ = make_client()
    a, b = signup(client), signup(client)
    note = str(uuid.uuid4())
    sync(client, a, {"note": [{"id": note, "body": "mine", "updated_at": ts()}]})
    # B guesses A's note id: nothing is overwritten and nothing leaks back.
    body = sync(client, b, {"note": [{"id": note, "body": "stolen", "updated_at": ts(60)}]})
    assert body["rejected"] == 1 and body["changes"]["note"] == []
    assert [n["body"] for n in pull_all(client, a)["note"]] == ["mine"]
    assert pull_all(client, b).get("note") == []


def test_invalid_references_are_rejected(make_client, text_id):
    client, _ = make_client()
    a = signup(client)
    body = sync(
        client,
        a,
        {
            "bookmark": [{"verse_id": "2.73", "updated_at": ts()}],  # no such verse
            # A text of 2.47 cannot be highlighted on 3.19.
            "highlight": [
                {
                    "id": str(uuid.uuid4()),
                    "verse_id": "3.19",
                    "text_id": text_id,
                    "start": 0,
                    "end": 3,
                    "updated_at": ts(),
                }
            ],
            "reading_progress": [{"chapter": 3, "last_verse_id": "2.47", "updated_at": ts()}],
            "revision_review": [
                {
                    "id": str(uuid.uuid4()),
                    "verse_id": "2.47",
                    "card_type": "concept",
                    "rating": 2,
                    "reviewed_at": ts(),
                }
            ],
        },
    )
    assert body["applied"] == 0 and body["rejected"] == 4
    bad_range = {
        "highlight": [{"id": str(uuid.uuid4()), "verse_id": "2.47", "start": 5, "end": 5, "updated_at": ts()}]
    }
    assert sync(client, a, bad_range, status=422)["error"]["code"] == "invalid_request"
    both = {
        "note": [{"id": str(uuid.uuid4()), "verse_id": "2.47", "chapter": 2, "body": "x", "updated_at": ts()}]
    }
    sync(client, a, both, status=422)
    naive = {"bookmark": [{"verse_id": "2.47", "updated_at": "2026-10-06T08:00:00"}]}
    sync(client, a, naive, status=422)


def test_reading_history_merges(make_client):
    client, _ = make_client()
    a = signup(client)
    sync(
        client,
        a,
        {
            "verse_read": [
                {"verse_id": "2.47", "first_read_at": ts(10), "last_read_at": ts(10), "read_count": 3}
            ]
        },
    )
    sync(
        client,
        a,
        {
            "verse_read": [
                {"verse_id": "2.47", "first_read_at": ts(0), "last_read_at": ts(5), "read_count": 1}
            ]
        },
    )
    got = pull_all(client, a)["verse_read"][0]
    assert got["first_read_at"].startswith("2026-01-06T08:00") and got["last_read_at"].startswith(
        "2026-01-06T08:10"
    )
    assert got["read_count"] == 3


def test_journal_stays_unless_sent_and_can_be_erased(make_client):
    client, _ = make_client()
    a = signup(client)
    day = {"date": "2026-10-06", "verse_id": "2.47"}
    sync(client, a, {"daily_practice": [{**day, "journal": "private", "updated_at": ts(1)}]})
    # Journal sync turned off later: the device sends practice without it.
    sync(client, a, {"daily_practice": [{**day, "applied_at": ts(2), "updated_at": ts(2)}]})
    got = pull_all(client, a)["daily_practice"][0]
    assert got["journal"] == "private" and got["applied_at"] is not None
    # Erasing it from the server is explicit.
    sync(client, a, {"daily_practice": [{**day, "journal": None, "updated_at": ts(3)}]})
    assert pull_all(client, a)["daily_practice"][0]["journal"] is None


def test_request_limits(make_client):
    client, _ = make_client(syncs_per_user_per_hour=3)
    a = signup(client)
    many = {"bookmark": [{"verse_id": "2.47", "updated_at": ts()}] * 1001}
    assert sync(client, a, many, status=413)["error"]["code"] == "too_large"
    sync(client, a)
    sync(client, a)
    sync(client, a)
    r = sync(client, a, status=429)
    assert r["error"]["code"] == "rate_limited"
    assert client.post("/v1/sync", json={}).status_code == 401


def test_production_requires_an_encryption_key():
    env = {"APP_ENV": "production", "JWT_SECRET": "s" * 40}
    with pytest.raises(SettingsError, match="DATA_ENCRYPTION_KEY"):
        Settings.from_env(env)
    assert Settings.from_env({**env, "DATA_ENCRYPTION_KEY": KEY}).data_encryption_key == KEY


def test_ciphertext_is_bound_to_its_owner_and_field():
    c = FieldCipher(KEY)
    enc = c.encrypt("hello", owner="u1", field="note.body")
    assert enc != c.encrypt("hello", owner="u1", field="note.body")  # random nonce
    assert c.decrypt(enc, owner="u1", field="note.body") == "hello"
    with pytest.raises(InvalidTag):
        c.decrypt(enc, owner="u2", field="note.body")
    with pytest.raises(InvalidTag):
        c.decrypt(enc, owner="u1", field="daily_practice.journal")
    assert c.decrypt("plain old text", owner="u1", field="note.body") == "plain old text"
    assert FieldCipher(None).encrypt("x", owner="u", field="f") == "x"
    with pytest.raises(RuntimeError):
        FieldCipher(None).decrypt(enc, owner="u1", field="note.body")


def test_the_apps_sync_request_is_accepted(make_client):
    """Contract with the app: fixtures/sync_request_from_app.json is the exact
    request the app sends (written by mobile/test/sync_contract_test.dart).
    Every item must be accepted, and what comes back must carry the fields the
    app reads (the same fields it sends)."""
    sent = json.loads((Path(__file__).parent / "fixtures" / "sync_request_from_app.json").read_text())
    client, _ = make_client(data_encryption_key=KEY)
    a = signup(client)
    body = sync(client, a, sent["changes"])
    total = sum(len(v) for v in sent["changes"].values())
    assert (body["applied"], body["rejected"]) == (total, 0)
    got = pull_all(client, a)
    for collection, records in sent["changes"].items():
        assert len(got[collection]) == len(records), collection
        assert set(got[collection][0]) == set(records[0]), collection
    note = got["note"][0]
    assert note["body"] == sent["changes"]["note"][0]["body"]
    # Times come back as sent (millisecond precision), so the app's
    # "is mine newer?" comparisons see equal times as equal.
    assert (
        note["updated_at"].replace("Z", "+00:00")
        == datetime.fromisoformat(sent["changes"]["note"][0]["updated_at"]).isoformat()
    )
