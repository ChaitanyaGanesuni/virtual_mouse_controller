-- Gita Companion mobile content pack (SQLite, read-only on device).
--
-- Mirrors the content tables of the backend Postgres schema
-- (backend/migrations) so ids and semantics are identical on both sides.
-- User data (bookmarks, notes, progress ...) is NOT in the pack: it lives
-- in the app's own database, which references verse ids / verse_text ids.
--
-- Bump PACK_SCHEMA_VERSION in pack.py when this file changes.
-- v2: source.model_id/prompt_version, word meanings, explanations in verse_fts.

PRAGMA foreign_keys = ON;

CREATE TABLE pack_meta (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE source (
  id               TEXT PRIMARY KEY,
  kind             TEXT NOT NULL CHECK (kind IN ('scripture','translation','commentary',
                     'transliteration','editorial','ai','dataset','recording')),
  title            TEXT NOT NULL,
  author           TEXT NOT NULL,
  year             INTEGER,
  language         TEXT NOT NULL,
  license          TEXT NOT NULL,
  license_note     TEXT NOT NULL DEFAULT '',
  url              TEXT,
  retrieved_commit TEXT,
  is_ai_generated  INTEGER NOT NULL DEFAULT 0 CHECK (is_ai_generated IN (0,1)),
  model_id         TEXT,                                -- AI sources: model that wrote the text
  prompt_version   TEXT,                                -- AI sources: prompt it was written with
  -- Model output must always say which model and prompt produced it.
  CHECK (kind <> 'ai' OR (is_ai_generated = 1 AND model_id IS NOT NULL AND prompt_version IS NOT NULL))
);

CREATE TABLE chapter (
  number      INTEGER PRIMARY KEY CHECK (number BETWEEN 1 AND 18),
  name_sa     TEXT NOT NULL,
  verse_count INTEGER NOT NULL CHECK (verse_count > 0)
);

CREATE TABLE chapter_text (
  id            TEXT PRIMARY KEY,
  chapter       INTEGER NOT NULL REFERENCES chapter(number),
  source_id     TEXT NOT NULL REFERENCES source(id),
  kind          TEXT NOT NULL CHECK (kind IN ('name','title','summary','theme')),
  language      TEXT NOT NULL,
  body          TEXT NOT NULL,
  review_status TEXT NOT NULL CHECK (review_status IN ('unreviewed','pending','reviewed','rejected')),
  UNIQUE (chapter, source_id, kind, language)
);

CREATE TABLE speaker (
  id           TEXT PRIMARY KEY,
  name_en      TEXT NOT NULL,
  line_sa      TEXT NOT NULL,
  line_sa_latn TEXT NOT NULL,
  line_sa_telu TEXT NOT NULL
);

CREATE TABLE verse (
  id            TEXT PRIMARY KEY,                       -- '2.47'
  chapter       INTEGER NOT NULL REFERENCES chapter(number),
  verse         INTEGER NOT NULL CHECK (verse >= 0),
  is_canonical  INTEGER NOT NULL CHECK (is_canonical IN (0,1)),
  speaker       TEXT REFERENCES speaker(id),            -- 'X uvāca' heading before the verse
  sanskrit      TEXT NOT NULL,                          -- Devanagari, one half-verse per line
  source_id     TEXT NOT NULL REFERENCES source(id),
  review_status TEXT NOT NULL CHECK (review_status IN ('unreviewed','pending','reviewed','rejected')),
  UNIQUE (chapter, verse),
  CHECK (id = chapter || '.' || verse)
);

CREATE TABLE verse_alias (
  edition  TEXT NOT NULL,
  ref      TEXT NOT NULL,
  verse_id TEXT NOT NULL REFERENCES verse(id),
  PRIMARY KEY (edition, ref)
);

-- Every rendering of a verse other than the Devanagari itself: transliterations,
-- translations, explanations, commentary, AI explanations. Adding a translation
-- or a language is inserting rows, never a schema change.
CREATE TABLE verse_text (
  id            TEXT PRIMARY KEY,                       -- deterministic UUIDv5
  verse_id      TEXT NOT NULL REFERENCES verse(id),
  source_id     TEXT NOT NULL REFERENCES source(id),
  kind          TEXT NOT NULL CHECK (kind IN ('transliteration','literal_translation','translation',
                  'simple','deep','practical','story','child','sanskrit_terms','commentary')),
  language      TEXT NOT NULL,                          -- BCP-47: en, te, sa-Latn, sa-Telu
  body          TEXT NOT NULL,
  review_status TEXT NOT NULL CHECK (review_status IN ('unreviewed','pending','reviewed','rejected')),
  UNIQUE (verse_id, source_id, kind, language)
);
CREATE INDEX verse_text_verse ON verse_text(verse_id, kind, language);

CREATE TABLE word_meaning (
  id        TEXT PRIMARY KEY,
  verse_id  TEXT NOT NULL REFERENCES verse(id),
  source_id TEXT NOT NULL REFERENCES source(id),
  position  INTEGER NOT NULL CHECK (position >= 0),
  word_sa   TEXT NOT NULL,
  language  TEXT NOT NULL,
  meaning   TEXT NOT NULL,
  UNIQUE (verse_id, source_id, language, position)
);

CREATE TABLE concept (
  id      TEXT PRIMARY KEY,                             -- 'karma-yoga'
  term_sa TEXT
);

CREATE TABLE concept_text (
  concept_id TEXT NOT NULL REFERENCES concept(id),
  source_id  TEXT NOT NULL REFERENCES source(id),
  language   TEXT NOT NULL,
  name       TEXT NOT NULL,
  definition TEXT,
  PRIMARY KEY (concept_id, source_id, language)
);

CREATE TABLE verse_concept (
  verse_id   TEXT NOT NULL REFERENCES verse(id),
  concept_id TEXT NOT NULL REFERENCES concept(id),
  source_id  TEXT NOT NULL REFERENCES source(id),
  weight     REAL NOT NULL DEFAULT 1.0,
  PRIMARY KEY (verse_id, concept_id, source_id)
);

-- Query side of the concept index (pack schema v3). `term_key` is the
-- normalised form the app compares queries with: stemmed English words, or
-- Telugu words with one common ending removed (gita_content.concepts.term_key).
-- `weak` terms are generic words ("god", "work") that only hint at a concept.
CREATE TABLE concept_term (
  concept_id TEXT NOT NULL REFERENCES concept(id),
  language   TEXT NOT NULL CHECK (language IN ('en', 'te')),
  term_key   TEXT NOT NULL,
  weak       INTEGER NOT NULL DEFAULT 0 CHECK (weak IN (0, 1)),
  PRIMARY KEY (concept_id, language, term_key)
);
CREATE INDEX ix_concept_term_key ON concept_term(term_key);

CREATE TABLE concept_related (
  concept_id TEXT NOT NULL REFERENCES concept(id),
  related_id TEXT NOT NULL REFERENCES concept(id),
  PRIMARY KEY (concept_id, related_id),
  CHECK (concept_id <> related_id)
);

CREATE TABLE verse_relation (
  from_verse TEXT NOT NULL REFERENCES verse(id),
  to_verse   TEXT NOT NULL REFERENCES verse(id),
  relation   TEXT NOT NULL CHECK (relation IN ('parallel','elaborates','contrasts','continues')),
  source_id  TEXT NOT NULL REFERENCES source(id),
  PRIMARY KEY (from_verse, to_verse, relation),
  CHECK (from_verse <> to_verse)
);

-- Full-text search.
-- verse_fts: word and prefix search. remove_diacritics folds IAST
--   ("phalesu" finds "phaleṣu"); `roman_loose` adds the informal spellings
--   people actually type ("phaleshu", "kadachana").
-- verse_fts_sub: trigram index for substrings inside long Sanskrit
--   compounds ("धिकार" inside "कर्मण्येवाधिकारस्ते").
CREATE VIRTUAL TABLE verse_fts USING fts5(
  verse_id UNINDEXED, sanskrit, iast, roman_loose, telugu_script, translation, explanation,
  tokenize = 'unicode61 remove_diacritics 2'
);
CREATE VIRTUAL TABLE verse_fts_sub USING fts5(
  verse_id UNINDEXED, sanskrit, roman_loose, telugu_script,
  tokenize = 'trigram'
);
