"""Downloadable packs for offline use: the catalog and the files.

Public (no sign-in): the packs hold the same public-domain texts and
labelled AI explanations that ship in the app. Downloads support HTTP Range,
so the app resumes an interrupted download instead of starting over.
"""

from __future__ import annotations

from fastapi import APIRouter, Request
from fastapi.responses import FileResponse, JSONResponse

from app.api.auth import RateLimitedError
from app.api.deps import client_ip

router = APIRouter(prefix="/v1/packs", tags=["packs"])


class PackNotFound(Exception):
    pass


@router.get("")
def catalog(request: Request):
    """Every pack with its version, size and SHA-256."""
    return JSONResponse(request.app.state.packs.public(), headers={"Cache-Control": "public, max-age=300"})


@router.api_route("/files/{name}", methods=["GET", "HEAD"])
def download(name: str, request: Request):
    path = request.app.state.packs.files.get(name)
    if path is None:
        raise PackNotFound()
    # A resumed download (Range) continues one already counted.
    if "range" not in request.headers and not request.app.state.download_limiter.allow(client_ip(request)):
        raise RateLimitedError("Too many downloads from this network. Try again later.")
    entry = next(e for e in request.app.state.packs.entries if e["url"].endswith(f"/{name}"))
    return FileResponse(
        path,
        media_type="application/octet-stream",
        filename=name,
        headers={"ETag": f'"{entry["sha256"]}"', "Cache-Control": "public, max-age=86400"},
    )
