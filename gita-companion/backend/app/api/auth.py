from __future__ import annotations

import uuid

from fastapi import APIRouter, Depends, Request, Response
from pydantic import BaseModel, Field
from sqlalchemy.orm import Session

from app.api.deps import DB, client_ip, current_user_id, settings
from app.core.settings import Settings
from app.modules.auth import service
from app.modules.auth.service import TokenPair

router = APIRouter(prefix="/v1", tags=["auth"])


class TokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user_id: uuid.UUID


class RefreshRequest(BaseModel):
    refresh_token: str = Field(min_length=20, max_length=200)


class RateLimitedError(Exception):
    pass


def _tokens(pair: TokenPair) -> TokenResponse:
    return TokenResponse(
        access_token=pair.access_token,
        refresh_token=pair.refresh_token,
        expires_in=pair.expires_in,
        user_id=pair.user_id,
    )


@router.post("/auth/anonymous", response_model=TokenResponse, status_code=201)
def create_anonymous(request: Request, session: Session = DB, cfg: Settings = Depends(settings)):
    """Create an account for this device. No personal data is collected."""
    state = request.app.state
    if not (state.signup_limiter.allow(client_ip(request)) and state.signup_limiter_total.allow("all")):
        raise RateLimitedError()
    return _tokens(service.create_anonymous_account(session, cfg))


@router.post("/auth/refresh", response_model=TokenResponse)
def refresh(body: RefreshRequest, request: Request, cfg: Settings = Depends(settings)):
    # Not the request-scoped session: after a detected token reuse the
    # revocation must be committed even though the request fails with 401.
    with request.app.state.session_factory() as session:
        try:
            with session.begin():
                return _tokens(service.refresh(session, cfg, body.refresh_token))
        except service.TokenReused as e:
            with session.begin():
                service.revoke_family(session, e.family_id)
            raise


@router.post("/auth/logout", status_code=204)
def logout(body: RefreshRequest, session: Session = DB):
    service.logout(session, body.refresh_token)
    return Response(status_code=204)


@router.delete("/me", status_code=204)
def delete_me(user_id: uuid.UUID = Depends(current_user_id), session: Session = DB):
    """Delete the account and everything stored for it."""
    service.delete_account(session, user_id)
    return Response(status_code=204)
