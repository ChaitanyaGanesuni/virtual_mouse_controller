"""FastAPI application.

    uvicorn app.main:app            # reads settings and llm.yaml from the environment

Only the AI tutor and accounts live here: everything else in the app works
offline from the content pack.
"""

from __future__ import annotations

import functools
import json
import logging
import math
from datetime import UTC, datetime

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from gita_content.retrieval import Retriever
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app.api import auth as auth_api
from app.api import packs as packs_api
from app.api import sync as sync_api
from app.api import tutor as tutor_api
from app.core.crypto import FieldCipher
from app.core.ratelimit import SlidingWindowLimiter
from app.core.security import HardeningMiddleware
from app.core.settings import Settings
from app.modules.ai_tutor.service import ProvidersBusy, QuotaExceeded, TutorError, TutorService
from app.modules.auth.service import AuthError
from app.modules.packs.catalog import PackCatalog
from app.modules.sync.schemas import MAX_RECORDS_PER_REQUEST
from app.providers.embeddings import EmbeddingProvider
from app.providers.embeddings import from_env as embeddings_from_env
from app.providers.llm import LLMRouter, build_router

VERSION = "0.9.0"
log = logging.getLogger("gita")


def _error(status: int, code: str, message: str, headers: dict | None = None) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status, headers=headers)


def load_retriever(settings: Settings) -> Retriever | None:
    """The hybrid retriever runs from the content dataset (format 3)."""
    path = settings.content_dataset
    if path is None or not path.exists():
        log.warning("content dataset not found (%s): tutor retrieval uses references only", path)
        return None
    return Retriever(json.loads(path.read_text(encoding="utf-8")))


def create_app(
    settings: Settings | None = None,
    llm: LLMRouter | str | None = "from-config",
    session_factory: sessionmaker | None = None,
    retriever: Retriever | str | None = "from-config",
    embeddings: EmbeddingProvider | str | None = "from-config",
    packs: PackCatalog | str = "from-config",
) -> FastAPI:
    settings = settings or Settings.from_env()
    if retriever == "from-config":
        retriever = load_retriever(settings)
    if packs == "from-config":
        packs = PackCatalog.load(settings.packs_dir)
    if embeddings == "from-config":
        embeddings = embeddings_from_env()
    if llm == "from-config":
        # Questions are personal: only providers approved for user data.
        router, notes = build_router(require_user_data_ok=True)
        for note in notes:
            log.info("llm: %s", note)
        llm = router if router.model else None
    if session_factory is None:
        engine = create_engine(settings.database_url, pool_pre_ping=True, pool_size=5, max_overflow=5)
        session_factory = sessionmaker(engine, expire_on_commit=False)

    app = FastAPI(
        title="Gita Companion API",
        version=VERSION,
        # No interactive docs in production; the schema is still at /openapi.json.
        docs_url=None if settings.environment == "production" else "/docs",
        redoc_url=None,
    )
    app.state.settings = settings
    app.add_middleware(HardeningMiddleware)
    app.state.session_factory = session_factory
    app.state.tutor = TutorService(llm, settings.tutor_daily_questions, retriever, embeddings)
    app.state.signup_limiter = SlidingWindowLimiter(settings.signups_per_ip_per_hour, 3600)
    app.state.signup_limiter_total = SlidingWindowLimiter(settings.signups_per_hour_total, 3600)
    # Recovery codes are 120-bit random, so this only stops noise.
    app.state.recover_limiter = SlidingWindowLimiter(20, 3600)
    app.state.sync_limiter = SlidingWindowLimiter(settings.syncs_per_user_per_hour, 3600)
    app.state.cipher = FieldCipher(settings.data_encryption_key)
    app.state.packs = packs
    app.state.download_limiter = SlidingWindowLimiter(settings.downloads_per_ip_per_hour, 3600)
    if not app.state.cipher.enabled:
        log.warning("DATA_ENCRYPTION_KEY not set: notes and journal are stored unencrypted")

    app.include_router(auth_api.router)
    app.include_router(tutor_api.router)
    app.include_router(sync_api.router)
    app.include_router(packs_api.router)

    @app.get("/v1/health", tags=["meta"])
    def health():
        with session_factory() as s:
            s.execute(text("SELECT 1"))
        return {"status": "ok", "version": VERSION, "tutor": app.state.tutor.available}

    @app.exception_handler(AuthError)
    def _auth(_: Request, e: AuthError):
        return _error(401, "unauthorized", str(e), {"WWW-Authenticate": "Bearer"})

    @app.exception_handler(auth_api.RateLimitedError)
    def _rate_limited(_: Request, e: auth_api.RateLimitedError):
        return _error(429, "rate_limited", str(e), {"Retry-After": str(e.retry_after)})

    @app.exception_handler(packs_api.PackNotFound)
    def _no_pack(_: Request, e: Exception):
        return _error(404, "not_found", "no such pack")

    @app.exception_handler(sync_api.TooLarge)
    def _too_large(_: Request, e: Exception):
        return _error(413, "too_large", f"send at most {MAX_RECORDS_PER_REQUEST} changes (4 MB) per request")

    @app.exception_handler(TutorError)
    def _tutor(_: Request, e: TutorError):
        headers = {}
        if isinstance(e, ProvidersBusy) and e.retry_after_s is not None:
            headers["Retry-After"] = str(max(1, math.ceil(e.retry_after_s)))
        if isinstance(e, QuotaExceeded):
            headers["Retry-After"] = str(max(1, int((e.resets_at - datetime.now(UTC)).total_seconds())))
        return _error(e.status, e.code, str(e), headers)

    @app.exception_handler(RequestValidationError)
    def _invalid(_: Request, e: RequestValidationError):
        first = e.errors()[0] if e.errors() else {}
        where = ".".join(str(x) for x in first.get("loc", []) if x != "body")
        return _error(422, "invalid_request", f"{where}: {first.get('msg', 'invalid request')}")

    return app


@functools.cache
def _default_app() -> FastAPI:
    logging.basicConfig(level=logging.INFO)
    return create_app()


def __getattr__(name: str):
    # `uvicorn app.main:app` builds the app lazily, so importing this module
    # (tests, tools) does not need a database or secrets.
    if name == "app":
        return _default_app()
    raise AttributeError(name)
