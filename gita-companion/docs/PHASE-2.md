# Phase 2 report: Database + Gita content model

## What was built

**Content pipeline** (`content/`, Python)

- Canonical chapter table: standard 700-verse numbering. Arjuna's question
  at the start of Chapter 13 is stored as non-canonical verse **13.0**, and
  an alias table maps the 701-verse numbering (13.1 → 13.0, 13.2 → 13.1, …).
  Every verse reference is validated against this table.
- Licence register (`sources.yaml`): text from an unregistered, unlicensed,
  planned or verify-only source fails the build.
- Devanagari normaliser and parser: dandas, embedded verse numbers in
  Latin or Devanagari digits, speaker headings (*X uvāca*, including the
  sandhi form *bhagavān uvāca*), one half-verse per line.
- Sanskrit text from the gita/gita dataset (Unlicense; Sanskrit text is
  public domain), cross-checked word for word against an independent
  transcription (vedicscriptures, used for verification only).
- Deterministic IAST and Telugu-script transliteration (no AI).
- Mobile content pack (SQLite) with full-text search across Devanagari,
  IAST, informal romanisation and Telugu script, plus substring search
  inside long Sanskrit compounds.

**Backend database layer** (`backend/`, SQLAlchemy 2 + Alembic + Postgres 16 + pgvector)

- 34 tables covering every entity in the ER design: content, audio
  assets/manifests/chunks, RAG embedding documents (HNSW cosine index +
  generated `tsvector`), users/settings/refresh tokens, bookmarks,
  highlights, notes, verse states, spaced repetition (fits both a fixed
  ladder and FSRS), reading and listening progress, AI conversations,
  validated citations, answer cache, daily practice.
- Database-enforced rules, among them: verse ids must match chapter.verse,
  verse numbers must lie inside the chapter (trigger), one live bookmark
  per verse, valid highlight ranges, allowed playback speeds, SHA-256 audio
  hashes, assistant messages must record their model, `updated_at`
  maintained by trigger for sync.
- Idempotent importer from `content/data/gita.json`.

**CI** (`.github/workflows/gita-companion.yml`): lint + tests for both
packages; backend tests run against a pgvector Postgres service; the
content job re-fetches the pinned upstream sources, rebuilds, and fails if
the committed dataset is not reproduced exactly.

## Tests

| Package | Tests | Notes |
|---|---|---|
| content | 78 | parser, legacy repairs, canon, errata safety, licence rules, build failures, pack search |
| backend | 30 | migration upgrade → `alembic check` → downgrade → upgrade; import; constraints; triggers; vector + full-text queries |

## Problems found and how they were handled

1. **The base Sanskrit dataset had systematic encoding damage** from a
   legacy (pre-Unicode) font conversion: the i-vowel sign stored in the
   wrong position (`निश्िचतं` for `निश्चितं`, 25 cases), `श्रृ` for `शृ`
   (14), long ṝ encoded as ṛ + nukta, and a stray nukta. Fixed by
   unambiguous, rule-based repairs (43 verses), each recorded per verse.
2. **About 20 real errors remained** (typos, wrong sandhi, a missing ॐ in
   17.23, `असुरीं` for `आसुरीं` in 16.20, a verse boundary moved between
   1.20 and 1.21, and a speaker heading misplaced in 1.28). They are
   corrected in `corrections/sanskrit-errata.yaml`, each with a reason, and
   only where the independent transcription has the standard reading.
   Moving text between verses is checked letter for letter, so a
   correction can move text but never add or drop any.
3. **Genuine variant readings** (1.19, 2.64, 8.7, 18.68) were *not*
   "corrected". The base reading is kept and they are listed for human
   review. Eight places where the verification source itself was wrong are
   also listed.
4. Result of the cross-check: 584 identical, 101 differing only in
   spelling conventions, 4 equivalent spellings, 4 variants, 8 verifier
   errors, **0 unexplained**. Any future unexplained difference fails the
   build.
5. **No public-domain English translation could be imported**, because
   this environment's network policy blocks en.wikisource.org,
   archive.org and gutenberg.org. The translation importer (verse-aligned
   JSONL) is built and tested; Besant (1922) is registered as `planned`.
6. pgvector needs a superuser to install. Tests create their own database
   through an admin connection; production installs the extension at
   provisioning (as managed Postgres providers do).
7. The informal-spelling fold cannot match both "krishna" and "krsna" to
   *kṛṣṇa* without merging unrelated words. "krishna" (by far the more
   common spelling) is supported; this is documented as a known
   limitation.

## Open items needing a human

- **Sanskrit review:** the 18 corrected verses are `pending`, and the 4
  variant readings need a decision. See `content/data/sanskrit-report.md`.
- **English translation text:** allow en.wikisource.org in the cloud
  environment's network settings (or provide the text), then run the
  importer.
- Chapter-title English glosses are project-written (flagged as
  AI-assisted, `unreviewed`).

## Deviations from the architecture document

- Backend modules keep their ORM models in `app/modules/<module>/models.py`.
  The `domain/` and `application/` layers will be added when the modules
  get behaviour (Phase 6), so no empty layers exist yet.
- The mobile drift schema is not part of Phase 2. The app opens the
  content pack directly; the app's own user-data tables come with the
  Flutter shell in Phase 3.
