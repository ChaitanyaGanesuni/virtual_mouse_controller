import json
from pathlib import Path

import pytest

from gita_content.canon import Canon
from gita_content.errata import Errata
from gita_content.registry import Registry
from gita_content.sources.readers import RawVerse

ROOT = Path(__file__).resolve().parent.parent
DATASET_PATH = ROOT / "data" / "gita.json"


@pytest.fixture(scope="session")
def canon() -> Canon:
    return Canon.load()


@pytest.fixture(scope="session")
def registry() -> Registry:
    return Registry.load()


@pytest.fixture(scope="session")
def dataset() -> dict:
    return json.loads(DATASET_PATH.read_text(encoding="utf-8"))


@pytest.fixture
def no_errata() -> Errata:
    return Errata(review="pending", errata=[])


@pytest.fixture(scope="session")
def raw_rows(dataset) -> list[RawVerse]:
    """Synthetic raw source in gita/gita style (701-numbering, '।।c.v।।' markers),
    rebuilt from the committed dataset, so build tests need no network."""
    rows = []
    for v in dataset["verses"]:
        n = v["verse"] + 1 if v["chapter"] == 13 else v["verse"]
        speaker = next((s["line_sa"] for s in dataset["speakers"] if s["id"] == v["speaker"]), None)
        body = v["sanskrit"].replace(" ॥", f"।।{v['chapter']}.{n}।।").replace(" ।", "।")
        # Raw sources put a danda after a speaker line inside a verse ("अर्जुन उवाच |").
        body = "\n".join(ln + "।" if ln.endswith("उवाच") else ln for ln in body.split("\n"))
        text = f"{speaker}\n\n{body}\n " if speaker else f"{body}\n "
        rows.append(RawVerse(v["chapter"], n, text))
    return rows
