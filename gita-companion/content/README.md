# Content pipeline (`gita-content`)

Produces the scripture content that ships in the app and is imported into
the backend. No text reaches the app unless it passes through here.

```
raw source ──► normalise ──► renumber ──► errata ──► validate ──► cross-check ──► transliterate
(gita/gita)    (danda,        (701 → 700   (documented   (canonical   (independent     (IAST, Telugu
               numbers,       standard)    corrections)  verse table) transcription)   script)
               speakers,
               legacy-font
               repairs)
                                                    ──► data/gita.json  (committed, reproducible)
                                                    ──► data/sanskrit-report.md
                                                    ──► build/gita_content_pack.sqlite (mobile)
```

## Files

| Path | Purpose |
|---|---|
| `canonical/chapters.yaml` | Chapter names and verse counts: the single source of truth for verse references |
| `sources.yaml` | Licence register. Unregistered, unlicensed or verify-only sources cannot be shipped |
| `corrections/sanskrit-errata.yaml` | Every manual correction with its reason; variants kept for review |
| `schema/content_pack.sql` | Mobile SQLite schema (mirrors backend content tables) |
| `data/gita.json` | Canonical dataset (committed). CI rebuilds it from pinned sources and requires an exact match |
| `data/sanskrit-report.md` | Cross-check and corrections report |
| `editorial/` | Project-written text (chapter overviews), labelled AI-assisted and unreviewed; `concepts.yaml`, the concept index |
| `sources/besant-1922/` | Wikisource snapshot of Besant's translation (with revision ids) and the derived verse-aligned JSONL |
| `eval/golden.yaml` | Golden set of questions and the verses that answer them |
| `ai/` | Output of the free-tier LLM generator (`backend/workers`), imported as AI-generated and unreviewed |

## Commands

```bash
pip install -e ".[dev]"
pytest -q

# Full rebuild from the pinned upstream sources (see sources.yaml for commits)
gita-content besant    # Besant's translation from the committed Wikisource snapshot
gita-content build --gita-json <gita/gita>/data/verse.json --verify-with <bhagavad-gita-data>/slok \
  --translation besant-1922-en=sources/besant-1922/besant-1922-en.jsonl

# Retrieval quality on the golden set (fails below the regression floors)
python -m gita_content.evaluate --details

# Rebuild only the SQLite pack from the committed dataset (no network)
gita-content pack
```

## Adding a translation

Translations are imported from a verse-aligned JSONL file, one object per
line, using the **standard 700-verse numbering**:

```json
{"chapter": 2, "verse": 47, "text": "..."}
```

1. Register the source in `sources.yaml` with its licence and `use: ship`.
2. `gita-content build ... --translation <source-id>=path/to/file.jsonl`

The build rejects unknown verses (e.g. 2.73), duplicates, empty rows and
unregistered or verify-only sources. Imported rows start as `unreviewed`.

## Review status

| Status | Meaning |
|---|---|
| `unreviewed` | Imported mechanically; no human has checked it yet |
| `pending` | Changed by a documented correction, awaiting sign-off by a Sanskrit-literate reviewer |
| `reviewed` | Checked by a named reviewer |
| `rejected` | Must not be shown |

Transliterations inherit the status of the Devanagari they were generated from.

## Search folding

`gita_content/romanize.py::loose()` folds IAST and informal spellings
("phaleshu", "kadachana", "krishna") into one ASCII form for search. The
mobile app must port it exactly; the test vectors in
`tests/test_transliterate_romanize.py` are the contract.

## Concepts and retrieval

`editorial/concepts.yaml` maps everyday English and Telugu words to Sanskrit
stems. A verse is linked to a concept only where a stem occurs in its
Sanskrit, and the build fails on stems that match nothing.
`gita_content/retrieval.py` combines explicit references, concepts and
keyword search (RRF). The server uses it directly and the app ports it.
`tests/query_vectors.json` (from `tools/gen_query_vectors.py`) is the
contract for the app's port. See [docs/PHASE-7.md](../docs/PHASE-7.md).
