"""HTTP hardening applied to every response and request (Phase 10 review).

- Security headers: no MIME sniffing, no referrer, never framed, HTTPS
  only (HSTS), and no caching of API responses that may carry tokens or
  personal data (public pack files set their own cache headers).
- A request body limit, so a client cannot make the server buffer an
  arbitrarily large body before validation rejects it. Bodies sent without
  Content-Length (chunked) are counted as they arrive.
"""

from __future__ import annotations

import json

from starlette.types import ASGIApp, Message, Receive, Scope, Send

SECURITY_HEADERS = [
    (b"x-content-type-options", b"nosniff"),
    (b"referrer-policy", b"no-referrer"),
    (b"x-frame-options", b"DENY"),
    (b"strict-transport-security", b"max-age=31536000"),
]

DEFAULT_MAX_BODY = 1 * 1024 * 1024
# Larger bodies are accepted only where they are expected.
MAX_BODY_BY_PATH = {"/v1/sync": 4 * 1024 * 1024}


class HardeningMiddleware:
    def __init__(self, app: ASGIApp):
        self.app = app

    async def __call__(self, scope: Scope, receive: Receive, send: Send) -> None:
        if scope["type"] != "http":
            await self.app(scope, receive, send)
            return
        limit = MAX_BODY_BY_PATH.get(scope["path"], DEFAULT_MAX_BODY)
        headers = dict(scope.get("headers") or [])
        declared = headers.get(b"content-length")
        if declared is not None and declared.isdigit() and int(declared) > limit:
            await _reject(send, limit)
            return

        if declared is None and scope["method"] in ("POST", "PUT", "PATCH"):
            # No declared length (chunked): read it here, up to the limit,
            # then replay it to the app.
            buffered: list[Message] = []
            size = 0
            while True:
                message = await receive()
                buffered.append(message)
                if message["type"] != "http.request":
                    break
                size += len(message.get("body", b""))
                if size > limit:
                    await _reject(send, limit)
                    return
                if not message.get("more_body", False):
                    break

            async def replay() -> Message:
                return buffered.pop(0) if buffered else await receive()

            receive = replay

        async def send_with_headers(message: Message) -> None:
            if message["type"] == "http.response.start":
                existing = {k.lower() for k, _ in message.get("headers", [])}
                extra = [(k, v) for k, v in SECURITY_HEADERS if k not in existing]
                if b"cache-control" not in existing:
                    extra.append((b"cache-control", b"no-store"))
                message["headers"] = [*message.get("headers", []), *extra]
            await send(message)

        await self.app(scope, receive, send_with_headers)


async def _reject(send: Send, limit: int) -> None:
    body = json.dumps(
        {"error": {"code": "too_large", "message": f"request body larger than {limit} bytes"}}
    ).encode()
    await send(
        {
            "type": "http.response.start",
            "status": 413,
            "headers": [
                (b"content-type", b"application/json"),
                *SECURITY_HEADERS,
                (b"cache-control", b"no-store"),
            ],
        }
    )
    await send({"type": "http.response.body", "body": body})
