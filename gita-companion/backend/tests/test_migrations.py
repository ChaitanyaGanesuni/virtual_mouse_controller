import uuid

import pytest
from alembic import command
from sqlalchemy import create_engine, inspect, text
from sqlalchemy.engine import make_url

from tests.conftest import ADMIN_URL, alembic_config


@pytest.fixture
def scratch_db_url():
    name = f"gita_mig_{uuid.uuid4().hex[:8]}"
    admin = create_engine(ADMIN_URL, isolation_level="AUTOCOMMIT")
    with admin.connect() as c:
        c.execute(text(f'CREATE DATABASE "{name}"'))
    try:
        yield make_url(ADMIN_URL).set(database=name).render_as_string(hide_password=False)
    finally:
        with admin.connect() as c:
            c.execute(text(f'DROP DATABASE IF EXISTS "{name}" WITH (FORCE)'))
        admin.dispose()


def _tables(url: str) -> set[str]:
    eng = create_engine(url)
    try:
        return set(inspect(eng).get_table_names())
    finally:
        eng.dispose()


def test_upgrade_check_downgrade_roundtrip(scratch_db_url):
    cfg = alembic_config(scratch_db_url)
    command.upgrade(cfg, "head")
    tables = _tables(scratch_db_url)
    assert {"verse", "verse_text", "embedding_doc", "listening_progress", "revision_item"} <= tables
    assert len(tables - {"alembic_version"}) == 34

    # Models and migrations agree (raises if autogenerate would emit anything).
    command.check(cfg)

    command.downgrade(cfg, "base")
    assert _tables(scratch_db_url) == {"alembic_version"}

    command.upgrade(cfg, "head")
    assert _tables(scratch_db_url) == tables
