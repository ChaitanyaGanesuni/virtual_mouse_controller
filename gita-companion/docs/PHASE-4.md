# Phase 4 report: Chapter screen, verse reader, search, free-tier LLM content

Per your instruction, every LLM used is a free tier or self-hosted. Nothing
in this phase costs money.

## What was built

### Free-tier LLM layer (`backend/app/providers/llm/`)
- `LLMProvider` interface, plus one adapter for the OpenAI-compatible API
  that Gemini, Groq, OpenRouter and Ollama all offer.
- `llm.yaml`: the providers in order (Gemini → Groq → OpenRouter → local
  Ollama), with daily request budgets and a per-provider flag for whether
  user data may be sent there. Keys come only from environment variables or
  CI secrets; a provider without a key is skipped.
- Router: falls back to the next provider on errors and rate limits
  (honouring `Retry-After`), disables a provider with a rejected key, and
  enforces daily budgets.
- `generate_structured`: lenient JSON parsing, validation in code, one
  repair attempt, then the next provider.

### Batch generator (`backend/workers/generate_content.py`)
- Per verse and language (English, Telugu), it writes the five explanation
  modes (Simple, Deeper, In practice, Story, For young readers), word-by-word
  meanings and Sanskrit terms. Per chapter, it writes a summary and theme.
- Every answer is validated:
  - glossed words and terms must occur in the verse (sandhi-tolerant);
  - verse references must exist;
  - chapter overviews may cite only their own chapter;
  - Telugu must be in Telugu script;
  - lengths must fall within bounds.
- The generator is resumable (JSONL, finished items skipped) and stops
  cleanly when the free quotas run out. Every record keeps provider, model,
  prompt version and timestamp.
- The manual GitHub workflow `gita-generate-ai` runs it with repository
  secrets, rebuilds the dataset, and uploads or commits the result.

### Content pipeline (format 2, pack schema v2)
- Imports AI output as clearly separate sources: `kind = ai`, model id and
  prompt version recorded, `unreviewed`. A database constraint requires every
  AI source to carry its model and prompt.
- Only providers allow-listed in `sources.yaml` are accepted.
- Editorial chapter overviews (English, all 18 chapters) are now in the
  dataset, labelled AI-assisted and unreviewed.
- Word meanings and explanation text are in the pack, and explanations are
  searchable.

### Mobile app
- **Verse reader:** swipe through all 701 verses across chapters, with the
  position ("Chapter 2 · 47 of 72") and script and text-size controls in the
  toolbar. Sections:
  - Sanskrit (speaker headings);
  - IAST;
  - word by word;
  - translation (an honest notice until one is imported);
  - Understand: the six explanation modes plus an English/Telugu switch. The
    chosen mode is kept while swiping. A missing language is announced
    ("Not yet available in Telugu; showing English").
- **Chapter screen:**
  - central theme and an expandable summary, with one source label when
    they share a source;
  - verse count and estimated reading and listening times;
  - Start reading, and Start listening (disabled until Phase 5, with a
    tooltip).
- **Search (offline):**
  - verse numbers (`2.47`, `BG 2:47`);
  - Devanagari words, prefixes and substrings inside compounds;
  - Telugu script;
  - IAST and informal spellings (`phaleshu`, `kadachana`, `dharmakshetre`);
  - English words in translations and explanations.
  
  Results show real IAST with the matching words highlighted. User input is
  always quoted, never run as FTS syntax. Meaning-based search is Phase 7,
  and the app says so.
- **Provenance:** AI output is labelled "AI-generated (model) · Not yet
  reviewed". Editorial text is labelled "AI-assisted".

## Tests

| Package | Tests |
|---|---|
| content | 87 (adds AI import, provider allow-list, pack v2, shared romanisation vectors) |
| backend | 63 (adds 15 LLM-layer tests against a fake HTTP server, 18 generator/validation tests, AI import into Postgres) |
| mobile | 48 (adds search, estimates, Dart romanisation against the shared vectors, 11 reader/chapter/search widget tests) |

## Problems found and fixed

1. **Sandhi.** Models gloss words in dictionary form (`adhikāraḥ`), while the
   verse has them sandhi-joined (`adhikāraste`). The word check now compares
   stems and treats an avagraha as an elided *a*. Invented words are still
   rejected.
2. A verse reference at the end of a sentence ("Compare 3.19.") escaped the
   reference check, because the full stop blocked the pattern. Found by a
   test, and fixed.
3. The reader title was truncated by the toolbar. The verse number is now
   the title, with the chapter and position underneath.
4. The translation notice claimed explanations were missing even when they
   were shown. It now speaks only about the translation.
5. Search snippets showed the internal folded spelling. Results now show
   real IAST with the matching words highlighted.
6. Python and Dart must fold spellings identically. Both test suites now
   check one shared vector file.

## What you need to do to get explanations

1. Create a free API key at one or more providers (Google AI Studio for
   Gemini, Groq, OpenRouter).
2. Add each as a repository secret: `GEMINI_API_KEY`, `GROQ_API_KEY`,
   `OPENROUTER_API_KEY`.
3. Run **Actions → gita-generate-ai**. Start with `only = 2,2.47,2.48` and
   review the output. Then run it daily; free quotas cover a few hundred
   items per day, and 701 verses × 2 languages + 36 chapter overviews is
   about 1,440 items.

## Limitations

- Model output may still be wrong in ways that code cannot check. It stays
  labelled unreviewed until a person reviews it.
- Free-tier model ids and limits in `llm.yaml` reflect what I could verify
  in October 2026 and will drift. Check them before relying on them.
- The Gemini free tier may use prompts to improve Google's products. It is
  only used for public scripture text, and is not marked `user_data_ok`.
