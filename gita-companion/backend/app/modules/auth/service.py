"""Anonymous device accounts, short-lived access tokens and rotating refresh
tokens.

- Access token: a signed JWT (HS256) valid for 15 minutes.
- Refresh token: 256 random bits, shown to the client once; only its SHA-256
  is stored. Every refresh rotates it. Presenting an already-rotated token
  means it was copied, so the whole token family is revoked and the device
  must sign in again.
"""

from __future__ import annotations

import hashlib
import secrets
import uuid
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta

import jwt
from sqlalchemy import select, update
from sqlalchemy.orm import Session

from app.core.settings import Settings
from app.modules.auth.models import AppUser, RefreshToken

ISSUER = "gita-companion"


class AuthError(Exception):
    """Invalid, expired or revoked credentials (HTTP 401)."""


class TokenReused(AuthError):
    """A rotated refresh token was presented again. The caller must revoke
    `family_id` in a transaction that commits even though the request fails."""

    def __init__(self, family_id: uuid.UUID):
        super().__init__("refresh token reused; signed out for safety")
        self.family_id = family_id


@dataclass(frozen=True)
class TokenPair:
    access_token: str
    refresh_token: str
    expires_in: int
    user_id: uuid.UUID


def _hash(token: str) -> str:
    return hashlib.sha256(token.encode()).hexdigest()


def _now() -> datetime:
    return datetime.now(UTC)


def access_token(settings: Settings, user_id: uuid.UUID, now: datetime | None = None) -> str:
    now = now or _now()
    payload = {
        "sub": str(user_id),
        "iss": ISSUER,
        "typ": "access",
        "iat": int(now.timestamp()),
        "exp": int((now + timedelta(seconds=settings.access_token_ttl_s)).timestamp()),
    }
    return jwt.encode(payload, settings.jwt_secret, algorithm="HS256")


def verify_access_token(settings: Settings, token: str) -> uuid.UUID:
    try:
        payload = jwt.decode(
            token,
            settings.jwt_secret,
            algorithms=["HS256"],
            issuer=ISSUER,
            options={"require": ["exp", "iat", "sub", "iss"]},
        )
    except jwt.ExpiredSignatureError:
        raise AuthError("token expired") from None
    except jwt.InvalidTokenError:
        raise AuthError("invalid token") from None
    if payload.get("typ") != "access":
        raise AuthError("invalid token")
    try:
        return uuid.UUID(payload["sub"])
    except ValueError:
        raise AuthError("invalid token") from None


def _issue(session: Session, settings: Settings, user_id: uuid.UUID, family: uuid.UUID) -> TokenPair:
    raw = secrets.token_urlsafe(32)
    session.add(
        RefreshToken(
            user_id=user_id,
            token_hash=_hash(raw),
            family_id=family,
            expires_at=_now() + timedelta(seconds=settings.refresh_token_ttl_s),
        )
    )
    session.flush()
    return TokenPair(access_token(settings, user_id), raw, settings.access_token_ttl_s, user_id)


def create_anonymous_account(session: Session, settings: Settings) -> TokenPair:
    user = AppUser(auth_provider="anonymous", external_subject=secrets.token_hex(16))
    session.add(user)
    session.flush()
    return _issue(session, settings, user.id, uuid.uuid4())


def refresh(session: Session, settings: Settings, raw: str) -> TokenPair:
    token = session.scalars(
        select(RefreshToken).where(RefreshToken.token_hash == _hash(raw)).with_for_update()
    ).one_or_none()
    if token is None:
        raise AuthError("unknown refresh token")
    if token.revoked_at is not None:
        # A rotated token came back: someone else has a copy.
        raise TokenReused(token.family_id)
    if token.expires_at <= _now():
        raise AuthError("refresh token expired")
    user = session.get(AppUser, token.user_id)
    if user is None or user.deleted_at is not None:
        raise AuthError("account no longer exists")
    token.revoked_at = _now()
    user.last_seen_at = _now()
    return _issue(session, settings, token.user_id, token.family_id)


def revoke_family(session: Session, family: uuid.UUID) -> None:
    session.execute(
        update(RefreshToken)
        .where(RefreshToken.family_id == family, RefreshToken.revoked_at.is_(None))
        .values(revoked_at=_now())
    )


def logout(session: Session, raw: str) -> None:
    token = session.scalars(select(RefreshToken).where(RefreshToken.token_hash == _hash(raw))).one_or_none()
    if token is not None:
        revoke_family(session, token.family_id)


def delete_account(session: Session, user_id: uuid.UUID) -> None:
    """Hard delete: the user row and, by cascade, every row they own."""
    user = session.get(AppUser, user_id)
    if user is not None:
        session.delete(user)
        session.flush()


def active_user(session: Session, user_id: uuid.UUID) -> AppUser:
    user = session.get(AppUser, user_id)
    if user is None or user.deleted_at is not None:
        raise AuthError("account no longer exists")
    return user
