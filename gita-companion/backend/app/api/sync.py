"""Study-data sync: POST /v1/sync (see app/modules/sync)."""

from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request
from sqlalchemy import select
from sqlalchemy.orm import Session

from app.api.auth import RateLimitedError
from app.api.deps import DB, current_user_id
from app.modules.content.models import Verse
from app.modules.sync.schemas import MAX_RECORDS_PER_REQUEST, SyncRequest, SyncResponse
from app.modules.sync.service import SyncService

router = APIRouter(prefix="/v1", tags=["sync"])
MAX_BODY_BYTES = 4 * 1024 * 1024


class TooLarge(Exception):
    pass


def _verse_ids(request: Request, session: Session) -> frozenset[str]:
    state = request.app.state
    if not getattr(state, "verse_ids", None):
        state.verse_ids = frozenset(session.scalars(select(Verse.id)))
    return state.verse_ids


@router.post("/sync", response_model=SyncResponse)
def sync(
    body: SyncRequest,
    request: Request,
    user_id: uuid.UUID = Depends(current_user_id),
    session: Session = DB,
):
    """Send this device's changes; receive other devices' changes since
    `cursor`. Call again while `more` is true."""
    if int(request.headers.get("content-length") or 0) > MAX_BODY_BYTES:
        raise TooLarge()
    if body.changes.count() > MAX_RECORDS_PER_REQUEST:
        raise TooLarge()
    if not request.app.state.sync_limiter.allow(str(user_id)):
        raise RateLimitedError("Syncing too often. Try again later.", retry_after=600)
    cipher = request.app.state.cipher
    return SyncService(session, user_id, cipher, _verse_ids(request, session)).run(body)
