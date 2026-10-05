"""Embed the verses for the server's vector channel (optional).

    EMBEDDINGS_BASE_URL=http://localhost:11434/v1 EMBEDDINGS_MODEL=bge-m3 \\
        python -m workers.index_embeddings

Idempotent: only new or changed documents are embedded.
"""

from __future__ import annotations

import sys

from sqlalchemy import create_engine
from sqlalchemy.orm import Session

from app.core.config import database_url
from app.modules.rag.index import index_embeddings
from app.providers.embeddings import from_env


def main() -> int:
    provider = from_env()
    if provider is None:
        print("set EMBEDDINGS_BASE_URL and EMBEDDINGS_MODEL", file=sys.stderr)
        return 2
    engine = create_engine(database_url())
    with Session(engine) as session, session.begin():
        n = index_embeddings(session, provider)
    print(f"ok: {n} documents embedded with {provider.model}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
