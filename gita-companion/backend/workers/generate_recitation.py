"""Pre-generate Sanskrit recitation audio for the app (normal + slow).

    python -m workers.generate_recitation --dataset ../content/data/gita.json \\
        --out recitation/ --voice sa:Aryan [--only 2.47,2.48] [--chapters 2,12]

Runs on a GPU machine (a free Kaggle or Colab GPU is enough). Resumable:
verses already in the manifest are skipped. Produces:

    recitation/
      manifest.json        one entry per (verse, style): file, sha256, seconds,
                           provider, model, voice, description, licence
      audio/2.47.normal.wav, audio/2.47.slow.wav, ...
      review.csv           pronunciation review sheet (one row per file)

Synthetic recitation must be checked by a Sanskrit-literate listener before
it ships: rows in review.csv start as 'unreviewed'. The app labels
unreviewed recitation accordingly (audio packs arrive in Phase 9).
"""

from __future__ import annotations

import argparse
import csv
import hashlib
import json
from datetime import UTC, datetime
from pathlib import Path

from app.providers.tts.base import TTSProvider

STYLES = {"normal": 1.0, "slow": 0.7}


def recitation_text(verse: dict, speakers: dict[str, dict]) -> str:
    """Devanagari text to recite: the speaker heading (if any), then the
    half-verses, separated so the model pauses at each danda."""
    parts = []
    if verse.get("speaker"):
        parts.append(speakers[verse["speaker"]]["line_sa"] + " ।")
    parts += [line.strip() for line in verse["sanskrit"].split("\n") if line.strip()]
    return "\n".join(parts)


def select(ds: dict, only: set[str] | None, chapters: set[int] | None) -> list[dict]:
    return [
        v
        for v in ds["verses"]
        if (not only or v["id"] in only) and (not chapters or v["chapter"] in chapters)
    ]


def run(
    ds: dict,
    provider: TTSProvider,
    voice_id: str,
    out: Path,
    verses: list[dict],
    styles: list[str] | None = None,
    log=print,
) -> dict[str, int]:
    styles = styles or list(STYLES)
    (out / "audio").mkdir(parents=True, exist_ok=True)
    manifest_path = out / "manifest.json"
    manifest = (
        json.loads(manifest_path.read_text(encoding="utf-8")) if manifest_path.exists() else {"items": []}
    )
    done = {(i["verse"], i["style"]) for i in manifest["items"]}
    voice = next(v for v in provider.voices("sa") if v.id == voice_id)
    speakers = {s["id"]: s for s in ds["speakers"]}
    stats = {"generated": 0, "skipped": 0}

    for v in verses:
        for style in styles:
            if (v["id"], style) in done:
                stats["skipped"] += 1
                continue
            text = recitation_text(v, speakers)
            result = provider.synthesize(text, voice, rate=STYLES[style])
            name = f"{v['id']}.{style}.wav"
            (out / "audio" / name).write_bytes(result.wav)
            manifest["items"].append(
                {
                    "verse": v["id"],
                    "style": style,
                    "file": f"audio/{name}",
                    "sha256": hashlib.sha256(result.wav).hexdigest(),
                    "seconds": round(result.seconds, 3),
                    "text": text,
                    "provider": provider.id,
                    "provider_version": provider.version,
                    "voice": voice.id,
                    "model": result.meta.get("model"),
                    "description": result.meta.get("description"),
                    "license": provider.capabilities().license,
                    "review_status": "unreviewed",
                    "generated_at": datetime.now(UTC).isoformat(timespec="seconds"),
                }
            )
            # Write after every file so an interrupted run loses nothing.
            manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=1), encoding="utf-8")
            stats["generated"] += 1
            log(f"ok {v['id']} {style} {result.seconds:.1f}s")

    with (out / "review.csv").open("w", newline="", encoding="utf-8") as f:
        w = csv.writer(f)
        w.writerow(["verse", "style", "file", "seconds", "review_status", "reviewer", "notes"])
        for i in sorted(manifest["items"], key=lambda i: (_order(i["verse"]), i["style"])):
            w.writerow([i["verse"], i["style"], i["file"], i["seconds"], i["review_status"], "", ""])
    return stats


def _order(vid: str) -> tuple[int, int]:
    c, v = vid.split(".")
    return int(c), int(v)


def main(argv: list[str] | None = None) -> int:
    ap = argparse.ArgumentParser(prog="generate_recitation")
    ap.add_argument("--dataset", type=Path, required=True)
    ap.add_argument("--out", type=Path, required=True)
    ap.add_argument("--voice", default="sa:Aryan")
    ap.add_argument("--only", help="comma-separated verse ids")
    ap.add_argument("--chapters", help="comma-separated chapter numbers")
    ap.add_argument("--styles", default="normal,slow")
    args = ap.parse_args(argv)

    from app.providers.tts.indic_parler import IndicParlerProvider

    ds = json.loads(args.dataset.read_text(encoding="utf-8"))
    verses = select(
        ds,
        set(args.only.split(",")) if args.only else None,
        {int(c) for c in args.chapters.split(",")} if args.chapters else None,
    )
    stats = run(ds, IndicParlerProvider(), args.voice, args.out, verses, args.styles.split(","))
    print(json.dumps(stats))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
