from __future__ import annotations

import uuid
from datetime import datetime
from typing import Literal

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.deps import DB, current_user_id
from app.modules.ai_tutor.models import AICitation, AIConversation, AIMessage
from app.modules.ai_tutor.prompts import EXPLAIN_QUESTION
from app.modules.ai_tutor.service import TutorService

router = APIRouter(prefix="/v1/tutor", tags=["tutor"])

Mode = Literal["simple", "deep", "practical", "story", "child", "sanskrit_terms", "free"]
Language = Literal["en", "te"]


def tutor(request: Request) -> TutorService:
    return request.app.state.tutor


class StatusOut(BaseModel):
    available: bool
    daily_limit: int
    questions_left_today: int


class ConversationIn(BaseModel):
    pinned_verse_id: str | None = Field(default=None, pattern=r"^\d{1,2}\.\d{1,2}$")
    mode: Mode = "free"
    language: Language = "en"


class ConversationOut(BaseModel):
    id: uuid.UUID
    title: str | None
    pinned_verse_id: str | None
    mode: str
    language: str
    created_at: datetime
    updated_at: datetime


class CitationOut(BaseModel):
    verse: str
    source_id: str | None


class MessageOut(BaseModel):
    id: uuid.UUID
    role: str
    content: str
    mode: str | None
    created_at: datetime
    # Assistant messages only:
    ai_generated: bool = False
    provider: str | None = None
    model: str | None = None
    prompt_version: str | None = None
    language: str | None = None
    citations: list[CitationOut] = []
    uncertain_points: list[str] = []
    confidence: str | None = None
    flags: list[str] = []
    retrieval: list[str] = []
    support: str | None = None
    out_of_scope: bool = False


class ConversationDetail(ConversationOut):
    messages: list[MessageOut]


class AskIn(BaseModel):
    question: str = Field(min_length=1, max_length=1000)
    mode: Mode | None = None
    language: Language | None = None


class ExplainIn(BaseModel):
    mode: Mode = "simple"
    language: Language = "en"


class ExchangeOut(BaseModel):
    question: MessageOut
    answer: MessageOut


def _conv(c: AIConversation) -> ConversationOut:
    return ConversationOut(
        id=c.id,
        title=c.title,
        pinned_verse_id=c.pinned_verse_id,
        mode=c.mode,
        language=c.language,
        created_at=c.created_at,
        updated_at=c.updated_at,
    )


def _msg(m: AIMessage, cites: list[AICitation]) -> MessageOut:
    out = MessageOut(id=m.id, role=m.role, content=m.content, mode=m.mode, created_at=m.created_at)
    if m.role == "assistant":
        meta = m.meta or {}
        out.ai_generated = True
        out.provider = m.provider
        out.model = m.model_id
        out.prompt_version = m.prompt_version
        out.language = meta.get("language")
        out.citations = [CitationOut(verse=c.verse_id, source_id=c.source_id) for c in cites if c.validated]
        out.uncertain_points = list(m.uncertain_points or [])
        out.confidence = meta.get("confidence")
        out.flags = list(meta.get("flags", []))
        out.retrieval = list(meta.get("retrieval", []))
        out.support = meta.get("support")
        out.out_of_scope = bool(meta.get("out_of_scope"))
    return out


@router.get("/status", response_model=StatusOut)
def status(
    user_id: uuid.UUID = Depends(current_user_id),
    session: Session = DB,
    svc: TutorService = Depends(tutor),
):
    used = svc.questions_used_today(session, user_id)
    return StatusOut(
        available=svc.available,
        daily_limit=svc.daily_questions,
        questions_left_today=max(0, svc.daily_questions - used),
    )


@router.post("/conversations", response_model=ConversationOut, status_code=201)
def create_conversation(
    body: ConversationIn,
    user_id: uuid.UUID = Depends(current_user_id),
    session: Session = DB,
    svc: TutorService = Depends(tutor),
):
    conv = svc.create_conversation(
        session, user_id, pinned_verse_id=body.pinned_verse_id, mode=body.mode, language=body.language
    )
    return _conv(conv)


@router.get("/conversations", response_model=list[ConversationOut])
def list_conversations(
    user_id: uuid.UUID = Depends(current_user_id),
    session: Session = DB,
    svc: TutorService = Depends(tutor),
):
    return [_conv(c) for c in svc.list_conversations(session, user_id)]


@router.get("/conversations/{conv_id}", response_model=ConversationDetail)
def get_conversation(
    conv_id: uuid.UUID,
    user_id: uuid.UUID = Depends(current_user_id),
    session: Session = DB,
    svc: TutorService = Depends(tutor),
):
    conv = svc.conversation(session, user_id, conv_id)
    msgs = [_msg(m, cs) for m, cs in svc.messages(session, conv)]
    return ConversationDetail(**_conv(conv).model_dump(), messages=msgs)


@router.delete("/conversations/{conv_id}", status_code=204)
def delete_conversation(
    conv_id: uuid.UUID,
    user_id: uuid.UUID = Depends(current_user_id),
    session: Session = DB,
    svc: TutorService = Depends(tutor),
):
    svc.delete_conversation(session, user_id, conv_id)
    return Response(status_code=204)


@router.post("/conversations/{conv_id}/messages", response_model=ExchangeOut)
def ask(
    conv_id: uuid.UUID,
    body: AskIn,
    user_id: uuid.UUID = Depends(current_user_id),
    session: Session = DB,
    svc: TutorService = Depends(tutor),
):
    ex = svc.ask(session, user_id, conv_id, body.question, mode=body.mode, language=body.language)
    return ExchangeOut(question=_msg(ex.question, []), answer=_msg(ex.answer, ex.citations))


@router.post("/conversations/{conv_id}/explain", response_model=ExchangeOut)
def explain(
    conv_id: uuid.UUID,
    body: ExplainIn,
    user_id: uuid.UUID = Depends(current_user_id),
    session: Session = DB,
    svc: TutorService = Depends(tutor),
):
    """Explain the pinned verse in a mode. A fixed question, so answers are
    shared through the cache: the first student pays, later ones are free."""
    question = EXPLAIN_QUESTION[body.language]
    ex = svc.ask(session, user_id, conv_id, question, mode=body.mode, language=body.language)
    return ExchangeOut(question=_msg(ex.question, []), answer=_msg(ex.answer, ex.citations))
