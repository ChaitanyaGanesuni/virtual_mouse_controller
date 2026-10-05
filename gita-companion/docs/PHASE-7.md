# Phase 7 report: RAG and search by meaning

Exit criterion: *Recall@8 target met on the golden set.* **Partly met.**

The targets were fixed before the first measurement: hit@8 ≥ 0.85 and
recall@8 ≥ 0.60, for English and Telugu separately.

| Golden set (server retriever) | Questions | hit@8 | recall@8 | MRR | Target |
|---|---|---|---|---|---|
| English | 70 | **0.914** | **0.594** | 0.692 | hit met; recall **missed by 0.006** |
| Telugu | 16 | **1.000** | **0.730** | 0.806 | met |

English recall is just under its target. I have not lowered the target,
changed the golden set or fitted settings to it to close the gap (see
[What did not work](#what-did-not-work)). CI prints the target status on
every run and fails if a score drops below its regression floor.

The app's offline search reaches nearly the same scores without a network
connection: English 0.900 / 0.580 / 0.689 and Telugu 1.000 / 0.730 / 0.784.

## What was built

### 1. A real English translation: Annie Besant (1922)

Until now the app showed "No translation is installed yet". It now ships
Annie Besant's *The Bhagavad-Gita* (4th edition, Natesan, Madras, 1922),
which is in the public domain. The text comes from the proofread Wikisource
transcription.

- **Snapshot.** `content/sources/besant-1922/wikisource-pages.jsonl` holds
  288 pages, each with its Wikisource revision ID. CI fetches them
  (`tools/fetch_besant.py`) because Wikisource is not reachable from the
  build machine.
- **Parser.** `gita_content/sources/besant.py` handles:
  - nested templates;
  - verse markers, including two misprinted ones (17.19→20, 18.14→15), which
    are listed explicitly;
  - Sanskrit split across a page break;
  - words hyphenated across a page break;
  - speaker headings and inline labels such as "Arjuna said:".
- **Verse numbering.** Besant numbers chapter 13 like the 700-verse
  tradition, so her 13.n maps to our 13.(n−1).
- **Gate.** The build fails unless the Sanskrit printed with each of
  Besant's verses matches our canonical verse (similarity ≥ 0.95 on loose
  romanisation). Three places where she divides half-verses differently
  (1.20, 1.21, 1.28) are listed explicitly.
- **Result.** All 701 verses have a translation. CI rebuilds the file from
  the snapshot and fails if it changed.

### 2. Concept index (`content/editorial/concepts.yaml`, 64 concepts)

Each concept has:

- an English and Telugu name, and a one-line definition;
- the words people use for it, in English and Telugu (for example "anger",
  "rage", "temper"; "కోపం");
- Sanskrit stems that show where the Gita actually talks about it (for
  example *krodh*, *kop*, *manyu*);
- related concepts (anger → desire, delusion, self-control).

How verses are linked and checked:

- **Only on evidence.** A verse is linked to a concept only if one of its
  stems occurs in that verse's Sanskrit. Links are weighted so rare words
  count more than common ones. This gives 1,768 links.
- **Build checks.** The build fails if a stem matches no verse or a related
  concept does not exist. An audit of the top verses per concept removed
  stems that produced off-topic links.
- **Generic words.** Words such as "god" or "work" are marked *weak*. They
  only hint at a concept and score lower.

How a question is understood (`gita_content/concepts.py`):

- English words are lightly stemmed, and accents are folded ("yajña" →
  "yajna").
- Telugu words lose one common ending.
- Sanskrit typed in Roman letters ("krodha", "sthitaprajna") also matches.

The app reads the same index from its content pack. The Dart port is checked
against the Python reference on shared test vectors
(`content/tests/query_vectors.json`), so the phone and the server understand
a question in exactly the same way.

### 3. Hybrid retriever (`gita_content/retrieval.py`)

One module used by both the server and the evaluator. It has three channels,
fused with Reciprocal Rank Fusion (k = 60):

| Channel | What it finds | Weight |
|---|---|---|
| Explicit | "2.47", "chapter 2 verse 47" anywhere in the question | 2 |
| Concept | Verses linked to the question's concepts (related concepts at 0.35). A verse also gains half the average score of its two neighbours, because the Gita teaches in passages (6.10–14 on meditation) | 1 |
| Keywords | BM25 over Besant's translation and the explanations (stemmed, without stopwords), Sanskrit in Roman letters (including inside long compounds) and Telugu text. Expanded with the English words of the matched concepts at 0.5, so "results" also finds Besant's "fruits" | 1, or 0.5 when a concept matched |
| Vector (optional, server only) | Nearest verses by embedding | 1 |

### 4. The AI teacher uses it

- `build_context` now uses the hybrid retriever: 6 verses for a free
  question, 3 when the chat is about one verse.
- Asking the model to suggest verse numbers is now only a last resort, used
  when nothing at all was found.
- Citation validation is unchanged: the answer may cite only verses it was
  shown.
- The backend imports the concepts from the dataset. Re-importing removes
  links that no longer exist.

### 5. Optional vector search (server)

This is wired in but **off by default**, and **not measured**.

To turn it on, set:

- `EMBEDDINGS_BASE_URL`;
- `EMBEDDINGS_MODEL`;
- optionally `EMBEDDINGS_API_KEY`.

Any OpenAI-compatible `/embeddings` endpoint works. The free option is
`bge-m3` on Ollama (1024 dimensions, multilingual). After setting the
variables, run `python -m workers.index_embeddings` to store the verse
vectors in pgvector. The run is idempotent: only new or changed documents
are embedded.

The vector channel is then fused with the others. Neither Hugging Face nor
an embedding API was reachable from this build environment, so I could not
measure what vectors add. The targets above are reached, or missed, without
them.

### 6. Search by meaning in the app (offline)

`SqliteSearchService` implements the same channels over the content pack,
which is now schema 3. The pack adds:

- the concept tables;
- a stemmed English column in the full-text index;
- the shared stopword list.

Typing still works as before (verse numbers, Devanagari, Telugu script,
IAST, informal spellings such as "phaleshu", prefixes while typing). Those
matches are fused in as a fourth channel. On the golden set they neither
help nor hurt questions, but they keep as-you-type search working.

New in the search screen:

- **"Related to:" chips** name the concepts a question is about, for example
  *Anger (krodha)*, or *కోపం (krodha)* for Telugu readers. Tapping a chip
  lists that topic's verses, best first.
- **Browse by topic.** With an empty query, all 64 topics are listed.
- **Explained results.** A result found by meaning shows the start of its
  translation and is labelled *Topic* or *Keywords*, so it is clear why it
  is there.

Screenshots: `mobile/test/screenshots/out/search_question_anger.png`,
`search_question_telugu_dark.png` and `search_topics.png`.

## Golden set (`content/eval/golden.yaml`)

The set has 86 questions people actually ask: 70 in English and 16 in
Telugu. Examples: "I'm anxious about the results of my work", "Is the soul
eternal?", "కోపాన్ని ఎలా నియంత్రించాలి?".

- **Expected verses.** Each question lists the verses a good answer must
  draw on. Every English expected verse was checked by reading Besant's
  translation and the Sanskrit.
- **Rule.** The file must never be edited to raise the score, only when a
  verse is wrong for its question.
- **Dev/test split.** Even positions are "dev" and odd positions are
  "test". Tuning decisions looked only at dev; test shows whether a change
  generalises.

| Split | English hit@8 / recall@8 | Telugu hit@8 / recall@8 |
|---|---|---|
| dev (35 + 8) | 0.886 / 0.536 | 1.000 / 0.610 |
| test (35 + 8) | 0.943 / 0.651 | 1.000 / 0.850 |

Where it runs:

- **Server retriever:** `python -m gita_content.evaluate [--details]`, run
  in the CI content job. Floors: English 0.88 / 0.57, Telugu 0.93 / 0.70.
- **App search:** `mobile/test/golden_eval_test.dart`, run in the CI mobile
  job. Floors: English 0.87 / 0.55, Telugu 0.93 / 0.70.

## What did not work

Each of these was tried, measured on dev, and dropped because it scored
worse or did not carry over to test:

- weighting concepts by how specific they are;
- a prior favouring commonly asked chapters;
- a softer rarity weighting (IDF power below 1);
- equal channel weights;
- adding concept words to the verses themselves (document expansion);
- grid-searched fusion settings: the best on dev was worse on test, a sign
  of overfitting;
- related-concept weights other than 0.35.

Six English questions find none of their expected verses. They are
phrased very differently from both Besant's wording and the concept terms.
Examples:

- "Is God partial to some people?" should find 9.29 ("The same am I to
  all beings; there is none hateful to Me nor dear").
- "What happens to someone who fails in spiritual practice?" should find
  6.37–43 ("with the mind wandering away from yoga").
- "Why can't people see God?" should find 7.24–25 and 11.8.

Meaning-based embeddings are the natural next step for these. That is why
the vector channel exists, but its effect still has to be measured with a
real model (`python -m gita_content.evaluate --details` lists every miss).

## Tests

| Part | Tests | Notes |
|---|---|---|
| content | 153 | Besant parser and cross-check, concept linking and query understanding, retriever channels, pack schema 3 |
| backend | 118 | Hybrid tutor context, suggestions only as a last resort, concept import and re-import, embedding index with a fake model |
| mobile | 163 | 46 Dart-vs-Python parity checks, hybrid search, search screen (chips, topics, Telugu), golden-set floors |

## Limitations and decisions for you

1. **English recall@8 is 0.594, against a target of 0.60.** Options:
   - accept it for now;
   - let me measure the vector channel with `bge-m3` once you have an
     Ollama host or a free embeddings key;
   - extend the concept index with more everyday phrasings.

   I recommend the vector measurement first.
2. **Telugu translation.** There is still no public-domain Telugu
   translation in the app. Telugu questions find verses through the concept
   index, but results show Besant's English. Telugu explanations remain
   AI-generated and labelled as such.
3. **Besant's English is archaic** ("thee", "thou", "conceiveth"). It is
   accurate and free to use. The AI explanations in Simple mode are where
   modern English lives.
4. **Concepts are editorial.** The 64 concepts and their words are my
   choice and reviewable in `concepts.yaml`. Every verse link is backed by
   a Sanskrit word in the verse, but whether a passing mention deserves a
   link is a judgement call.
