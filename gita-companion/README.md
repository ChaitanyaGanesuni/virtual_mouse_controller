# Gita Companion

An offline-first, audio-first Bhagavad Gita study app (Android APK first)
with a grounded AI teacher. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for the approved design and the phase reports in [docs/](docs/) for the
current state.

| Directory | What | Status |
|---|---|---|
| `content/` | Content pipeline: canonical Sanskrit text, Besant's English translation (1922), concept index, hybrid retriever and golden-set evaluation, mobile SQLite pack | Phase 7 ✅ except English recall@8 0.594 vs 0.60 ([report](docs/PHASE-7.md)) |
| `backend/` | API: anonymous accounts, AI teacher with validated citations and hybrid retrieval (optional vector search); free-tier LLM providers; explanation and recitation generators ([deploy for free](docs/DEPLOY.md)) | Phase 7 ✅ |
| `mobile/` | Flutter app: reader, chapters, search by meaning and topics, listening (offline) and the AI teacher (online); APK built by CI | Phase 7 ✅ |
| `infra/` | Local dev services (Postgres + pgvector) | ✅ |

## Quick start

```bash
# Content: tests + rebuild the mobile pack from the committed dataset (offline)
cd content && pip install -e ".[dev]" && pytest -q && gita-content pack
python -m gita_content.evaluate   # retrieval quality on the golden set

# Backend database
docker compose -f infra/docker-compose.yml up -d
cd backend && pip install -e ".[dev]"
alembic upgrade head
python -m app.modules.content.seed ../content/data/gita.json
TEST_DATABASE_ADMIN_URL=postgresql+psycopg://gita:gita@localhost:5432/postgres pytest -q
```
