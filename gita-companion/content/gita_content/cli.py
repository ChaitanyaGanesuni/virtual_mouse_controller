"""gita-content: build the canonical Sanskrit content set and the mobile pack.

    gita-content build \\
        --gita-json   <gita/gita checkout>/data/verse.json \\
        --verify-with <vedicscriptures checkout>/slok \\
        [--translation SOURCE_ID=path/to/translation.jsonl ...] \\
        --out data/
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from .build import BuildError, build_dataset, render_report
from .canon import Canon
from .errata import Errata
from .pack import pack_manifest, write_pack
from .registry import Registry
from .sources.readers import read_gita_json, read_vedicscriptures

ROOT = Path(__file__).resolve().parent.parent
DEFAULT_PACK = ROOT / "build" / "gita_content_pack.sqlite"


def main(argv: list[str] | None = None) -> int:
    p = argparse.ArgumentParser(prog="gita-content")
    sub = p.add_subparsers(dest="cmd", required=True)
    b = sub.add_parser("build", help="build canonical JSON, report and SQLite pack")
    b.add_argument("--gita-json", type=Path, required=True)
    b.add_argument("--verify-with", type=Path, help="vedicscriptures slok/ directory")
    b.add_argument("--translation", action="append", default=[], metavar="SOURCE_ID=PATH")
    b.add_argument("--out", type=Path, default=ROOT / "data")
    b.add_argument("--pack", type=Path, default=DEFAULT_PACK)
    k = sub.add_parser("pack", help="rebuild the SQLite pack from an existing gita.json (offline)")
    k.add_argument("--dataset", type=Path, default=ROOT / "data" / "gita.json")
    k.add_argument("--pack", type=Path, default=DEFAULT_PACK)
    k.add_argument("--manifest", type=Path, help="also write a JSON manifest (content hash, schema version)")
    bs = sub.add_parser(
        "besant", help="convert the Wikisource snapshot of Besant (1922) to the import format"
    )
    bs.add_argument(
        "--snapshot", type=Path, default=ROOT / "sources" / "besant-1922" / "wikisource-pages.jsonl"
    )
    bs.add_argument("--dataset", type=Path, default=ROOT / "data" / "gita.json")
    bs.add_argument("--out", type=Path, default=ROOT / "sources" / "besant-1922" / "besant-1922-en.jsonl")
    args = p.parse_args(argv)

    if args.cmd == "besant":
        from .sources import besant

        verses = besant.parse(besant.read_snapshot(args.snapshot))
        dataset = json.loads(args.dataset.read_text(encoding="utf-8"))
        problems = besant.check_against(verses, {v["id"]: v["sanskrit"] for v in dataset["verses"]})
        if problems:
            print(
                "BESANT FAILED: Sanskrit does not match the canonical text at "
                + ", ".join(f"{vid} ({r})" for vid, r in problems),
                file=sys.stderr,
            )
            return 1
        args.out.write_text(besant.to_jsonl_canonical(verses), encoding="utf-8")
        print(f"ok: {len(verses)} verses -> {args.out}")
        return 0

    if args.cmd == "pack":
        dataset = json.loads(args.dataset.read_text(encoding="utf-8"))
        write_pack(dataset, args.pack)
        if args.manifest:
            args.manifest.write_text(json.dumps(pack_manifest(dataset), indent=1) + "\n", encoding="utf-8")
        print(f"ok: {args.pack} ({len(dataset['verses'])} verses)")
        return 0

    translations = []
    for item in args.translation:
        sid, _, path = item.partition("=")
        if not path:
            p.error(f"--translation must be SOURCE_ID=PATH, got {item!r}")
        translations.append((sid, Path(path)))

    errata = Errata.load()
    try:
        dataset, report = build_dataset(
            list(read_gita_json(args.gita_json)),
            Canon.load(),
            Registry.load(),
            errata,
            verify_rows=list(read_vedicscriptures(args.verify_with)) if args.verify_with else None,
            translations=translations,
        )
    except (BuildError, ValueError) as e:
        print(f"BUILD FAILED: {e}", file=sys.stderr)
        return 1

    args.out.mkdir(parents=True, exist_ok=True)
    (args.out / "gita.json").write_text(
        json.dumps(dataset, ensure_ascii=False, indent=1) + "\n", encoding="utf-8"
    )
    (args.out / "sanskrit-report.md").write_text(render_report(dataset, report, errata), encoding="utf-8")
    write_pack(dataset, args.pack)
    print(f"ok: {len(dataset['verses'])} verses, content hash {dataset['content_hash'][:12]}")
    print(f"    {args.out / 'gita.json'}\n    {args.out / 'sanskrit-report.md'}\n    {args.pack}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
