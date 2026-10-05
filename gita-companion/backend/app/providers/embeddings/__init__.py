"""Embedding providers (optional).

Semantic search over the verses works without embeddings: the concept index
and keyword search meet the Phase 7 targets on their own. An embedding model
adds a third ranking channel on the server.

Questions are personal, so point this only at a model you trust with them:
a self-hosted Ollama is the free, private choice
(`ollama pull bge-m3`; EMBEDDINGS_BASE_URL=http://host:11434/v1,
EMBEDDINGS_MODEL=bge-m3). The vectors must have EMBEDDING_DIM (1024)
dimensions, the size of bge-m3.
"""

from __future__ import annotations

import os
from typing import Literal, Protocol, runtime_checkable

import httpx

Purpose = Literal["query", "document"]


class EmbeddingError(RuntimeError):
    pass


@runtime_checkable
class EmbeddingProvider(Protocol):
    model: str
    dimensions: int

    def embed(self, texts: list[str], purpose: Purpose) -> list[list[float]]: ...


class OpenAICompatibleEmbeddings:
    """POST {base_url}/embeddings, as served by Ollama, vLLM, LM Studio and
    most hosted APIs."""

    def __init__(
        self,
        base_url: str,
        model: str,
        api_key: str | None = None,
        dimensions: int = 1024,
        client: httpx.Client | None = None,
        timeout_s: float = 60.0,
    ):
        self.base_url = base_url.rstrip("/")
        self.model = model
        self.dimensions = dimensions
        self._key = api_key
        self._client = client or httpx.Client(timeout=timeout_s)

    def embed(self, texts: list[str], purpose: Purpose) -> list[list[float]]:
        headers = {"Authorization": f"Bearer {self._key}"} if self._key else {}
        try:
            r = self._client.post(
                f"{self.base_url}/embeddings", json={"model": self.model, "input": texts}, headers=headers
            )
        except httpx.HTTPError as e:
            raise EmbeddingError(f"embedding request failed: {e}") from e
        if r.status_code != 200:
            raise EmbeddingError(f"embedding request failed: HTTP {r.status_code}")
        data = sorted(r.json()["data"], key=lambda d: d["index"])
        vectors = [d["embedding"] for d in data]
        if len(vectors) != len(texts) or any(len(v) != self.dimensions for v in vectors):
            raise EmbeddingError(f"expected {len(texts)} vectors of {self.dimensions} dimensions")
        return vectors


def from_env(env: dict[str, str] | None = None) -> EmbeddingProvider | None:
    env = dict(os.environ) if env is None else env
    base, model = env.get("EMBEDDINGS_BASE_URL"), env.get("EMBEDDINGS_MODEL")
    if not base or not model:
        return None
    return OpenAICompatibleEmbeddings(base, model, env.get("EMBEDDINGS_API_KEY"))
