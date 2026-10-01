"""AI tutor: conversations and grounded, validated answers."""

from __future__ import annotations

import hashlib
import threading
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

from sqlalchemy import func, select, update
from sqlalchemy.orm import Session

from app.modules.ai_tutor.models import AIAnswerCache, AICitation, AIConversation, AIMessage
from app.modules.ai_tutor.prompts import MODES, PROMPT_VERSION, SUGGEST_SYSTEM, SYSTEM, user_turn
from app.modules.ai_tutor.retrieval import VerseIndex, build_context
from app.modules.ai_tutor.safety import support_note
from app.modules.ai_tutor.validate import Answer, Citation, check_answer, finalize
from app.providers.llm import (
    AllProvidersFailed,
    GenerateOptions,
    InvalidOutput,
    LLMError,
    LLMRouter,
    Message,
    ValidationFailed,
    generate_structured,
)

HISTORY_MESSAGES = 6


class TutorError(Exception):
    code = "tutor_error"
    status = 400


class NotFound(TutorError):
    code, status = "not_found", 404


class TutorUnavailable(TutorError):
    code, status = "tutor_unavailable", 503


class QuotaExceeded(TutorError):
    code, status = "quota_exceeded", 429

    def __init__(self, limit: int, resets_at: datetime):
        super().__init__(
            f"You have used today's {limit} questions. More are available after {resets_at:%H:%M} UTC."
        )
        self.resets_at = resets_at


class ProvidersBusy(TutorError):
    code, status = "providers_busy", 503

    def __init__(self, retry_after_s: float | None):
        super().__init__("The AI teacher is busy right now. Please try again in a little while.")
        self.retry_after_s = retry_after_s


class NoVerifiedAnswer(TutorError):
    code, status = "no_verified_answer", 502

    def __init__(self):
        super().__init__(
            "The AI teacher could not produce an answer whose sources could be verified. "
            "Try rephrasing, or ask about a specific verse."
        )


def _start_of_day(now: datetime) -> datetime:
    return now.replace(hour=0, minute=0, second=0, microsecond=0)


def _normalize_question(q: str) -> str:
    return " ".join(q.lower().split()).rstrip("?.! ")


def cache_key(pinned: str | None, mode: str, language: str, question: str) -> str:
    raw = f"{pinned or ''}|{mode}|{language}|{_normalize_question(question)}|{PROMPT_VERSION}"
    return hashlib.sha256(raw.encode()).hexdigest()


@dataclass(frozen=True)
class Exchange:
    question: AIMessage
    answer: AIMessage
    citations: list[AICitation]


class TutorService:
    def __init__(self, llm: LLMRouter | None, daily_questions: int):
        self.llm = llm
        self.daily_questions = daily_questions
        self._index: VerseIndex | None = None
        self._lock = threading.Lock()

    @property
    def available(self) -> bool:
        return self.llm is not None

    def index(self, session: Session) -> VerseIndex:
        with self._lock:
            if self._index is None:
                self._index = VerseIndex.load(session)
            return self._index

    # ---- quota -------------------------------------------------------------

    def questions_used_today(self, session: Session, user_id: uuid.UUID, now: datetime | None = None) -> int:
        since = _start_of_day(now or datetime.now(UTC))
        return session.scalar(
            select(func.count(AIMessage.id))
            .join(AIConversation, AIConversation.id == AIMessage.conversation_id)
            .where(
                AIConversation.user_id == user_id,
                AIMessage.role == "assistant",
                AIMessage.provider != "cache",
                AIMessage.created_at >= since,
            )
        )

    # ---- conversations ------------------------------------------------------

    def create_conversation(
        self, session: Session, user_id: uuid.UUID, *, pinned_verse_id: str | None, mode: str, language: str
    ) -> AIConversation:
        if pinned_verse_id is not None and pinned_verse_id not in self.index(session).ids:
            raise NotFound(f"verse {pinned_verse_id} does not exist")
        conv = AIConversation(user_id=user_id, pinned_verse_id=pinned_verse_id, mode=mode, language=language)
        session.add(conv)
        session.flush()
        session.refresh(conv)
        return conv

    def conversation(self, session: Session, user_id: uuid.UUID, conv_id: uuid.UUID) -> AIConversation:
        conv = session.get(AIConversation, conv_id)
        if conv is None or conv.user_id != user_id or conv.deleted_at is not None:
            raise NotFound("conversation not found")
        return conv

    def list_conversations(
        self, session: Session, user_id: uuid.UUID, limit: int = 50
    ) -> list[AIConversation]:
        return list(
            session.scalars(
                select(AIConversation)
                .where(AIConversation.user_id == user_id, AIConversation.deleted_at.is_(None))
                .order_by(AIConversation.updated_at.desc())
                .limit(limit)
            )
        )

    def messages(self, session: Session, conv: AIConversation) -> list[tuple[AIMessage, list[AICitation]]]:
        msgs = list(
            session.scalars(
                select(AIMessage)
                .where(AIMessage.conversation_id == conv.id)
                .order_by(AIMessage.created_at, AIMessage.role.desc())
            )
        )
        cites: dict[uuid.UUID, list[AICitation]] = {}
        if msgs:
            for c in session.scalars(
                select(AICitation).where(AICitation.message_id.in_([m.id for m in msgs]))
            ):
                cites.setdefault(c.message_id, []).append(c)
        return [(m, cites.get(m.id, [])) for m in msgs]

    def delete_conversation(self, session: Session, user_id: uuid.UUID, conv_id: uuid.UUID) -> None:
        conv = self.conversation(session, user_id, conv_id)
        conv.deleted_at = datetime.now(UTC)

    # ---- answering ----------------------------------------------------------

    def ask(
        self,
        session: Session,
        user_id: uuid.UUID,
        conv_id: uuid.UUID,
        question: str,
        *,
        mode: str | None = None,
        language: str | None = None,
    ) -> Exchange:
        conv = self.conversation(session, user_id, conv_id)
        mode = mode or conv.mode
        language = language or conv.language
        if mode not in MODES:
            raise TutorError(f"unknown mode {mode}")
        question = question.strip()
        history = self.messages(session, conv)[-HISTORY_MESSAGES:]
        support = support_note(question, language)

        key = cache_key(conv.pinned_verse_id, mode, language, question) if not history else None
        cached = session.get(AIAnswerCache, key) if key else None
        if cached is not None:
            cached.hit_count += 1
            return self._store(
                session,
                conv,
                question,
                mode,
                language,
                _answer_from_cache(cached.answer),
                provider="cache",
                model=cached.model_id,
                tokens=(None, None),
                meta_extra={"retrieval": cached.answer.get("retrieval", []), "support": support},
            )

        if self.llm is None:
            raise TutorUnavailable("The AI teacher is not configured on this server.")
        used = self.questions_used_today(session, user_id)
        if used >= self.daily_questions:
            raise QuotaExceeded(self.daily_questions, _start_of_day(datetime.now(UTC)) + timedelta(days=1))

        index = self.index(session)
        carry = [c.verse_id for m, cs in history if m.role == "assistant" for c in cs]
        ctx = build_context(
            session,
            index,
            question,
            pinned_verse_id=conv.pinned_verse_id,
            language=language,
            carry=carry[-4:],
            suggest=self._suggest,
        )
        prompt = [
            Message("system", SYSTEM),
            *[Message(m.role, m.content) for m, _ in history if m.role in ("user", "assistant")],
            Message(
                "user", user_turn(question, ctx, mode=mode, language=language, pinned=conv.pinned_verse_id)
            ),
        ]
        try:
            result = generate_structured(
                self.llm,
                prompt,
                lambda obj: check_answer(obj, ctx, index, language),
                GenerateOptions(json=True, max_tokens=1400, temperature=0.3),
            )
        except AllProvidersFailed as e:
            if e.errors and all(isinstance(err, InvalidOutput) for _, err in e.errors):
                raise NoVerifiedAnswer() from e
            raise ProvidersBusy(self.llm.next_available_in()) from e

        sanskrit_source = {p.verse_id: p.source_id for p in ctx.passages if p.kind == "sanskrit"}
        answer = finalize(result.value, ctx, index, sanskrit_source)
        if result.repaired:
            answer.flags.append("repaired")
        c = result.completion
        exchange = self._store(
            session,
            conv,
            question,
            mode,
            language,
            answer,
            provider=c.provider,
            model=c.model,
            tokens=(c.tokens_in, c.tokens_out),
            meta_extra={"retrieval": ctx.methods, "support": support},
        )
        if key is not None:
            session.add(
                AIAnswerCache(
                    cache_key=key,
                    verse_id=conv.pinned_verse_id,
                    mode=mode,
                    language=language,
                    prompt_version=PROMPT_VERSION,
                    model_id=c.model,
                    question=question,
                    answer=_answer_to_cache(answer, ctx.methods),
                )
            )
        return exchange

    def _suggest(self, question: str) -> list[str]:
        """Ask the model which verses to read. The ids are checked against the
        verse table by the caller; a failure here only means fewer passages."""
        assert self.llm is not None

        def valid(obj: dict) -> list[str]:
            verses = obj.get("verses")
            if not isinstance(verses, list):
                raise ValidationFailed('"verses" must be a list')
            return [str(v).strip().removeprefix("BG").strip() for v in verses][:5]

        try:
            return generate_structured(
                self.llm,
                [Message("system", SUGGEST_SYSTEM), Message("user", question)],
                valid,
                GenerateOptions(json=True, max_tokens=120, temperature=0.0),
            ).value
        except LLMError:
            return []

    def _store(
        self,
        session: Session,
        conv: AIConversation,
        question: str,
        mode: str,
        language: str,
        answer: Answer,
        *,
        provider: str,
        model: str,
        tokens: tuple[int | None, int | None],
        meta_extra: dict,
    ) -> Exchange:
        q = AIMessage(conversation_id=conv.id, role="user", content=question, mode=mode)
        session.add(q)
        session.flush()
        a = AIMessage(
            conversation_id=conv.id,
            role="assistant",
            content=answer.text,
            mode=mode,
            provider=provider,
            model_id=model,
            prompt_version=PROMPT_VERSION,
            tokens_in=tokens[0],
            tokens_out=tokens[1],
            uncertain_points=answer.uncertain_points,
            meta={
                "language": language,
                "confidence": answer.confidence,
                "flags": answer.flags,
                "out_of_scope": answer.out_of_scope,
                **{k: v for k, v in meta_extra.items() if v},
            },
        )
        session.add(a)
        session.flush()
        cites = [
            AICitation(message_id=a.id, verse_id=c.verse, source_id=c.source_id, validated=True)
            for c in answer.citations
        ]
        session.add_all(cites)
        # An explicit UPDATE so the trigger moves updated_at (conversation list order).
        session.execute(
            update(AIConversation)
            .where(AIConversation.id == conv.id)
            .values(title=func.coalesce(AIConversation.title, question[:80]))
        )
        session.flush()
        session.refresh(q)
        session.refresh(a)
        return Exchange(q, a, cites)


def _answer_to_cache(answer: Answer, retrieval: list[str]) -> dict:
    return {
        "text": answer.text,
        "citations": [{"verse": c.verse, "source_id": c.source_id} for c in answer.citations],
        "confidence": answer.confidence,
        "uncertain_points": answer.uncertain_points,
        "out_of_scope": answer.out_of_scope,
        "flags": answer.flags,
        "retrieval": retrieval,
    }


def _answer_from_cache(d: dict) -> Answer:
    return Answer(
        text=d["text"],
        citations=[Citation(c["verse"], c["source_id"]) for c in d["citations"]],
        confidence=d.get("confidence", "medium"),
        uncertain_points=list(d.get("uncertain_points", [])),
        out_of_scope=bool(d.get("out_of_scope")),
        flags=[*d.get("flags", []), "cached"],
    )
