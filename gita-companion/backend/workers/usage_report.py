"""What the deployed server actually uses: AI teacher answers and tokens
per provider, answer-cache hits, accounts, and database size. Read-only.

    DATABASE_URL=... python -m workers.usage_report [--days 30]

Compare with the free tiers in docs/PHASE-10.md (Costs).
"""

from __future__ import annotations

import argparse

from sqlalchemy import create_engine, text

from app.core.config import database_url

QUERIES = {
    "answers by provider": """
        SELECT provider, model_id, count(*) AS answers,
               round(avg(tokens_in)) AS avg_in, round(avg(tokens_out)) AS avg_out,
               coalesce(sum(tokens_in + tokens_out), 0) AS total_tokens
        FROM ai_message
        WHERE role = 'assistant' AND created_at > now() - make_interval(days => :days)
        GROUP BY provider, model_id ORDER BY answers DESC""",
    "busiest days": """
        SELECT date_trunc('day', created_at)::date AS day, count(*) AS answers,
               count(*) FILTER (WHERE provider <> 'cache') AS model_calls
        FROM ai_message
        WHERE role = 'assistant' AND created_at > now() - make_interval(days => :days)
        GROUP BY 1 ORDER BY answers DESC LIMIT 5""",
    "accounts": """
        SELECT count(*) AS accounts,
               count(*) FILTER (WHERE recovery_code_hash IS NOT NULL) AS with_recovery_code,
               count(*) FILTER (WHERE last_seen_at > now() - make_interval(days => :days)) AS active
        FROM app_user WHERE deleted_at IS NULL""",
    "database size": "SELECT pg_size_pretty(pg_database_size(current_database())) AS size",
}


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="usage_report")
    ap.add_argument("--days", type=int, default=30)
    args = ap.parse_args(argv)
    engine = create_engine(database_url())
    with engine.connect() as c:
        for title, sql in QUERIES.items():
            rows = c.execute(text(sql), {"days": args.days}).mappings().all()
            print(f"\n## {title} (last {args.days} days)" if "days" in sql else f"\n## {title}")
            for r in rows:
                print("  " + ", ".join(f"{k}={v}" for k, v in r.items()))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
