"""HTTP hardening (Phase 10 security review)."""

from __future__ import annotations

from tests.conftest import signup


def test_security_headers_and_no_caching_of_api_responses(make_client):
    client, _ = make_client()
    r = client.post("/v1/auth/anonymous")
    for header, value in {
        "x-content-type-options": "nosniff",
        "referrer-policy": "no-referrer",
        "x-frame-options": "DENY",
        "strict-transport-security": "max-age=31536000",
        "cache-control": "no-store",  # tokens must not be cached anywhere
    }.items():
        assert r.headers[header] == value, header
    # Public catalog keeps its own caching.
    assert client.get("/v1/packs").headers["cache-control"] == "public, max-age=300"
    # Errors carry the headers too.
    assert client.get("/v1/nope").headers["x-content-type-options"] == "nosniff"


def test_oversized_bodies_are_rejected_before_parsing(make_client):
    client, _ = make_client()
    t = signup(client)
    big = "x" * (1024 * 1024 + 10)
    r = client.post("/v1/auth/refresh", content=big, headers={"content-type": "application/json"})
    assert r.status_code == 413 and r.json()["error"]["code"] == "too_large"

    # Without Content-Length (chunked), the body is counted as it arrives.
    def chunks():
        for _ in range(20):
            yield b"x" * 100_000

    r = client.post("/v1/auth/refresh", content=chunks(), headers={"content-type": "application/json"})
    assert r.status_code == 413

    # Sync may send more, up to its own limit.
    r = client.post(
        "/v1/sync",
        content=b'{"cursor": 0, "changes": {}, "pad": "' + b"x" * (2 * 1024 * 1024) + b'"}',
        headers={**t["headers"], "content-type": "application/json"},
    )
    assert r.status_code == 422, "reaches validation (unknown field), not the size limit"
