"""Test database: a fresh Postgres database per test session, migrated with
the real Alembic migration (not metadata.create_all), so tests exercise
exactly what production runs.

Requires Postgres 16 + pgvector. TEST_DATABASE_ADMIN_URL must be a role
allowed to create databases and the vector extension (CI uses the
pgvector/pgvector:pg16 service container).
"""

from __future__ import annotations

import json
import os
import uuid
from pathlib import Path

import pytest
from alembic import command
from alembic.config import Config
from sqlalchemy import create_engine, text
from sqlalchemy.engine import make_url
from sqlalchemy.orm import Session

BACKEND = Path(__file__).resolve().parent.parent
DATASET = BACKEND.parent / "content" / "data" / "gita.json"
ADMIN_URL = os.environ.get(
    "TEST_DATABASE_ADMIN_URL", "postgresql+psycopg://postgres:postgres@localhost:5432/postgres"
)


def alembic_config(url: str) -> Config:
    cfg = Config(str(BACKEND / "alembic.ini"))
    cfg.set_main_option("sqlalchemy.url", url)
    cfg.attributes["configure_logger"] = False
    return cfg


@pytest.fixture(scope="session")
def db_url():
    name = f"gita_test_{uuid.uuid4().hex[:8]}"
    admin = create_engine(ADMIN_URL, isolation_level="AUTOCOMMIT")
    with admin.connect() as c:
        c.execute(text(f'CREATE DATABASE "{name}"'))
    url = make_url(ADMIN_URL).set(database=name).render_as_string(hide_password=False)
    old = os.environ.pop("DATABASE_URL", None)  # env.py must not redirect the migration
    try:
        yield url
    finally:
        if old is not None:
            os.environ["DATABASE_URL"] = old
        with admin.connect() as c:
            c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))
        admin.dispose()


@pytest.fixture(scope="session")
def migrated_url(db_url):
    command.upgrade(alembic_config(db_url), "head")
    return db_url


@pytest.fixture(scope="session")
def engine(migrated_url):
    eng = create_engine(migrated_url)
    yield eng
    eng.dispose()


@pytest.fixture(scope="session")
def dataset() -> dict:
    return json.loads(DATASET.read_text(encoding="utf-8"))


@pytest.fixture(scope="session")
def seeded(engine, dataset):
    from app.modules.content.seed import import_dataset

    with Session(engine) as s, s.begin():
        import_dataset(s, dataset)
    return engine


@pytest.fixture
def session(seeded):
    """A session whose work is rolled back after the test."""
    conn = seeded.connect()
    trans = conn.begin()
    s = Session(bind=conn, join_transaction_mode="create_savepoint")
    try:
        yield s
    finally:
        s.close()
        trans.rollback()
        conn.close()


# ---- API test support -------------------------------------------------------


class ScriptedLLM:
    """A fake provider that replies from a script. Each reply is a dict (sent
    as JSON), a string, an exception to raise, or a function of the messages."""

    def __init__(self, name: str = "fake", replies=None):
        self.name = name
        self.model = f"{name}-model"
        self.replies = list(replies or [])
        self.calls: list[list] = []

    def generate(self, messages, opts=None):
        from app.providers.llm import Completion

        self.calls.append(messages)
        if not self.replies:
            raise AssertionError(f"{self.name}: unexpected LLM call")
        r = self.replies.pop(0)
        if callable(r) and not isinstance(r, type):
            r = r(messages)
        if isinstance(r, Exception):
            raise r
        text_ = r if isinstance(r, str) else json.dumps(r, ensure_ascii=False)
        return Completion(text_, self.name, self.model, 100, 50)

    def stream(self, messages, opts=None):
        raise NotImplementedError


def answer(text_: str = "Act without clinging to results (BG 2.47).", cites=("2.47",), **extra) -> dict:
    return {
        "answer": text_,
        "citations": [{"verse": c, "source_id": "bg-sanskrit-gita-json"} for c in cites],
        "confidence": "medium",
        "uncertain_points": [],
        "out_of_scope": False,
        **extra,
    }


@pytest.fixture
def make_client(seeded):
    """make_client(*providers, **settings) -> (TestClient, router or None)."""
    from fastapi.testclient import TestClient
    from sqlalchemy.orm import sessionmaker

    from app.core.settings import Settings
    from app.main import create_app
    from app.providers.llm import LLMRouter, RoutedProvider

    clients = []

    from gita_content.retrieval import Retriever

    retriever = Retriever(json.loads(DATASET.read_text(encoding="utf-8")))

    def make(*providers, embeddings=None, hybrid=True, **overrides):
        settings = Settings(
            **{
                "database_url": seeded.url.render_as_string(hide_password=False),
                "jwt_secret": "t" * 40,
                "environment": "test",
                "signups_per_ip_per_hour": 1000,
                **overrides,
            }
        )
        llm = LLMRouter([RoutedProvider(p) for p in providers]) if providers else None
        app = create_app(
            settings,
            llm=llm,
            session_factory=sessionmaker(seeded, expire_on_commit=False),
            retriever=retriever if hybrid else None,
            embeddings=embeddings,
        )
        client = TestClient(app)
        clients.append(client)
        return client, llm

    yield make
    for c in clients:
        c.close()
    # API tests commit; keep later tests independent of cached answers.
    with seeded.begin() as conn:
        conn.execute(text("DELETE FROM ai_answer_cache"))


def signup(client) -> dict:
    r = client.post("/v1/auth/anonymous")
    assert r.status_code == 201, r.text
    tokens = r.json()
    tokens["headers"] = {"Authorization": f"Bearer {tokens['access_token']}"}
    return tokens
