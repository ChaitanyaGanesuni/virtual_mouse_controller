"""Licence register (sources.yaml). Shipping text from a source that is not
registered, has no licence, or is marked verify-only fails the build."""

from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path

import yaml

SOURCES_PATH = Path(__file__).resolve().parent.parent / "sources.yaml"

KINDS = {
    "scripture",
    "translation",
    "commentary",
    "transliteration",
    "editorial",
    "ai",
    "dataset",
    "recording",
}


class RegistryError(ValueError):
    pass


@dataclass(frozen=True)
class Source:
    id: str
    kind: str
    title: str
    author: str
    language: str
    license: str
    use: str
    license_note: str = ""
    url: str | None = None
    year: int | None = None
    is_ai_generated: bool = False
    status: str = "active"
    retrieved_commit: str | None = None

    def as_row(self) -> dict:
        return {
            "id": self.id,
            "kind": self.kind,
            "title": self.title,
            "author": self.author,
            "year": self.year,
            "language": self.language,
            "license": self.license,
            "license_note": " ".join(self.license_note.split()),
            "url": self.url,
            "retrieved_commit": self.retrieved_commit,
            "is_ai_generated": self.is_ai_generated,
            "model_id": None,
            "prompt_version": None,
        }


class Registry:
    def __init__(self, sources: dict[str, Source], ai_providers: dict[str, dict] | None = None):
        self.sources = sources
        # LLM providers whose (labelled) output may be shipped.
        self.ai_providers = ai_providers or {}

    @classmethod
    def load(cls, path: Path = SOURCES_PATH) -> Registry:
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        sources: dict[str, Source] = {}
        for raw in data["sources"]:
            known = Source.__dataclass_fields__
            src = Source(**{k: v for k, v in raw.items() if k in known})
            if src.id in sources:
                raise RegistryError(f"duplicate source id {src.id}")
            if src.kind not in KINDS:
                raise RegistryError(f"{src.id}: unknown kind {src.kind!r}")
            if not src.license or not str(src.license).strip():
                raise RegistryError(f"{src.id}: missing licence")
            if src.use not in ("ship", "verify"):
                raise RegistryError(f"{src.id}: use must be 'ship' or 'verify'")
            sources[src.id] = src
        return cls(sources, data.get("ai_providers") or {})

    def shippable(self, source_id: str) -> Source:
        src = self.sources.get(source_id)
        if src is None:
            raise RegistryError(f"source {source_id!r} is not in the licence register")
        if src.use != "ship":
            raise RegistryError(f"source {source_id!r} is verify-only and must not be shipped")
        if src.status != "active":
            raise RegistryError(f"source {source_id!r} is {src.status}, not active")
        return src
