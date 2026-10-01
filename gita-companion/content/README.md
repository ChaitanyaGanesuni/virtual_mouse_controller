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
| `editorial/` | Project-written text (chapter overviews), labelled AI-assisted and unreviewed |
| `ai/` | Output of the free-tier LLM generator (`backend/workers`), imported as AI-generated and unreviewed |

## Commands

```bash
pip install -e ".[dev]"
pytest -q

# Full rebuild from the pinned upstream sources (see sources.yaml for commits)
gita-content build --gita-json <gita/gita>/data/verse.json --verify-with <bhagavad-gita-data>/slok

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
