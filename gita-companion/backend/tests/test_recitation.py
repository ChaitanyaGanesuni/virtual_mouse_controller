"""Recitation batch job, tested with a fake TTS engine (no GPU, no model)."""

import csv
import json
import math

import pytest

from app.providers.tts.base import Capabilities, SynthesisResult, TTSProvider, Voice, wav_bytes, wav_seconds
from app.providers.tts.indic_parler import SPEAKERS, IndicParlerProvider, describe
from workers.generate_recitation import recitation_text, run, select


class FakeTTS:
    id = "fake"
    version = "1"

    def __init__(self):
        self.calls = []

    def capabilities(self):
        return Capabilities(frozenset({"sa"}), True, False, True, 600, False, "test-licence")

    def voices(self, language=None):
        return [Voice(id="sa:Test", language="sa", name="Test")]

    def synthesize(self, text, voice, *, rate=1.0):
        self.calls.append((text, rate))
        seconds = 0.5 / rate
        sr = 8000
        samples = [0.3 * math.sin(2 * math.pi * 440 * i / sr) for i in range(int(sr * seconds))]
        data = wav_bytes(samples, sr)
        return SynthesisResult(
            wav=data, sample_rate=sr, seconds=wav_seconds(data), meta={"model": "fake-model"}
        )


@pytest.fixture(scope="module")
def ds():
    from tests.conftest import DATASET

    return json.loads(DATASET.read_text(encoding="utf-8"))


def test_fake_and_real_providers_satisfy_the_protocol():
    assert isinstance(FakeTTS(), TTSProvider)
    assert isinstance(IndicParlerProvider(), TTSProvider)


def test_indic_parler_metadata_without_loading_the_model():
    p = IndicParlerProvider()
    caps = p.capabilities()
    assert caps.native_sanskrit and caps.needs_gpu and caps.license == "Apache-2.0"
    assert {v.language for v in p.voices()} == set(SPEAKERS)
    assert [v.name for v in p.voices("sa")] == ["Aryan", "Vasudha"]
    assert "slow pace" in describe("Aryan", 0.7)
    assert "moderate pace" in describe("Aryan", 1.0)


def test_wav_helpers_round_trip():
    data = wav_bytes([0.0] * 16000, 16000)
    assert data[:4] == b"RIFF"
    assert wav_seconds(data) == pytest.approx(1.0)


def test_recitation_text_includes_speaker_heading_and_half_verses(ds):
    speakers = {s["id"]: s for s in ds["speakers"]}
    v = next(v for v in ds["verses"] if v["id"] == "2.11")
    text = recitation_text(v, speakers)
    assert text.startswith("श्रीभगवानुवाच ।")
    assert text.count("\n") == len(v["sanskrit"].split("\n"))


def test_batch_generates_normal_and_slow_and_is_resumable(ds, tmp_path):
    tts = FakeTTS()
    verses = select(ds, {"2.47", "2.48"}, None)
    stats = run(ds, tts, "sa:Test", tmp_path, verses, log=lambda m: None)
    assert stats == {"generated": 4, "skipped": 0}
    assert sorted(r for _, r in tts.calls) == [0.7, 0.7, 1.0, 1.0]

    manifest = json.loads((tmp_path / "manifest.json").read_text())
    item = next(i for i in manifest["items"] if i["verse"] == "2.47" and i["style"] == "slow")
    assert (tmp_path / item["file"]).exists()
    assert item["review_status"] == "unreviewed"
    assert item["license"] == "test-licence" and item["model"] == "fake-model"
    assert item["seconds"] > 0.5  # slow is longer

    rows = list(csv.DictReader((tmp_path / "review.csv").open()))
    assert [(r["verse"], r["style"]) for r in rows] == [
        ("2.47", "normal"),
        ("2.47", "slow"),
        ("2.48", "normal"),
        ("2.48", "slow"),
    ]

    stats = run(ds, tts, "sa:Test", tmp_path, verses, log=lambda m: None)
    assert stats == {"generated": 0, "skipped": 4}
    assert len(tts.calls) == 4


def test_select_by_chapter(ds):
    assert {v["chapter"] for v in select(ds, None, {12})} == {12}
    assert len(select(ds, None, {12})) == 20
