"""FastAPI application.

    uvicorn app.main:app            # reads settings and llm.yaml from the environment

Only the AI tutor and accounts live here: everything else in the app works
offline from the content pack.
"""

from __future__ import annotations

import functools
import logging
import math
from datetime import UTC, datetime

from fastapi import FastAPI, Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse
from sqlalchemy import create_engine, text
from sqlalchemy.orm import sessionmaker

from app.api import auth as auth_api
from app.api import tutor as tutor_api
from app.core.ratelimit import SlidingWindowLimiter
from app.core.settings import Settings
from app.modules.ai_tutor.service import ProvidersBusy, QuotaExceeded, TutorError, TutorService
from app.modules.auth.service import AuthError
from app.providers.llm import LLMRouter, build_router

VERSION = "0.6.0"
log = logging.getLogger("gita")


def _error(status: int, code: str, message: str, headers: dict | None = None) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status, headers=headers)


def create_app(
    settings: Settings | None = None,
    llm: LLMRouter | str | None = "from-config",
    session_factory: sessionmaker | None = None,
) -> FastAPI:
    settings = settings or Settings.from_env()
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
    app.state.session_factory = session_factory
    app.state.tutor = TutorService(llm, settings.tutor_daily_questions)
    app.state.signup_limiter = SlidingWindowLimiter(settings.signups_per_ip_per_hour, 3600)
    app.state.signup_limiter_total = SlidingWindowLimiter(settings.signups_per_hour_total, 3600)

    app.include_router(auth_api.router)
    app.include_router(tutor_api.router)

    @app.get("/v1/health", tags=["meta"])
    def health():
        with session_factory() as s:
            s.execute(text("SELECT 1"))
        return {"status": "ok", "version": VERSION, "tutor": app.state.tutor.available}

    @app.exception_handler(AuthError)
    def _auth(_: Request, e: AuthError):
        return _error(401, "unauthorized", str(e), {"WWW-Authenticate": "Bearer"})

    @app.exception_handler(auth_api.RateLimitedError)
    def _signup_limited(_: Request, e: Exception):
        return _error(
            429,
            "rate_limited",
            "Too many new accounts from this network. Try again later.",
            {"Retry-After": "3600"},
        )

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
