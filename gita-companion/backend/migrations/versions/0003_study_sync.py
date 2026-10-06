"""Sync of study data ("My Gita") and account recovery codes.

- sync_seq: a global change counter on every synced table, bumped by a
  trigger on every insert and update. A device asks for "changes after N".
- client_updated_at: when the change was made on the device. Conflicts are
  resolved by it (last write wins); updated_at stays the server's write time.
- bookmark: one row per user and verse (deleting sets deleted_at), so two
  devices bookmarking the same verse meet on the same row.
- app_user.recovery_code_hash: SHA-256 of a recovery code that signs a new
  installation back into the account. The code itself is never stored.

Revision ID: 0003
Revises: 0002
Create Date: 2026-10-06 09:00:00
"""

from collections.abc import Sequence

import sqlalchemy as sa
from alembic import op

revision: str = "0003"
down_revision: str | None = "0002"
branch_labels: str | Sequence[str] | None = None
depends_on: str | Sequence[str] | None = None

# table -> has user_id column
SYNCED = {
    "bookmark": True,
    "highlight": True,
    "note": True,
    "verse_state": True,
    "revision_item": True,
    "revision_review": False,
    "daily_practice": True,
    "verse_read": True,
    "reading_progress": True,
}
# Tables whose rows are edited (last write wins); the others merge.
LWW = ("bookmark", "highlight", "note", "verse_state", "revision_item", "daily_practice", "reading_progress")

SET_SYNC_SEQ = """
CREATE FUNCTION set_sync_seq() RETURNS trigger LANGUAGE plpgsql AS $$
BEGIN
  NEW.sync_seq = nextval('sync_seq');
  RETURN NEW;
END $$;
"""


def upgrade() -> None:
    op.execute("CREATE SEQUENCE sync_seq AS bigint")
    op.execute(SET_SYNC_SEQ)
    for table, has_user in SYNCED.items():
        op.add_column(
            table,
            sa.Column(
                "sync_seq", sa.BigInteger(), server_default=sa.text("nextval('sync_seq')"), nullable=False
            ),
        )
        if table in LWW:
            op.add_column(table, sa.Column("client_updated_at", sa.DateTime(timezone=True), nullable=True))
        cols = ["user_id", "sync_seq"] if has_user else ["sync_seq"]
        op.create_index(op.f(f"ix_{table}_sync"), table, cols)
        op.execute(
            f"CREATE TRIGGER set_sync_seq BEFORE UPDATE ON {table} FOR EACH ROW EXECUTE FUNCTION set_sync_seq()"
        )

    op.drop_index("uq_bookmark_user_verse_live", table_name="bookmark")
    op.create_unique_constraint(op.f("uq_bookmark_user_id_verse_id"), "bookmark", ["user_id", "verse_id"])

    op.add_column("app_user", sa.Column("recovery_code_hash", sa.String(64), nullable=True))
    op.add_column(
        "app_user", sa.Column("recovery_code_created_at", sa.DateTime(timezone=True), nullable=True)
    )
    op.create_unique_constraint(op.f("uq_app_user_recovery_code_hash"), "app_user", ["recovery_code_hash"])


def downgrade() -> None:
    op.drop_constraint(op.f("uq_app_user_recovery_code_hash"), "app_user", type_="unique")
    op.drop_column("app_user", "recovery_code_created_at")
    op.drop_column("app_user", "recovery_code_hash")

    op.drop_constraint(op.f("uq_bookmark_user_id_verse_id"), "bookmark", type_="unique")
    op.create_index(
        "uq_bookmark_user_verse_live",
        "bookmark",
        ["user_id", "verse_id"],
        unique=True,
        postgresql_where=sa.text("deleted_at IS NULL"),
    )
    for table in SYNCED:
        op.execute(f"DROP TRIGGER set_sync_seq ON {table}")
        op.drop_index(op.f(f"ix_{table}_sync"), table_name=table)
        if table in LWW:
            op.drop_column(table, "client_updated_at")
        op.drop_column(table, "sync_seq")
    op.execute("DROP FUNCTION set_sync_seq()")
    op.execute("DROP SEQUENCE sync_seq")
