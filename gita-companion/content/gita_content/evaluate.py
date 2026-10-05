"""Golden-set evaluation of retrieval (eval/golden.yaml).

    python -m gita_content.evaluate [--details]

Prints hit@8, recall@8 and MRR per language, says whether the Phase 7
targets are met, and exits non-zero if a score falls below its regression
floor, so CI fails when retrieval gets worse.

Targets were fixed before the first measurement and are not lowered to fit
results. Floors are the scores reached when this was written, minus a small
margin; raise them as retrieval improves.
"""

from __future__ import annotations

import argparse
import json
import sys
from collections.abc import Callable
from dataclasses import dataclass
from pathlib import Path

import yaml

from .retrieval import Retriever

ROOT = Path(__file__).resolve().parent.parent
GOLDEN = ROOT / "eval" / "golden.yaml"
TARGETS = {"hit@8": 0.85, "recall@8": 0.60}
FLOORS = {
    "en": {"hit@8": 0.88, "recall@8": 0.57},
    "te": {"hit@8": 0.93, "recall@8": 0.70},
}
K = 8


@dataclass(frozen=True)
class Result:
    question: str
    language: str
    expected: tuple[str, ...]
    got: tuple[str, ...]

    @property
    def hit(self) -> bool:
        return bool(set(self.got[:K]) & set(self.expected))

    @property
    def recall(self) -> float:
        return len(set(self.got[:K]) & set(self.expected)) / min(K, len(self.expected))

    @property
    def rr(self) -> float:
        for i, vid in enumerate(self.got, 1):
            if vid in self.expected:
                return 1 / i
        return 0.0


def load_golden(path: Path = GOLDEN) -> list[dict]:
    return yaml.safe_load(path.read_text(encoding="utf-8"))["questions"]


def evaluate(search: Callable[[str], list[str]], golden: list[dict]) -> list[Result]:
    return [Result(g["q"], g.get("lang", "en"), tuple(g["expect"]), tuple(search(g["q"]))) for g in golden]


def summary(results: list[Result]) -> dict[str, dict[str, float]]:
    out = {}
    for lang in sorted({r.language for r in results}):
        rs = [r for r in results if r.language == lang]
        out[lang] = {
            "questions": len(rs),
            "hit@8": round(sum(r.hit for r in rs) / len(rs), 3),
            "recall@8": round(sum(r.recall for r in rs) / len(rs), 3),
            "mrr": round(sum(r.rr for r in rs) / len(rs), 3),
        }
    return out


def below(stats: dict[str, dict[str, float]], limits: dict[str, dict[str, float]]) -> list[str]:
    return [
        f"{lang} {metric} {stats[lang][metric]} < {limit}"
        for lang, by_metric in limits.items()
        for metric, limit in by_metric.items()
        if lang in stats and stats[lang][metric] < limit
    ]


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="gita-evaluate")
    ap.add_argument("--dataset", type=Path, default=ROOT / "data" / "gita.json")
    ap.add_argument("--details", action="store_true")
    args = ap.parse_args(argv)
    dataset = json.loads(args.dataset.read_text(encoding="utf-8"))
    retriever = Retriever(dataset)
    results = evaluate(lambda q: [h.verse_id for h in retriever.search(q, k=K)], load_golden())
    if args.details:
        for r in results:
            mark = "ok " if r.hit else "MISS"
            print(f"{mark} {r.recall:.2f} {r.question}")
            print(f"      expected {list(r.expected)}")
            print(f"      got      {list(r.got)}")
    stats = summary(results)
    # Tuning uses only the "dev" half (even positions); "test" (odd) shows
    # whether the result generalises.
    split = {
        "dev": summary([r for i, r in enumerate(results) if i % 2 == 0]),
        "test": summary([r for i, r in enumerate(results) if i % 2 == 1]),
    }
    print(json.dumps({"all": stats, **split}, indent=1))
    missed = below(stats, {lang: TARGETS for lang in stats})
    print("phase targets:", "met" if not missed else "NOT met (" + "; ".join(missed) + ")")
    regressions = below(stats, FLOORS)
    for p in regressions:
        print("REGRESSION:", p, file=sys.stderr)
    return 1 if regressions else 0


if __name__ == "__main__":
    raise SystemExit(main())
