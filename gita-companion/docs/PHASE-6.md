# Phase 6 report: Backend API and AI teacher

Exit criterion: *every answer shows validated sources; invalid references
are rejected in tests.* Met. The server will not return an answer that
mentions a verse that does not exist, or one the model was not shown. Every
answer reaches the app with a checked source list, and 41 backend tests and
8 widget tests exercise this.

## What was built

### Server (`backend/app`, FastAPI)

- **Accounts without personal data.**
  - The phone creates an anonymous account on first use of the teacher.
  - Access tokens are signed JWTs valid for 15 minutes.
  - Refresh tokens are random, stored only as hashes, and rotate on every use.
  - If an old refresh token is presented again, the whole token family is
    revoked, which detects token theft.
  - `DELETE /v1/me` erases the account and everything stored for it.
  - New accounts are rate-limited per network address and overall.
- **AI teacher endpoints.**
  - Create, list, read and delete conversations.
  - Ask a question.
  - Explain the pinned verse in a mode (Simple, Deeper, Practical, Story,
    For children, Sanskrit terms), or chat freely.
- **Retrieval (Phase 6 version).** The model gets only the real text from
  the database:
  - the verse the chat is about, plus its neighbours;
  - verses or chapters named in the question;
  - verses cited earlier in the conversation;
  - keyword matches in translations and explanations;
  - as a last resort, verse numbers the model suggests. These are checked
    against the verse table, and the model then sees their real text.
  - Every passage has an ID such as `BG 2.47 | sanskrit | bg-sanskrit-gita-json`.
- **Grounding contract, enforced in code.** The model must reply with JSON:
  answer, citations, confidence, uncertain points, out-of-scope. Before an
  answer is accepted:
  - **rejected and sent back for repair** (then the next provider):
    - a reference to a verse that does not exist (2.99, 19.1, chapter 20);
    - a reference to a verse not among the passages;
    - no citation at all;
    - the wrong language or script;
  - **cleaned and flagged in the app:**
    - invalid entries in the citation list are removed;
    - a citation's source must be a passage of that verse;
    - verses mentioned in the text are added to the sources;
    - quotations that match no passage lose their quotation marks, so they
      read as paraphrase;
  - if no provider produces a valid answer, the user is told so. Nothing
    unverified is stored or shown.
- **Privacy.** User questions go only to providers marked
  `user_data_ok: true`: Groq, or your own Ollama. Free tiers that may train
  on prompts (Gemini, OpenRouter) are excluded automatically.
- **Cost controls.**
  - Each device gets 30 questions a day, configurable.
  - Free-tier daily budgets apply per provider.
  - The first question of a verse chat is cached across all users, so
    "Explain 2.47 simply" costs one model call, ever. Cached answers don't
    count against the quota.
- **Safety.** A question that suggests self-harm adds a support note above
  the answer. It gives Tele-MANAS, India's free national mental-health
  helpline (14416 / 1800-891-4416, 24×7), and 112, in English or Telugu.
  The answer itself is still given.
- **Deployment.**
  - A Dockerfile whose entry point migrates the database, imports the
    content and serves the API.
  - A Render blueprint (`render.yaml`) and a Neon guide in
    [DEPLOY.md](DEPLOY.md). Both are free tiers.
  - CI now also builds the container.
- **Migration 0002:** `ai_message.meta` (confidence, validation flags,
  retrieval methods, support note).

### App

- **AI Gita teacher screen.**
  - The question appears immediately, with a "thinking" note that warns
    the first answer may take a minute while the free server wakes.
  - Answers carry an *AI-generated interpretation · model · date* label and
    a **"Sources, checked against the verse text"** row of verse chips that
    open the verse.
  - They also show uncertain points, notices about removed references or
    quotations, and the support note when present.
  - Answers are displayed in paragraphs and bullet points, and the text
    can be selected.
- **Entry points:**
  - Home → "Ask the AI teacher".
  - Verse screen → "Ask about this verse".
  - When an explanation mode has no text yet → "Explain with the AI
    teacher", in that mode.
- **Past conversations**, which can be reopened and deleted.
- **Settings → AI teacher:** a server address (HTTPS only), a privacy note,
  and "Delete my AI teacher data".
- **Security:**
  - Tokens are kept in the Android Keystore (flutter_secure_storage).
  - A network security config forbids plain HTTP except to the
    development machine.
  - Tokens are bound to the server that issued them.
  - Refresh and sign-up happen one at a time (refresh tokens are
    single-use).
  - App backup is disabled, so tokens are not copied to other devices.
  - The INTERNET permission was added for the teacher only; everything
    else remains offline.
- **Database schema v3** (the server address setting), with a migration
  from v1 and v2.

## Tests

| Package | Tests | New in Phase 6 |
|---|---|---|
| backend | 110 | 9 auth (expired, forged and `alg=none` tokens, rotation, reuse detection, logout, deletion, rate limits), 27 tutor API, 5 unit (reference parsing, quote matching, safety) |
| mobile | 111 | 12 API client (sign-in, refresh, single-flight, re-sign-up, server binding, errors, deletion, HTTPS rules), 8 tutor UI, v2→v3 migration |
| content | 87 | unchanged |

I also built the Docker image and ran it against a fresh database with a
Neon-style `postgresql://` address. The migrations ran, all 701 verses were
imported, and sign-in, status and conversation creation worked over HTTP.

## Problems found and fixed

1. **A detected token theft would have been undone.** The revocation ran
   inside the failing request's transaction and was rolled back with it.
   It now commits separately, and a test checks it.
2. **Transactions committed after the response was sent**, so a failed
   commit could have been reported as success. Requests now commit first.
3. **Neon and Render hand out `postgresql://` addresses**, which would have
   loaded a database driver we don't ship. The address is now normalised;
   `%` in passwords is escaped for Alembic.
4. **An extra "suggest verses" model call ran whenever retrieval found only
   one verse.** It now runs only when nothing was found, which halves the
   cost of follow-up questions.
5. **`Retry-After` was missing or off by one** when a provider was cooling
   down.
6. **Deleting a conversation crashed the history screen** (`setState`
   received a Future). Found by a widget test.
7. **Two simultaneous first requests would have created two accounts.**
   Sign-up is now single-flight, like refresh.
8. **SQLAlchemy 2.1 rejected `dict(result)`.**
9. **The Home teacher card pushed "Continue listening" off screen.**
   Resuming audio now stays above it.
10. **The helpline note claimed Telugu-language support**, which I could not
    verify. It now says "many Indian languages".

## Limitations and decisions for you

- **The server is not deployed.** I can't create Render, Neon or Groq
  accounts for you. Follow [DEPLOY.md](DEPLOY.md) (about 15 minutes), then
  enter the address in the app or set `GITA_API_BASE_URL` for CI builds.
  Until then the teacher screen explains that no server is set up.
- **Grounding is only as good as the content.** The database still has no
  public-domain English translation (blocked since Phase 2), and the AI
  explanations have not been generated yet. So for now the teacher reads
  the Sanskrit and IAST itself. Its answers are clearly labelled as AI
  interpretation and cite real verses, but adding Telang's 1882 translation
  and running `gita-generate-ai` would make them noticeably better.
- **Free-question retrieval is basic until Phase 7** (embeddings, hybrid
  search, golden-set evaluation). Questions about a verse are the strong
  case today.
- **Abuse.** Anonymous accounts plus forged `X-Forwarded-For` could spend
  the free daily model budget. The global sign-up cap and per-provider
  budgets bound this: the worst case is "teacher busy until tomorrow",
  never a bill. Play Integrity checks could be added later.
- **Not built yet:** streaming answers (they arrive whole), Google or email
  sign-in, and syncing conversations for offline reading. These belong to
  Phases 8 and 9.
