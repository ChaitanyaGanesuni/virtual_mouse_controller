"""Downloadable packs: what a phone can fetch for offline use.

The catalog lists each pack with its version, size and SHA-256, so the app
can show what is new, resume an interrupted download (HTTP Range) and
reject a corrupted one.

- The content pack (the same SQLite file that ships in the app) is built
  into the server image from the deployed dataset. New explanations and
  reviewed corrections therefore reach phones without a new app release.
- Packs hosted elsewhere (for example recitation audio in object storage)
  are listed in `extra.json` in the packs directory, with absolute HTTPS
  URLs and their checksums.
"""

from __future__ import annotations

import hashlib
import json
import logging
import sqlite3
from dataclasses import dataclass, field
from pathlib import Path

log = logging.getLogger("gita.packs")

CONTENT_PACK = "gita_content_pack.sqlite"
EXTRA = "extra.json"
_REQUIRED_EXTRA = {"id", "kind", "title", "version", "size", "sha256", "url"}


def sha256_of(path: Path) -> str:
    h = hashlib.sha256()
    with path.open("rb") as f:
        for block in iter(lambda: f.read(1 << 20), b""):
            h.update(block)
    return h.hexdigest()


def _pack_meta(path: Path) -> dict[str, str]:
    db = sqlite3.connect(f"file:{path}?mode=ro", uri=True)
    try:
        return dict(db.execute("SELECT key, value FROM pack_meta").fetchall())
    finally:
        db.close()


@dataclass
class PackCatalog:
    entries: list[dict] = field(default_factory=list)
    # Files this server serves itself: name -> path.
    files: dict[str, Path] = field(default_factory=dict)

    @staticmethod
    def load(directory: Path | None) -> PackCatalog:
        catalog = PackCatalog()
        if directory is None or not directory.is_dir():
            log.warning("no packs directory (%s): the download catalog is empty", directory)
            return catalog
        content = directory / CONTENT_PACK
        if content.exists():
            meta = _pack_meta(content)
            catalog.files[CONTENT_PACK] = content
            catalog.entries.append(
                {
                    "id": "content",
                    "kind": "content",
                    "title": "Texts and explanations",
                    # The build time orders versions; the hash says what is inside.
                    "version": meta["built_at"],
                    "content_hash": meta["content_hash"],
                    "pack_schema_version": int(meta["pack_schema_version"]),
                    "size": content.stat().st_size,
                    "sha256": sha256_of(content),
                    "url": f"/v1/packs/files/{CONTENT_PACK}",
                }
            )
        extra = directory / EXTRA
        if extra.exists():
            for e in json.loads(extra.read_text(encoding="utf-8")):
                missing = _REQUIRED_EXTRA - set(e)
                if missing or not str(e["url"]).startswith("https://"):
                    log.error("skipping pack %s in %s: missing %s or not https", e.get("id"), extra, missing)
                    continue
                catalog.entries.append(e)
        return catalog

    def public(self) -> dict:
        return {"packs": self.entries}
