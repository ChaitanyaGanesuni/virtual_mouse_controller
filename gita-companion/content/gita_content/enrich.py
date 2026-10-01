"""Add editorial and AI-generated explanations to the dataset.

Inputs (both committed, so CI can reproduce the dataset):
- editorial/chapter-overviews.<lang>.yaml   project-written chapter summaries/themes
- ai/*.jsonl                                output of backend/workers/generate_content.py

Every AI record becomes text from a per-(provider, model, prompt version)
source with is_ai_generated = true and review_status 'unreviewed'. Only
providers listed under `ai_providers` in sources.yaml are accepted.
"""

from __future__ import annotations

import json
import re
from pathlib import Path

import yaml

from .canon import Canon
from .registry import Registry

ROOT = Path(__file__).resolve().parent.parent
EDITORIAL_DIR = ROOT / "editorial"
AI_DIR = ROOT / "ai"

VERSE_MODES = ("simple", "deep", "practical", "story", "child")
SUPPORTED_PROMPTS = {"verse-explain-v1", "chapter-overview-v1"}


class EnrichError(ValueError):
    pass


def _slug(text: str) -> str:
    return re.sub(r"[^a-z0-9]+", "-", text.lower()).strip("-")


def ai_source_id(provider: str, model: str, prompt_version: str) -> str:
    return f"ai-{_slug(provider)}-{_slug(model)}-{prompt_version}"


def load_editorial_overviews(canon: Canon, directory: Path = EDITORIAL_DIR) -> list[dict]:
    """Returns chapter_text rows (without ids) for summaries and themes."""
    rows = []
    for path in sorted(directory.glob("chapter-overviews.*.yaml")):
        data = yaml.safe_load(path.read_text(encoding="utf-8"))
        lang, source = data["language"], data["source"]
        for number, entry in data["chapters"].items():
            if int(number) not in canon.chapters:
                raise EnrichError(f"{path.name}: no chapter {number}")
            for kind in ("summary", "theme"):
                text = " ".join(str(entry[kind]).split())
                if not text:
                    raise EnrichError(f"{path.name}: chapter {number} has an empty {kind}")
                rows.append(
                    {
                        "chapter": int(number),
                        "kind": kind,
                        "language": lang,
                        "source_id": source,
                        "body": text,
                    }
                )
    return rows


def load_ai_records(directory: Path = AI_DIR) -> list[dict]:
    """All AI records; for a repeated (kind, ref, language) the last one wins
    (a regenerated answer replaces the old one)."""
    latest: dict[tuple[str, str, str], dict] = {}
    for path in sorted(directory.glob("*.jsonl")) if directory.exists() else []:
        for n, line in enumerate(path.read_text(encoding="utf-8").splitlines(), 1):
            if not line.strip():
                continue
            try:
                rec = json.loads(line)
                key = (rec["kind"], rec["ref"], rec["language"])
                rec["content"], rec["provider"], rec["model"], rec["prompt_version"]
            except (ValueError, KeyError) as e:
                raise EnrichError(f"{path.name}:{n}: malformed record ({e})") from e
            if rec["prompt_version"] not in SUPPORTED_PROMPTS:
                raise EnrichError(f"{path.name}:{n}: unknown prompt version {rec['prompt_version']!r}")
            latest[key] = rec
    return list(latest.values())


def ai_source_row(rec: dict, registry: Registry) -> dict:
    provider = registry.ai_providers.get(rec["provider"])
    if provider is None:
        raise EnrichError(f"AI provider {rec['provider']!r} is not allowed in sources.yaml (ai_providers)")
    return {
        "id": ai_source_id(rec["provider"], rec["model"], rec["prompt_version"]),
        "kind": "ai",
        "title": f"AI-generated explanations ({rec['model']})",
        "author": f"{rec['model']} via {rec['provider']}",
        "year": None,
        "language": "mul",
        "license": "AI-generated text; provider terms apply",
        "license_note": provider.get("note", ""),
        "url": provider.get("terms_url"),
        "retrieved_commit": None,
        "is_ai_generated": True,
        "model_id": rec["model"],
        "prompt_version": rec["prompt_version"],
    }


def verse_ai_texts(rec: dict, source_id: str, text_id) -> tuple[list[dict], list[dict]]:
    """verse_text rows and word_meaning rows for one verse record."""
    vid, lang, c = rec["ref"], rec["language"], rec["content"]
    texts = [
        {
            "id": text_id(vid, mode, lang, source_id),
            "kind": mode,
            "language": lang,
            "source_id": source_id,
            "body": c[mode],
            "review_status": "unreviewed",
        }
        for mode in VERSE_MODES
    ]
    texts.append(
        {
            "id": text_id(vid, "sanskrit_terms", lang, source_id),
            "kind": "sanskrit_terms",
            "language": lang,
            "source_id": source_id,
            # Structured: [{"term": IAST, "meaning": ...}]
            "body": json.dumps(c["sanskrit_terms"], ensure_ascii=False),
            "review_status": "unreviewed",
        }
    )
    words = [
        {
            "id": text_id(vid, "word", i, lang, source_id),
            "source_id": source_id,
            "language": lang,
            "position": i,
            "word": w["word"],
            "meaning": w["meaning"],
        }
        for i, w in enumerate(c["word_meanings"])
    ]
    return texts, words
