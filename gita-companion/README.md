# Gita Companion

An offline-first, audio-first Bhagavad Gita study app (Android APK first)
with a grounded AI teacher. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for the approved design and [docs/PHASE-2.md](docs/PHASE-2.md) for the
current state.

| Directory | What | Status |
|---|---|---|
| `content/` | Content pipeline: canonical Sanskrit text, transliteration, licence register, mobile SQLite pack | Phase 2 ✅ |
| `backend/` | FastAPI modular monolith. Phase 2: database models + migrations | Phase 2 ✅ (DB layer) |
| `mobile/` | Flutter app | Phase 3 |
| `infra/` | Local dev services (Postgres + pgvector) | ✅ |

## Quick start

```bash
# Content: tests + rebuild the mobile pack from the committed dataset (offline)
cd content && pip install -e ".[dev]" && pytest -q && gita-content pack

# Backend database
docker compose -f infra/docker-compose.yml up -d
cd backend && pip install -e ".[dev]"
alembic upgrade head
python -m app.modules.content.seed ../content/data/gita.json
TEST_DATABASE_ADMIN_URL=postgresql+psycopg://gita:gita@localhost:5432/postgres pytest -q
```
