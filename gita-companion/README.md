# Gita Companion

An offline-first, audio-first Bhagavad Gita study app (Android APK first)
with a grounded AI teacher. See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
for the approved design and the phase reports in [docs/](docs/) for the
current state.

| Directory | What | Status |
|---|---|---|
| `content/` | Content pipeline: canonical Sanskrit text, Besant's English translation (1922), concept index, hybrid retriever and golden-set evaluation, mobile SQLite pack | Phase 7 ✅ except English recall@8 0.594 vs 0.60 ([report](docs/PHASE-7.md)) |
| `backend/` | API: anonymous accounts with recovery codes, study-data sync (notes and journal encrypted at rest), downloadable content packs with resumable downloads, AI teacher with validated citations and hybrid retrieval (optional vector search); free-tier LLM providers; explanation and recitation generators ([deploy for free](docs/DEPLOY.md)) | Phase 9 ✅ |
| `mobile/` | Flutter app: reader, chapters, search by meaning and topics, listening, My Gita (bookmarks, notes, highlights, spaced revision, Daily Practice), downloads for offline listening and content updates; AI teacher and optional sync online; APK built by CI | Phase 9 ✅ ([report](docs/PHASE-9.md)) |
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
