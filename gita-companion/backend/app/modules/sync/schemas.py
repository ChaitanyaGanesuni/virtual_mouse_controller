"""Wire format of study-data sync (POST /v1/sync).

Each collection is identified the way the app identifies it:
- by its natural key where there can only be one (a bookmark per verse, a
  verse state per verse, a revision card per verse and card type, a daily
  practice per date, reading progress per chapter);
- by a client-generated UUID where there can be many (notes, highlights,
  revision reviews).

`updated_at` is when the change was made on the device; conflicting edits
are resolved by it (last write wins). Deleted items stay as tombstones
(`deleted: true`) so every device learns about the deletion.
"""

from __future__ import annotations

import uuid
from datetime import date
from typing import Literal

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

VerseId = str  # validated against the verse table by the service
MAX_TEXT = 20_000


class _Record(BaseModel):
    model_config = ConfigDict(extra="forbid")


class BookmarkRec(_Record):
    verse_id: VerseId = Field(max_length=8)
    updated_at: AwareDatetime
    deleted: bool = False


class VerseStateRec(_Record):
    verse_id: VerseId = Field(max_length=8)
    favorite: bool = False
    understood: bool = False
    needs_revision: bool = False
    updated_at: AwareDatetime


class HighlightRec(_Record):
    id: uuid.UUID
    verse_id: VerseId = Field(max_length=8)
    # The verse_text row (same id in the app's content pack and on the
    # server); null for the Sanskrit itself.
    text_id: uuid.UUID | None = None
    start: int = Field(ge=0, le=MAX_TEXT)
    end: int = Field(gt=0, le=MAX_TEXT)
    color: Literal["gold", "green", "blue", "pink"] = "gold"
    updated_at: AwareDatetime
    deleted: bool = False

    @model_validator(mode="after")
    def _range(self) -> HighlightRec:
        if self.end <= self.start:
            raise ValueError("end must be after start")
        return self


class NoteRec(_Record):
    id: uuid.UUID
    verse_id: VerseId | None = Field(default=None, max_length=8)
    chapter: int | None = Field(default=None, ge=1, le=18)
    kind: Literal["note", "question", "reflection"] = "note"
    body: str = Field(max_length=MAX_TEXT)
    updated_at: AwareDatetime
    deleted: bool = False

    @model_validator(mode="after")
    def _anchor(self) -> NoteRec:
        if self.verse_id is not None and self.chapter is not None:
            raise ValueError("a note belongs to a verse or a chapter, not both")
        return self


CardType = Literal["meaning", "concept", "application"]


class RevisionItemRec(_Record):
    verse_id: VerseId = Field(max_length=8)
    card_type: CardType
    state: Literal["new", "learning", "review", "relearning", "suspended"] = "new"
    step: int = Field(default=0, ge=0, le=100)
    due_at: AwareDatetime
    reps: int = Field(default=0, ge=0)
    lapses: int = Field(default=0, ge=0)
    last_reviewed_at: AwareDatetime | None = None
    updated_at: AwareDatetime
    deleted: bool = False


class RevisionReviewRec(_Record):
    """Append-only log of self-graded reviews (1 again … 4 easy)."""

    id: uuid.UUID
    verse_id: VerseId = Field(max_length=8)
    card_type: CardType
    rating: int = Field(ge=1, le=4)
    reviewed_at: AwareDatetime
    elapsed_days: float | None = Field(default=None, ge=0)
    scheduled_days: float | None = Field(default=None, ge=0)


class DailyPracticeRec(_Record):
    date: date
    verse_id: VerseId = Field(max_length=8)
    listened_at: AwareDatetime | None = None
    understood_at: AwareDatetime | None = None
    reflected_at: AwareDatetime | None = None
    applied_at: AwareDatetime | None = None
    # Journal text is private: the app sends it only if the user chose to
    # sync the journal. Absent = leave the stored journal unchanged; null =
    # erase it from the server.
    journal: str | None = Field(default=None, max_length=MAX_TEXT)
    updated_at: AwareDatetime
    deleted: bool = False


class VerseReadRec(_Record):
    """Merged, never overwritten: earliest first read, latest last read."""

    verse_id: VerseId = Field(max_length=8)
    first_read_at: AwareDatetime
    last_read_at: AwareDatetime
    read_count: int = Field(default=1, ge=1, le=1_000_000)


class ReadingProgressRec(_Record):
    chapter: int = Field(ge=1, le=18)
    last_verse_id: VerseId = Field(max_length=8)
    updated_at: AwareDatetime


class Changes(_Record):
    bookmark: list[BookmarkRec] = []
    verse_state: list[VerseStateRec] = []
    highlight: list[HighlightRec] = []
    note: list[NoteRec] = []
    revision_item: list[RevisionItemRec] = []
    revision_review: list[RevisionReviewRec] = []
    daily_practice: list[DailyPracticeRec] = []
    verse_read: list[VerseReadRec] = []
    reading_progress: list[ReadingProgressRec] = []

    def count(self) -> int:
        return sum(len(getattr(self, name)) for name in COLLECTIONS)


COLLECTIONS = tuple(Changes.model_fields)
MAX_RECORDS_PER_REQUEST = 1000


class SyncRequest(_Record):
    # The `cursor` from the previous response; 0 on first sync.
    cursor: int = Field(default=0, ge=0)
    changes: Changes = Changes()


class SyncResponse(BaseModel):
    cursor: int
    # More changes are waiting: call again with the new cursor.
    more: bool
    changes: dict[str, list[dict]]
    applied: int
    # Changes not applied: older than what the server has (the newer version
    # is included in `changes`), or naming verses that do not exist.
    rejected: int
