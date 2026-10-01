# Backend

FastAPI modular monolith (API arrives in Phase 6). Currently: the database
layer (SQLAlchemy + Alembic + Postgres/pgvector), the LLM provider layer,
and the batch content generator.

## LLM providers: free tiers only

`llm.yaml` lists the providers, tried in order:

| Provider | Key (environment variable) | Notes |
|---|---|---|
| Google Gemini (free tier) | `GEMINI_API_KEY` | Prompts may be used to improve Google's products on the free tier, so only public scripture text is sent (batch generation). |
| Groq (free tier) | `GROQ_API_KEY` | Hosted open models (Llama); Llama licence applies. |
| OpenRouter (`:free` models) | `OPENROUTER_API_KEY` | Small daily allowance; upstream model licence applies. |
| Ollama (self-hosted) | `OLLAMA_BASE_URL` | Unlimited and private if you run it yourself. |

Free tiers change often. Check model ids, limits and terms before relying
on them, and keep each `daily_request_budget` below the provider's real
limit. A provider without its key is skipped. `<NAME>_MODEL` (for example
`GROQ_MODEL`) overrides a model id without editing the file.

All providers speak the OpenAI-compatible API, so they share one adapter
(`app/providers/llm/openai_compat.py`). The router falls back on rate limits,
errors or invalid output, cools down a rate-limited provider, disables one
with a bad key, and enforces daily budgets.

## Generating explanations

```bash
pip install -e ../content -e ".[dev]"
export GROQ_API_KEY=...            # and/or GEMINI_API_KEY, OPENROUTER_API_KEY
python -m workers.generate_content --dataset ../content/data/gita.json --out ../content/ai \
    --languages en,te --kinds chapter,verse --limit 100
cd ../content && gita-content build --gita-json ... --verify-with ...   # imports content/ai/
```

Or use the manual GitHub workflow **gita-generate-ai** with the keys stored
as repository secrets.

Every answer is checked before it is kept:
- the JSON shape is valid;
- every glossed word and Sanskrit term occurs in the verse (sandhi-tolerant);
- every verse reference exists, and chapter overviews cite only their own chapter;
- the language is right (Telugu answers in Telugu script);
- lengths fall within bounds.

A failing answer gets one repair attempt, then the next provider is tried.
Output is imported as **AI-generated, unreviewed** text, labelled with its
model in the app.

## Tests

```bash
TEST_DATABASE_ADMIN_URL=postgresql+psycopg://postgres:postgres@localhost:5432/postgres pytest -q
```
