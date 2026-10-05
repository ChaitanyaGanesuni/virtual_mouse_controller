"""Optional vector channel: provider adapter, indexing into pgvector, search,
and its use by the tutor. A deterministic fake embedder stands in for a real
model (bag of words hashed into EMBEDDING_DIM buckets)."""

import hashlib
import json
import math

import httpx
import pytest
from sqlalchemy import delete, func, select

from app.modules.rag.index import index_embeddings, vector_search, verse_documents
from app.modules.rag.models import EMBEDDING_DIM, EmbeddingDoc
from app.providers.embeddings import EmbeddingError, OpenAICompatibleEmbeddings, from_env
from tests.conftest import ScriptedLLM, answer, signup


class FakeEmbedder:
    model = "fake-bow"
    dimensions = EMBEDDING_DIM

    def __init__(self):
        self.calls = []

    def embed(self, texts, purpose):
        self.calls.append((purpose, len(texts)))
        out = []
        for t in texts:
            v = [0.0] * EMBEDDING_DIM
            for w in t.lower().replace(",", " ").replace(".", " ").split():
                v[int(hashlib.md5(w.encode()).hexdigest(), 16) % EMBEDDING_DIM] += 1.0
            n = math.sqrt(sum(x * x for x in v)) or 1.0
            out.append([x / n for x in v])
        return out


def test_openai_compatible_adapter():
    seen = []

    def handler(request: httpx.Request) -> httpx.Response:
        body = json.loads(request.content)
        seen.append((body["model"], request.headers.get("authorization")))
        data = [{"index": i, "embedding": [float(i)] * 4} for i in range(len(body["input"]))]
        return httpx.Response(200, json={"data": list(reversed(data))})

    p = OpenAICompatibleEmbeddings(
        "http://x/v1",
        "bge-m3",
        "k",
        dimensions=4,
        client=httpx.Client(transport=httpx.MockTransport(handler)),
    )
    assert p.embed(["a", "b"], "query") == [[0.0] * 4, [1.0] * 4]  # ordered by index
    assert seen == [("bge-m3", "Bearer k")]

    wrong = OpenAICompatibleEmbeddings(
        "http://x/v1", "m", dimensions=3, client=httpx.Client(transport=httpx.MockTransport(handler))
    )
    with pytest.raises(EmbeddingError, match="dimensions"):
        wrong.embed(["a"], "query")
    down = OpenAICompatibleEmbeddings(
        "http://x/v1", "m", client=httpx.Client(transport=httpx.MockTransport(lambda r: httpx.Response(503)))
    )
    with pytest.raises(EmbeddingError, match="503"):
        down.embed(["a"], "document")


def test_configuration_from_environment():
    assert from_env({}) is None
    p = from_env({"EMBEDDINGS_BASE_URL": "http://ollama:11434/v1", "EMBEDDINGS_MODEL": "bge-m3"})
    assert p.model == "bge-m3" and p.dimensions == EMBEDDING_DIM


def test_documents_carry_translation_and_topics(session):
    docs = {d["verse_id"]: d for d in verse_documents(session) if d["facet"] == "translation"}
    assert len(docs) == 701
    assert docs["2.63"]["body"].startswith("From anger proceedeth delusion")
    assert "Anger" in docs["2.63"]["metadata_"]["concepts"]


def test_index_is_idempotent_and_search_finds_neighbours(session):
    fake = FakeEmbedder()
    assert index_embeddings(session, fake, log=lambda m: None) == 701
    assert index_embeddings(session, fake, log=lambda m: None) == 0  # nothing changed
    hits = vector_search(session, fake, "anger delusion memory", k=5)
    assert "2.63" in hits
    assert session.scalar(select(func.count()).select_from(EmbeddingDoc)) == 701


def test_tutor_uses_the_vector_channel(make_client, seeded):
    from sqlalchemy.orm import Session

    fake = FakeEmbedder()
    with Session(seeded) as s, s.begin():
        index_embeddings(s, fake, log=lambda m: None)
    try:
        llm = ScriptedLLM(replies=[answer("Anger clouds judgement (BG 2.63).", cites=("2.63",))])
        client, _ = make_client(llm, embeddings=fake)
        t = signup(client)
        conv = client.post("/v1/tutor/conversations", json={}, headers=t["headers"]).json()["id"]
        r = client.post(
            f"/v1/tutor/conversations/{conv}/messages",
            json={"question": "anger delusion memory"},
            headers=t["headers"],
        )
        assert r.status_code == 200, r.text
        assert ("query", 1) in fake.calls
        assert "BG 2.63 | translation" in llm.calls[0][-1].content
    finally:
        with Session(seeded) as s, s.begin():
            s.execute(delete(EmbeddingDoc))


def test_embedding_failure_does_not_break_answers(make_client):
    class Broken(FakeEmbedder):
        def embed(self, texts, purpose):
            raise EmbeddingError("down")

    llm = ScriptedLLM(replies=[answer("Anger clouds judgement (BG 2.63).", cites=("2.63",))])
    client, _ = make_client(llm, embeddings=Broken())
    t = signup(client)
    conv = client.post("/v1/tutor/conversations", json={}, headers=t["headers"]).json()["id"]
    r = client.post(
        f"/v1/tutor/conversations/{conv}/messages",
        json={"question": "How do I control my anger?"},
        headers=t["headers"],
    )
    assert r.status_code == 200 and r.json()["answer"]["retrieval"] == ["hybrid"]
