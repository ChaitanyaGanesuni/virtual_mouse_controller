"""Batch-generate AI explanations with free-tier LLMs.

    python -m workers.generate_content \\
        --dataset ../content/data/gita.json --out generated/ \\
        --languages en,te --kinds verse,chapter [--only 2.47,2.48] [--limit 50]

- Resumable: results are appended to JSONL files; finished tasks are skipped
  on the next run, so a run that hits today's free quotas simply continues
  tomorrow.
- Every record carries provider, model, prompt version and timestamp.
- Output is AI-generated and unreviewed; the content pipeline imports it
  with that label (gita-content build --ai-content ...).
"""

from __future__ import annotations

import argparse
import json
import sys
import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass
from datetime import UTC, datetime
from pathlib import Path

from gita_content.canon import Canon

from app.providers.llm import (
    AllProvidersFailed,
    GenerateOptions,
    LLMRouter,
    Message,
    build_router,
    generate_structured,
)

from . import prompts
from .validation import validate_chapter, validate_verse

VERSE_FILE = "verse-explanations.jsonl"
CHAPTER_FILE = "chapter-overviews.jsonl"


@dataclass(frozen=True)
class Task:
    kind: str  # 'verse' | 'chapter'
    ref: str  # '2.47' or '2'
    language: str

    @property
    def key(self) -> str:
        version = prompts.VERSE_PROMPT_VERSION if self.kind == "verse" else prompts.CHAPTER_PROMPT_VERSION
        return f"{self.kind}:{self.ref}:{self.language}:{version}"


def done_keys(out_dir: Path) -> set[str]:
    keys = set()
    for name in (VERSE_FILE, CHAPTER_FILE):
        path = out_dir / name
        if path.exists():
            for line in path.read_text(encoding="utf-8").splitlines():
                if line.strip():
                    keys.add(json.loads(line)["key"])
    return keys


def plan(ds: dict, kinds: list[str], languages: list[str], only: set[str] | None) -> Iterator[Task]:
    for lang in languages:
        if "chapter" in kinds:
            for c in ds["chapters"]:
                if not only or str(c["number"]) in only:
                    yield Task("chapter", str(c["number"]), lang)
        if "verse" in kinds:
            for v in ds["verses"]:
                if not only or v["id"] in only:
                    yield Task("verse", v["id"], lang)


class Generator:
    def __init__(self, ds: dict, llm: LLMRouter, canon: Canon):
        self.llm = llm
        self.canon = canon
        self.verses = {v["id"]: v for v in ds["verses"]}
        self.order = [v["id"] for v in ds["verses"]]
        self.chapters = {c["number"]: c for c in ds["chapters"]}
        self.speakers = {s["id"]: s for s in ds["speakers"]}

    @staticmethod
    def _iast(v: dict) -> str:
        return next(
            t["body"] for t in v["texts"] if t["kind"] == "transliteration" and t["language"] == "sa-Latn"
        )

    def _chapter_iast(self, n: int) -> str:
        c = self.chapters[n]
        return next(t["body"] for t in c["texts"] if t["kind"] == "name" and t["language"] == "sa-Latn")

    def run(self, task: Task) -> dict:
        if task.kind == "verse":
            v = self.verses[task.ref]
            i = self.order.index(task.ref)
            prev = self.verses[self.order[i - 1]] if i > 0 else None
            nxt = self.verses[self.order[i + 1]] if i + 1 < len(self.order) else None
            iast = self._iast(v)
            user = prompts.verse_prompt(
                verse_id=v["id"],
                chapter_name_iast=self._chapter_iast(v["chapter"]),
                speaker=self.speakers[v["speaker"]]["line_sa_latn"] if v["speaker"] else None,
                sanskrit=v["sanskrit"],
                iast=iast,
                previous_iast=self._iast(prev) if prev and prev["chapter"] == v["chapter"] else None,
                next_iast=self._iast(nxt) if nxt and nxt["chapter"] == v["chapter"] else None,
                language=task.language,
            )
            out = generate_structured(
                self.llm,
                [Message("system", prompts.SYSTEM), Message("user", user)],
                lambda obj: validate_verse(obj, iast=iast, language=task.language, canon=self.canon),
                GenerateOptions(json=True, max_tokens=3000, temperature=0.3, timeout_s=120),
            )
            version = prompts.VERSE_PROMPT_VERSION
        else:
            n = int(task.ref)
            listing = [(v["id"], self._iast(v)) for v in self.verses.values() if v["chapter"] == n]
            user = prompts.chapter_prompt(
                chapter=n, name_iast=self._chapter_iast(n), verses_iast=listing, language=task.language
            )
            out = generate_structured(
                self.llm,
                [Message("system", prompts.SYSTEM), Message("user", user)],
                lambda obj: validate_chapter(obj, chapter=n, language=task.language, canon=self.canon),
                GenerateOptions(json=True, max_tokens=1500, temperature=0.3, timeout_s=120),
            )
            version = prompts.CHAPTER_PROMPT_VERSION
        return {
            "key": task.key,
            "kind": task.kind,
            "ref": task.ref,
            "language": task.language,
            "prompt_version": version,
            "provider": out.completion.provider,
            "model": out.completion.model,
            "repaired": out.repaired,
            "generated_at": datetime.now(UTC).isoformat(timespec="seconds"),
            "content": out.value,
        }


def run_batch(
    ds: dict,
    llm: LLMRouter,
    out_dir: Path,
    tasks: list[Task],
    limit: int | None = None,
    min_interval_s: float = 2.5,
    sleep: Callable[[float], None] = time.sleep,
    log: Callable[[str], None] = print,
) -> dict[str, int]:
    out_dir.mkdir(parents=True, exist_ok=True)
    gen = Generator(ds, llm, Canon.load())
    finished = done_keys(out_dir)
    todo = [t for t in tasks if t.key not in finished]
    stats = {"done_before": len(tasks) - len(todo), "generated": 0, "failed": 0, "remaining": len(todo)}
    failures: list[str] = []
    for task in todo[: limit if limit is not None else None]:
        try:
            record = gen.run(task)
        except AllProvidersFailed as e:
            exhausted = llm.next_available_in() is None
            stats["failed"] += 1
            failures.append(f"{task.key}: {e}")
            if exhausted:
                log(
                    "All providers are out of quota or unavailable for today; stopping. "
                    "Re-run later to resume."
                )
                break
            continue
        path = out_dir / (VERSE_FILE if task.kind == "verse" else CHAPTER_FILE)
        with path.open("a", encoding="utf-8") as f:
            f.write(json.dumps(record, ensure_ascii=False) + "\n")
        stats["generated"] += 1
        stats["remaining"] -= 1
        log(f"ok {task.key} via {record['provider']}/{record['model']}")
        sleep(min_interval_s)  # stay under free-tier requests-per-minute limits
    if failures:
        (out_dir / "failures.log").write_text("\n".join(failures) + "\n", encoding="utf-8")
    log(f"providers: {llm.status()}")
    return stats


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="generate_content", description=__doc__.split("\n\n")[0])
    ap.add_argument("--dataset", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--languages", default="en,te")
    ap.add_argument("--kinds", default="chapter,verse")
    ap.add_argument("--only", help="comma-separated verse ids or chapter numbers")
    ap.add_argument("--limit", type=int, help="maximum number of new items this run")
    ap.add_argument("--providers", help="comma-separated subset of llm.yaml providers")
    ap.add_argument("--min-interval", type=float, default=2.5, help="seconds between requests")
    args = ap.parse_args(argv)

    llm, notes = build_router(only=args.providers.split(",") if args.providers else None)
    for n in notes:
        print(n)
    if not llm._providers:
        print("No LLM provider is configured. Set at least one API key from llm.yaml.", file=sys.stderr)
        return 2
    ds = json.loads(args.dataset.read_text(encoding="utf-8"))
    tasks = list(
        plan(
            ds,
            args.kinds.split(","),
            args.languages.split(","),
            set(args.only.split(",")) if args.only else None,
        )
    )
    stats = run_batch(ds, llm, args.out, tasks, limit=args.limit, min_interval_s=args.min_interval)
    print(json.dumps(stats))
    return 0 if stats["failed"] == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
