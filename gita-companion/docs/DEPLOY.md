# Deploying the AI teacher server (free)

Everything in the app except the AI teacher works offline. The teacher needs
a small server. This setup costs nothing:

| Piece | Service | Free plan (October 2026; check before relying on it) |
|---|---|---|
| API (Docker) | [Render](https://render.com) web service | 750 instance-hours a month, 512 MB RAM. Sleeps after 15 minutes without traffic; the next request waits 30–60 s while it wakes. |
| Database | [Neon](https://neon.com) Postgres | 0.5 GB storage, 100 compute-hours a month, pgvector included. Suspends when idle. |
| AI model | [Groq](https://console.groq.com) free tier | Daily request limits; the server stops using it for the day when its budget is spent. |

Only providers marked `user_data_ok: true` in `backend/llm.yaml` ever see
user questions (Groq, or your own Ollama). Gemini's and OpenRouter's free
tiers may use prompts for training, so they are used only for batch content
generation from public scripture text.

## 1. Database (Neon)

1. Create a Neon account and a project (region: AWS Asia Pacific Singapore
   is closest to India).
2. Copy the connection string (Dashboard → Connect). It looks like
   `postgresql://user:password@ep-xxx.ap-southeast-1.aws.neon.tech/neondb?sslmode=require`.

The server runs the migrations and imports the 701 verses itself on every
start; there is nothing else to set up.

## 2. AI key (Groq)

Create a free API key at console.groq.com → API Keys.

## 3. API (Render)

1. Render dashboard → **New → Blueprint** → connect this GitHub repository
   and pick the branch. Render reads `render.yaml` at the repository root.
2. When asked, paste `DATABASE_URL` (from Neon) and `GROQ_API_KEY`.
   `JWT_SECRET` is generated for you.
3. Deploy. When it is live, open `https://<your-service>.onrender.com/v1/health`.
   You should see `{"status":"ok", ..., "tutor":true}`. If `tutor` is
   `false`, the AI key is missing.

## 4. Point the app at it

Either:
- **In the app:** Settings → AI teacher → Server address →
  `https://<your-service>.onrender.com`; or
- **At build time:** in GitHub, Settings → Secrets and variables →
  Actions → **Variables**, add `GITA_API_BASE_URL` with that address. Every
  APK built by CI then has it built in.

The address must be HTTPS. The app accepts plain HTTP only for a server on
your own computer during development (`http://10.0.2.2:8000` from the
Android emulator).

## Settings (environment variables)

| Variable | Default | Meaning |
|---|---|---|
| `DATABASE_URL` | — | Postgres connection string (`postgres://`, `postgresql://` or `postgresql+psycopg://`). |
| `DATA_ENCRYPTION_KEY` | — | Required in production (32+ random characters; the Render blueprint generates it). Encrypts synced notes and journal entries. Keep it: changing or losing it makes them unreadable. |
| `JWT_SECRET` | — | Required in production, at least 32 random characters. Changing it signs every device out (they sign in again automatically). |
| `GROQ_API_KEY` | — | Enables Groq. Others: `OLLAMA_BASE_URL` for a self-hosted model. |
| `SYNCS_PER_USER_PER_HOUR` | 240 | Study-data sync requests per account. |
| `TUTOR_DAILY_QUESTIONS` | 30 | Questions per device per UTC day. Cached explanations don't count. |
| `SIGNUPS_PER_IP_PER_HOUR` | 10 | New anonymous accounts per network address. |
| `SIGNUPS_PER_HOUR_TOTAL` | 300 | New accounts per hour overall (a backstop, since addresses can be forged). |
| `CONTENT_DATASET` | `content/gita.json` in the image | The dataset the tutor's retriever is built from (the same file the database is seeded from). |
| `EMBEDDINGS_BASE_URL`, `EMBEDDINGS_MODEL` | — | Optional vector search: any OpenAI-compatible `/embeddings` endpoint, e.g. Ollama with `bge-m3` (`http://host:11434/v1`, 1024 dimensions). Then run `python -m workers.index_embeddings` once (and after content updates). Off by default; retrieval works without it. |
| `EMBEDDINGS_API_KEY` | — | Only if the embeddings endpoint needs one. |
| `APP_ENV` | production | `development` enables `/docs` and allows a missing `JWT_SECRET`. |

## Running it locally

```bash
cd gita-companion
docker compose -f infra/docker-compose.yml up -d postgres   # or any Postgres 16 with pgvector
docker build -f backend/Dockerfile -t gita-api .
docker run --rm --network host \
  -e DATABASE_URL=postgresql://gita:gita@localhost:5432/gita \
  -e APP_ENV=development -e GROQ_API_KEY=... gita-api
```

## Costs and limits to keep in mind

- **Cold starts.** After 15 idle minutes the first question waits for Render
  to wake (up to a minute). The app tells the user and allows 100 s before
  giving up.
- **Free AI quotas.** When the day's Groq budget is used up, the teacher
  answers "busy, try later" until the next day. Cached explanations still
  work. Add a second approved provider (e.g. your own Ollama) to raise the
  limit.
- **One instance.** Rate limits are kept in memory; that is right for one
  free instance. More instances would need Redis.
