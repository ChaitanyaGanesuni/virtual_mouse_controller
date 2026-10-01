"""Request-scoped dependencies: database session, settings, current user."""

from __future__ import annotations

import uuid
from collections.abc import Iterator

from fastapi import Depends, Request
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer
from sqlalchemy.orm import Session

from app.core.settings import Settings
from app.modules.auth.service import AuthError, active_user, verify_access_token

_bearer = HTTPBearer(auto_error=False)


def settings(request: Request) -> Settings:
    return request.app.state.settings


def db(request: Request) -> Iterator[Session]:
    """One transaction per request: committed if the handler returns, rolled
    back if it raises."""
    with request.app.state.session_factory() as session, session.begin():
        yield session


# Commit before the response is sent, so a failed commit is never reported
# to the client as success. Use this one object everywhere: it is also the
# cache key that makes a request share a single session.
DB = Depends(db, scope="function")


def client_ip(request: Request) -> str:
    if request.app.state.settings.trust_forwarded_for:
        fwd = request.headers.get("x-forwarded-for")
        if fwd:
            return fwd.split(",")[0].strip()
    return request.client.host if request.client else "unknown"


def current_user_id(
    request: Request,
    creds: HTTPAuthorizationCredentials | None = Depends(_bearer),
    session: Session = DB,
) -> uuid.UUID:
    if creds is None or creds.scheme.lower() != "bearer":
        raise AuthError("sign-in required")
    user_id = verify_access_token(request.app.state.settings, creds.credentials)
    active_user(session, user_id)
    return user_id
