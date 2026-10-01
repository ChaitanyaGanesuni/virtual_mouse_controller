#!/bin/sh
# Container entry point: migrate, load the content, serve.
# Every step is idempotent, so restarts and redeploys are safe.
set -e
alembic upgrade head
python -m app.modules.content.seed content/gita.json
exec uvicorn app.main:app --host 0.0.0.0 --port "${PORT:-8000}" \
  --proxy-headers --forwarded-allow-ips='*' --no-server-header
