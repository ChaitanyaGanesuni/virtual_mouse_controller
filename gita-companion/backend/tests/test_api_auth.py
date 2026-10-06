"""Accounts and tokens over HTTP."""

from datetime import UTC, datetime, timedelta

import jwt

from tests.conftest import signup


def test_anonymous_account_gets_working_tokens(make_client):
    client, _ = make_client()
    t = signup(client)
    assert t["token_type"] == "bearer" and t["expires_in"] == 900
    r = client.get("/v1/tutor/status", headers=t["headers"])
    assert r.status_code == 200
    assert r.json() == {"available": False, "daily_limit": 30, "questions_left_today": 30}


def test_requests_without_valid_token_are_rejected(make_client):
    client, _ = make_client()
    assert client.get("/v1/tutor/status").json()["error"]["code"] == "unauthorized"
    r = client.get("/v1/tutor/status", headers={"Authorization": "Bearer not-a-jwt"})
    assert r.status_code == 401 and r.headers["www-authenticate"] == "Bearer"

    t = signup(client)
    claims = jwt.decode(t["access_token"], options={"verify_signature": False})
    # Same claims signed with another key, and an expired token signed with the right key.
    forged = jwt.encode(claims, "x" * 40, algorithm="HS256")
    past = datetime.now(UTC) - timedelta(hours=1)
    expired = jwt.encode(
        {**claims, "iat": int(past.timestamp()), "exp": int(past.timestamp()) + 60},
        "t" * 40,
        algorithm="HS256",
    )
    for token in (forged, expired):
        r = client.get("/v1/tutor/status", headers={"Authorization": f"Bearer {token}"})
        assert r.status_code == 401
    # A token with alg=none must never be accepted.
    unsigned = jwt.encode(claims, None, algorithm="none")
    assert client.get("/v1/tutor/status", headers={"Authorization": f"Bearer {unsigned}"}).status_code == 401


def test_refresh_rotates_and_reuse_revokes_the_family(make_client):
    client, _ = make_client()
    t1 = signup(client)
    r = client.post("/v1/auth/refresh", json={"refresh_token": t1["refresh_token"]})
    assert r.status_code == 200
    t2 = r.json()
    assert t2["refresh_token"] != t1["refresh_token"] and t2["user_id"] == t1["user_id"]

    # The old token is presented again: treated as stolen, and the whole family
    # (including the newest token) is revoked.
    r = client.post("/v1/auth/refresh", json={"refresh_token": t1["refresh_token"]})
    assert r.status_code == 401 and "reused" in r.json()["error"]["message"]
    assert client.post("/v1/auth/refresh", json={"refresh_token": t2["refresh_token"]}).status_code == 401


def test_logout_revokes_refresh_token(make_client):
    client, _ = make_client()
    t = signup(client)
    assert client.post("/v1/auth/logout", json={"refresh_token": t["refresh_token"]}).status_code == 204
    assert client.post("/v1/auth/refresh", json={"refresh_token": t["refresh_token"]}).status_code == 401


def test_unknown_refresh_token_is_rejected(make_client):
    client, _ = make_client()
    r = client.post("/v1/auth/refresh", json={"refresh_token": "x" * 43})
    assert r.status_code == 401


def test_delete_account_removes_everything(make_client):
    client, _ = make_client()
    t = signup(client)
    conv = client.post("/v1/tutor/conversations", json={"pinned_verse_id": "2.47"}, headers=t["headers"])
    assert conv.status_code == 201
    assert client.delete("/v1/me", headers=t["headers"]).status_code == 204
    assert client.get("/v1/tutor/conversations", headers=t["headers"]).status_code == 401
    assert client.post("/v1/auth/refresh", json={"refresh_token": t["refresh_token"]}).status_code == 401


def test_signups_are_rate_limited_per_ip(make_client):
    client, _ = make_client(signups_per_ip_per_hour=2)
    assert client.post("/v1/auth/anonymous").status_code == 201
    assert client.post("/v1/auth/anonymous").status_code == 201
    r = client.post("/v1/auth/anonymous")
    assert r.status_code == 429 and r.json()["error"]["code"] == "rate_limited"
    # Another address is not affected.
    assert client.post("/v1/auth/anonymous", headers={"X-Forwarded-For": "203.0.113.9"}).status_code == 201


def test_health(make_client):
    client, _ = make_client()
    assert client.get("/v1/health").json() == {"status": "ok", "version": "0.8.0", "tutor": False}


def test_production_requires_a_real_secret():
    import pytest

    from app.core.settings import Settings, SettingsError

    with pytest.raises(SettingsError):
        Settings.from_env({"APP_ENV": "production", "JWT_SECRET": "short"})
    assert Settings.from_env({"APP_ENV": "development"}).jwt_secret
