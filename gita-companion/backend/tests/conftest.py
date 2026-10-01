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
