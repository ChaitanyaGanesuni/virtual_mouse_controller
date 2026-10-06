"""Two-way sync of study data between devices (one account, many devices).

One request does both directions: the device sends what changed since its
last sync and receives what other devices changed since its cursor.

- Ordering. Every write bumps the row's sync_seq (a database trigger), and a
  device asks for rows with sync_seq > cursor. Syncs of one account are
  serialised with an advisory lock, so a row can never commit with a lower
  sequence number than one a device has already been sent.
- Conflicts. Edits carry the time they were made on the device; the later
  edit wins. Timestamps more than five minutes in the future are clamped to
  the server's clock, so a device with a wrong clock cannot win forever. A
  rejected (older) edit is answered with the server's version, so the device
  converges even if it had already been sent that version.
- Reading history merges instead: earliest first read, latest last read,
  highest count.
- Privacy. Notes and journal text are encrypted at rest (core/crypto.py).
  Ids are checked against the account, so an id belonging to someone else
  is never updated or returned.
"""

from __future__ import annotations

import uuid
from collections.abc import Callable
from datetime import UTC, datetime, timedelta
from typing import Any

from sqlalchemy import Table, and_, func, or_, select, text
from sqlalchemy.dialects.postgresql import insert as pg_insert
from sqlalchemy.orm import Session

from app.core.crypto import FieldCipher
from app.modules.content.models import VerseText
from app.modules.practice.models import DailyPractice
from app.modules.progress.models import ReadingProgress, VerseRead
from app.modules.study.models import Bookmark, Highlight, Note, RevisionItem, RevisionReview, VerseState
from app.modules.sync.schemas import COLLECTIONS, Changes, SyncRequest, SyncResponse

PAGE = 500
MAX_CLOCK_SKEW = timedelta(minutes=5)

T: dict[str, Table] = {
    "bookmark": Bookmark.__table__,
    "verse_state": VerseState.__table__,
    "highlight": Highlight.__table__,
    "note": Note.__table__,
    "revision_item": RevisionItem.__table__,
    "revision_review": RevisionReview.__table__,
    "daily_practice": DailyPractice.__table__,
    "verse_read": VerseRead.__table__,
    "reading_progress": ReadingProgress.__table__,
}


def _iso(t: datetime | None) -> str | None:
    return t.astimezone(UTC).isoformat().replace("+00:00", "Z") if t is not None else None


class SyncService:
    def __init__(self, session: Session, user_id: uuid.UUID, cipher: FieldCipher, verse_ids: frozenset[str]):
        self.s = session
        self.uid = user_id
        self.owner = str(user_id)
        self.cipher = cipher
        self.verse_ids = verse_ids
        self.now = datetime.now(UTC)
        self.applied = 0
        self.rejected = 0
        # (collection, key) of edits that lost to a newer server version.
        self.conflicts: list[tuple[str, tuple]] = []

    # -- entry point -------------------------------------------------------------

    def run(self, req: SyncRequest) -> SyncResponse:
        self.s.execute(text("SELECT pg_advisory_xact_lock(hashtextextended(:k, 0))"), {"k": self.owner})
        self._apply(req.changes)
        changes, cursor, more = self._pull(req.cursor)
        for collection, key in self.conflicts:
            row = self._current(collection, key)
            if row is not None and row not in changes[collection]:
                changes[collection].append(row)
        return SyncResponse(
            cursor=cursor, more=more, changes=changes, applied=self.applied, rejected=self.rejected
        )

    # -- push --------------------------------------------------------------------

    def _ts(self, t: datetime) -> datetime:
        return min(t, self.now + MAX_CLOCK_SKEW)

    def _verse_ok(self, vid: str | None) -> bool:
        return vid is None or vid in self.verse_ids

    def _lww(self, collection: str, key: tuple, values: dict, conflict_cols: list[str], owned: bool = False):
        """Insert, or update if this edit is newer than the stored one."""
        t = T[collection]
        stmt = pg_insert(t).values(**values)
        newer = or_(t.c.client_updated_at.is_(None), stmt.excluded.client_updated_at > t.c.client_updated_at)
        where = and_(t.c.user_id == self.uid, newer) if owned else newer
        update = {c: stmt.excluded[c] for c in values if c not in (*conflict_cols, "user_id")}
        stmt = stmt.on_conflict_do_update(index_elements=conflict_cols, set_=update, where=where)
        # A row comes back only if it was inserted or updated (rowcount is
        # not reliable for INSERT .. ON CONFLICT through SQLAlchemy).
        if self.s.execute(stmt.returning(t.c.sync_seq)).first() is not None:
            self.applied += 1
        else:
            self.rejected += 1
            self.conflicts.append((collection, key))

    def _apply(self, ch: Changes) -> None:
        uid = self.uid
        for r in ch.bookmark:
            if not self._verse_ok(r.verse_id):
                self.rejected += 1
                continue
            ts = self._ts(r.updated_at)
            self._lww(
                "bookmark",
                (r.verse_id,),
                dict(
                    user_id=uid,
                    verse_id=r.verse_id,
                    client_updated_at=ts,
                    deleted_at=ts if r.deleted else None,
                ),
                ["user_id", "verse_id"],
            )
        for r in ch.verse_state:
            if not self._verse_ok(r.verse_id):
                self.rejected += 1
                continue
            self._lww(
                "verse_state",
                (r.verse_id,),
                dict(
                    user_id=uid,
                    verse_id=r.verse_id,
                    is_favorite=r.favorite,
                    is_understood=r.understood,
                    needs_revision=r.needs_revision,
                    client_updated_at=self._ts(r.updated_at),
                ),
                ["user_id", "verse_id"],
            )
        texts = self._text_verses({r.text_id for r in ch.highlight if r.text_id is not None})
        for r in ch.highlight:
            if not self._verse_ok(r.verse_id) or (
                r.text_id is not None and texts.get(r.text_id) != r.verse_id
            ):
                self.rejected += 1
                continue
            ts = self._ts(r.updated_at)
            self._lww(
                "highlight",
                (r.id,),
                dict(
                    id=r.id,
                    user_id=uid,
                    verse_id=r.verse_id,
                    verse_text_id=r.text_id,
                    start_offset=r.start,
                    end_offset=r.end,
                    color=r.color,
                    client_updated_at=ts,
                    deleted_at=ts if r.deleted else None,
                ),
                ["id"],
                owned=True,
            )
        for r in ch.note:
            if not self._verse_ok(r.verse_id):
                self.rejected += 1
                continue
            ts = self._ts(r.updated_at)
            self._lww(
                "note",
                (r.id,),
                dict(
                    id=r.id,
                    user_id=uid,
                    verse_id=r.verse_id,
                    chapter=r.chapter,
                    kind=r.kind,
                    body=self.cipher.encrypt(r.body, owner=self.owner, field="note.body"),
                    client_updated_at=ts,
                    deleted_at=ts if r.deleted else None,
                ),
                ["id"],
                owned=True,
            )
        for r in ch.revision_item:
            if not self._verse_ok(r.verse_id):
                self.rejected += 1
                continue
            ts = self._ts(r.updated_at)
            self._lww(
                "revision_item",
                (r.verse_id, r.card_type),
                dict(
                    user_id=uid,
                    verse_id=r.verse_id,
                    card_type=r.card_type,
                    state=r.state,
                    step=r.step,
                    due_at=r.due_at,
                    reps=r.reps,
                    lapses=r.lapses,
                    last_reviewed_at=r.last_reviewed_at,
                    client_updated_at=ts,
                    deleted_at=ts if r.deleted else None,
                ),
                ["user_id", "verse_id", "card_type"],
            )
        if ch.revision_review:
            items = self._item_ids()
            for r in ch.revision_review:
                item = items.get((r.verse_id, r.card_type))
                if item is None:
                    self.rejected += 1
                    continue
                stmt = pg_insert(T["revision_review"]).values(
                    id=r.id,
                    item_id=item,
                    rating=r.rating,
                    reviewed_at=r.reviewed_at,
                    elapsed_days=r.elapsed_days,
                    scheduled_days=r.scheduled_days,
                )
                # Append-only: a repeated id is a re-send, not an edit.
                self.s.execute(stmt.on_conflict_do_nothing(index_elements=["id"]))
                self.applied += 1
        for r in ch.daily_practice:
            if not self._verse_ok(r.verse_id):
                self.rejected += 1
                continue
            ts = self._ts(r.updated_at)
            values: dict[str, Any] = dict(
                user_id=uid,
                practice_date=r.date,
                verse_id=r.verse_id,
                listened_at=r.listened_at,
                understood_at=r.understood_at,
                reflected_at=r.reflected_at,
                applied_at=r.applied_at,
                client_updated_at=ts,
                deleted_at=ts if r.deleted else None,
            )
            if "journal" in r.model_fields_set:
                values["journal_text"] = self.cipher.encrypt(
                    r.journal or None, owner=self.owner, field="daily_practice.journal"
                )
            self._lww("daily_practice", (r.date,), values, ["user_id", "practice_date"])
        for r in ch.verse_read:
            if not self._verse_ok(r.verse_id):
                self.rejected += 1
                continue
            t = T["verse_read"]
            stmt = pg_insert(t).values(
                user_id=uid,
                verse_id=r.verse_id,
                first_read_at=self._ts(r.first_read_at),
                last_read_at=self._ts(r.last_read_at),
                read_count=r.read_count,
            )
            x = stmt.excluded
            self.s.execute(
                stmt.on_conflict_do_update(
                    index_elements=["user_id", "verse_id"],
                    set_={
                        "first_read_at": func.least(t.c.first_read_at, x.first_read_at),
                        "last_read_at": func.greatest(t.c.last_read_at, x.last_read_at),
                        "read_count": func.greatest(t.c.read_count, x.read_count),
                    },
                    # Only a real change moves the row up the sync order.
                    where=or_(
                        x.first_read_at < t.c.first_read_at,
                        x.last_read_at > t.c.last_read_at,
                        x.read_count > t.c.read_count,
                    ),
                )
            )
            self.applied += 1
        for r in ch.reading_progress:
            if not self._verse_ok(r.last_verse_id) or not r.last_verse_id.startswith(f"{r.chapter}."):
                self.rejected += 1
                continue
            self._lww(
                "reading_progress",
                (r.chapter,),
                dict(
                    user_id=uid,
                    chapter=r.chapter,
                    last_verse_id=r.last_verse_id,
                    client_updated_at=self._ts(r.updated_at),
                ),
                ["user_id", "chapter"],
            )

    def _text_verses(self, ids: set[uuid.UUID]) -> dict[uuid.UUID, str]:
        if not ids:
            return {}
        rows = self.s.execute(select(VerseText.id, VerseText.verse_id).where(VerseText.id.in_(ids)))
        return {i: v for i, v in rows}

    def _item_ids(self) -> dict[tuple[str, str], uuid.UUID]:
        t = T["revision_item"]
        rows = self.s.execute(select(t.c.verse_id, t.c.card_type, t.c.id).where(t.c.user_id == self.uid))
        return {(v, c): i for v, c, i in rows}

    # -- pull --------------------------------------------------------------------

    def _query(self, collection: str):
        t = T[collection]
        if collection == "revision_review":
            items = T["revision_item"]
            return (
                select(t, items.c.verse_id, items.c.card_type)
                .join(items, items.c.id == t.c.item_id)
                .where(items.c.user_id == self.uid)
            )
        return select(t).where(t.c.user_id == self.uid)

    def _pull(self, cursor: int) -> tuple[dict[str, list[dict]], int, bool]:
        found: list[tuple[int, str, Any]] = []
        for collection in COLLECTIONS:
            t = T[collection]
            q = self._query(collection).where(t.c.sync_seq > cursor).order_by(t.c.sync_seq).limit(PAGE + 1)
            found += [(row.sync_seq, collection, row) for row in self.s.execute(q)]
        found.sort(key=lambda x: x[0])
        page = found[:PAGE]
        changes: dict[str, list[dict]] = {c: [] for c in COLLECTIONS}
        for _, collection, row in page:
            changes[collection].append(SERIALIZE[collection](self, row))
        return changes, (page[-1][0] if page else cursor), len(found) > PAGE

    def _current(self, collection: str, key: tuple) -> dict | None:
        t = T[collection]
        cols = {
            "bookmark": ["verse_id"],
            "verse_state": ["verse_id"],
            "highlight": ["id"],
            "note": ["id"],
            "revision_item": ["verse_id", "card_type"],
            "daily_practice": ["practice_date"],
            "reading_progress": ["chapter"],
        }[collection]
        q = self._query(collection).where(*(t.c[c] == v for c, v in zip(cols, key, strict=True)))
        row = self.s.execute(q).first()
        return SERIALIZE[collection](self, row) if row is not None else None

    def _updated(self, row) -> str | None:
        return _iso(row.client_updated_at or row.updated_at)


def _bookmark(self: SyncService, r) -> dict:
    return {"verse_id": r.verse_id, "updated_at": self._updated(r), "deleted": r.deleted_at is not None}


def _verse_state(self: SyncService, r) -> dict:
    return {
        "verse_id": r.verse_id,
        "favorite": r.is_favorite,
        "understood": r.is_understood,
        "needs_revision": r.needs_revision,
        "updated_at": self._updated(r),
    }


def _highlight(self: SyncService, r) -> dict:
    return {
        "id": str(r.id),
        "verse_id": r.verse_id,
        "text_id": str(r.verse_text_id) if r.verse_text_id else None,
        "start": r.start_offset,
        "end": r.end_offset,
        "color": r.color,
        "updated_at": self._updated(r),
        "deleted": r.deleted_at is not None,
    }


def _note(self: SyncService, r) -> dict:
    return {
        "id": str(r.id),
        "verse_id": r.verse_id,
        "chapter": r.chapter,
        "kind": r.kind,
        "body": self.cipher.decrypt(r.body, owner=self.owner, field="note.body"),
        "updated_at": self._updated(r),
        "deleted": r.deleted_at is not None,
    }


def _revision_item(self: SyncService, r) -> dict:
    return {
        "verse_id": r.verse_id,
        "card_type": r.card_type,
        "state": r.state,
        "step": r.step,
        "due_at": _iso(r.due_at),
        "reps": r.reps,
        "lapses": r.lapses,
        "last_reviewed_at": _iso(r.last_reviewed_at),
        "updated_at": self._updated(r),
        "deleted": r.deleted_at is not None,
    }


def _revision_review(self: SyncService, r) -> dict:
    return {
        "id": str(r.id),
        "verse_id": r.verse_id,
        "card_type": r.card_type,
        "rating": r.rating,
        "reviewed_at": _iso(r.reviewed_at),
        "elapsed_days": r.elapsed_days,
        "scheduled_days": r.scheduled_days,
    }


def _daily_practice(self: SyncService, r) -> dict:
    return {
        "date": r.practice_date.isoformat(),
        "verse_id": r.verse_id,
        "listened_at": _iso(r.listened_at),
        "understood_at": _iso(r.understood_at),
        "reflected_at": _iso(r.reflected_at),
        "applied_at": _iso(r.applied_at),
        "journal": self.cipher.decrypt(r.journal_text, owner=self.owner, field="daily_practice.journal"),
        "updated_at": self._updated(r),
        "deleted": r.deleted_at is not None,
    }


def _verse_read(self: SyncService, r) -> dict:
    return {
        "verse_id": r.verse_id,
        "first_read_at": _iso(r.first_read_at),
        "last_read_at": _iso(r.last_read_at),
        "read_count": r.read_count,
    }


def _reading_progress(self: SyncService, r) -> dict:
    return {"chapter": r.chapter, "last_verse_id": r.last_verse_id, "updated_at": self._updated(r)}


SERIALIZE: dict[str, Callable[[SyncService, Any], dict]] = {
    "bookmark": _bookmark,
    "verse_state": _verse_state,
    "highlight": _highlight,
    "note": _note,
    "revision_item": _revision_item,
    "revision_review": _revision_review,
    "daily_practice": _daily_practice,
    "verse_read": _verse_read,
    "reading_progress": _reading_progress,
}
