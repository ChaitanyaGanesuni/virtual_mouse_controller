"""Prompts for batch content generation. Changing a prompt means bumping its
version: the version is stored with every generated text, so old and new
outputs are never confused."""

from __future__ import annotations

VERSE_PROMPT_VERSION = "verse-explain-v1"
CHAPTER_PROMPT_VERSION = "chapter-overview-v1"

LANGUAGE_NAMES = {"en": "English", "te": "Telugu (natural, everyday Telugu in Telugu script)"}

SYSTEM = """You are a careful teacher of the Bhagavad Gita writing study notes for a mobile app.

Rules you must follow:
- Base everything on the Sanskrit verse you are given and its immediate context. Do not quote any \
published translation or commentary, and do not attribute words to any teacher, author or tradition.
- Never invent verse numbers, quotations, Sanskrit words or facts. Only mention another verse if you \
are sure of its chapter and verse number; otherwise do not mention it.
- Where traditional schools (for example Advaita, Viśiṣṭādvaita, Dvaita) understand a verse \
differently, say that interpretations differ instead of presenting one view as the only meaning.
- If you are unsure about anything, say so in the "uncertain" list rather than guessing.
- Be respectful, clear and non-sectarian. No promises of supernatural results.
- Reply with a single JSON object and nothing else."""


def verse_prompt(
    *,
    verse_id: str,
    chapter_name_iast: str,
    speaker: str | None,
    sanskrit: str,
    iast: str,
    previous_iast: str | None,
    next_iast: str | None,
    language: str,
) -> str:
    lang = LANGUAGE_NAMES[language]
    context = []
    if previous_iast:
        context.append(f"Previous verse (IAST): {previous_iast}")
    if next_iast:
        context.append(f"Next verse (IAST): {next_iast}")
    return f"""Bhagavad Gita {verse_id} (chapter: {chapter_name_iast}).
Speaker heading: {speaker or "none (narration continues)"}

Sanskrit:
{sanskrit}

IAST:
{iast}

{chr(10).join(context)}

Write all explanations in {lang}. Keep Sanskrit words in IAST.

Return a JSON object with exactly these keys:
- "simple": the meaning for someone meeting the Gita for the first time (60-150 words).
- "deep": the philosophical meaning and implications (120-300 words).
- "practical": how the teaching can apply to modern life. Pick only the areas that genuinely \
fit this verse (for example work, relationships, fear, stress, decisions, failure, success, \
attachment, anger, discipline, leadership, personal growth) (80-200 words).
- "story": a short, original analogy or everyday story that illustrates the verse (80-180 words).
- "child": an explanation for a 12-15 year old (50-120 words).
- "word_meanings": a list of objects {{"word": "<a word exactly as it appears in the IAST above>", \
"meaning": "<meaning in {lang}>"}} covering the verse's words in order.
- "sanskrit_terms": 1-4 important terms that appear in this verse, as objects \
{{"term": "<IAST, as it appears in the verse>", "meaning": "<explanation in {lang}, 1-3 sentences>"}}.
- "uncertain": a list of short notes on anything you are not sure about (may be empty)."""


def chapter_prompt(*, chapter: int, name_iast: str, verses_iast: list[tuple[str, str]], language: str) -> str:
    lang = LANGUAGE_NAMES[language]
    listing = "\n".join(f"{vid}: {text.replace(chr(10), ' ')}" for vid, text in verses_iast)
    return f"""Bhagavad Gita chapter {chapter}: {name_iast}.

The verses of the chapter in IAST:
{listing}

Write in {lang}. Return a JSON object with exactly these keys:
- "summary": a faithful overview of what happens and what is taught in this chapter, in order \
(120-250 words). Mention verse numbers only from the list above.
- "theme": the central theme in one sentence (at most 30 words).
- "uncertain": a list of short notes on anything you are not sure about (may be empty)."""
