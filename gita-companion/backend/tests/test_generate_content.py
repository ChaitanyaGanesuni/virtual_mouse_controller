import json

import pytest
from gita_content.canon import Canon

from app.providers.llm import Completion, LLMRouter, RateLimited, RoutedProvider, ValidationFailed
from workers.generate_content import CHAPTER_FILE, VERSE_FILE, Task, plan, run_batch
from workers.validation import validate_chapter, validate_verse

CANON = Canon.load()
IAST_247 = "karmaṇyevādhikāraste mā phaleṣu kadācana ।\nmā karmaphalaheturbhūrmā te saṅgo'stvakarmaṇi ॥"


def good_verse(lang="en") -> dict:
    t = (
        (lambda s: s)
        if lang == "en"
        else (lambda s: "కర్మ చేయడం మన బాధ్యత, ఫలితం మన చేతిలో లేదు. " * (len(s) // 40 + 1))
    )
    return {
        "simple": t("You have a right to your actions, but never to their results. " * 3),
        "deep": t("The verse separates action from the craving for its fruit, see also 3.19. " * 6),
        "practical": t("At work, give full effort to the task and let go of anxiety about outcomes. " * 4),
        "story": t("A gardener waters the seed every day without pulling it up to check the roots. " * 4),
        "child": t("Do your homework well; worrying about marks will not help. " * 3),
        "word_meanings": [
            {"word": "karmaṇi", "meaning": "in action"},
            {"word": "eva", "meaning": "only"},
            {"word": "adhikāraḥ", "meaning": "right"},
            {"word": "phaleṣu", "meaning": "in the fruits"},
        ],
        "sanskrit_terms": [{"term": "karma", "meaning": t("Action, especially one's duty.")}],
        "uncertain": [],
    }


def test_valid_verse_passes():
    out = validate_verse(good_verse(), iast=IAST_247, language="en", canon=CANON)
    assert out["word_meanings"][0]["word"] == "karmaṇi"


@pytest.mark.parametrize(
    "mutate,message",
    [
        (lambda o: o["word_meanings"].append({"word": "dharmakṣetre", "meaning": "x"}), "does not appear"),
        (lambda o: o.update(deep=o["deep"] + " As 2.99 says, ..."), "2.99, which does not exist"),
        (lambda o: o.update(simple="too short"), "between"),
        (lambda o: o.update(sanskrit_terms=[{"term": "mokṣa", "meaning": "liberation"}]), "does not appear"),
        (lambda o: o.pop("child"), '"child" must be a non-empty string'),
        (lambda o: o.update(uncertain="none"), "list of strings"),
    ],
)
def test_invalid_verse_output_is_rejected(mutate, message):
    obj = good_verse()
    mutate(obj)
    with pytest.raises(ValidationFailed, match=message):
        validate_verse(obj, iast=IAST_247, language="en", canon=CANON)


def test_telugu_requested_but_english_returned_is_rejected():
    with pytest.raises(ValidationFailed, match="Telugu script"):
        validate_verse(good_verse("en"), iast=IAST_247, language="te", canon=CANON)
    out = validate_verse(good_verse("te"), iast=IAST_247, language="te", canon=CANON)
    assert out["simple"].startswith("కర్మ")


def test_chapter_overview_must_stay_inside_its_chapter():
    obj = {
        "summary": "Arjuna is overcome with grief and Krishna begins to teach (2.11). " * 6,
        "theme": "The eternal Self, duty, and equanimity in action.",
        "uncertain": [],
    }
    assert validate_chapter(obj, chapter=2, language="en", canon=CANON)["theme"].startswith("The eternal")
    obj["summary"] += " Compare 3.19."
    with pytest.raises(ValidationFailed, match="only verses of chapter 2"):
        validate_chapter(obj, chapter=2, language="en", canon=CANON)


class ScriptedProvider:
    """A fake LLMProvider: replies from a function of the user prompt."""

    def __init__(self, name, reply):
        self.name, self.model, self.reply, self.calls = name, f"{name}-model", reply, 0

    def generate(self, messages, opts=None):
        self.calls += 1
        result = self.reply(messages[-1].content)
        if isinstance(result, Exception):
            raise result
        return Completion(text=result, provider=self.name, model=self.model)

    def stream(self, messages, opts=None):
        raise NotImplementedError


def reply_for(prompt: str) -> str:
    if "verses of the chapter" in prompt:
        return json.dumps(
            {
                "summary": "A chapter summary that is long enough to pass validation. " * 7,
                "theme": "A theme sentence of reasonable length.",
                "uncertain": [],
            }
        )
    return json.dumps(good_verse())


@pytest.fixture(scope="module")
def ds(request):
    from tests.conftest import DATASET

    return json.loads(DATASET.read_text(encoding="utf-8"))


def test_plan_and_resume(ds, tmp_path):
    tasks = list(plan(ds, ["chapter", "verse"], ["en"], {"2", "2.47"}))
    assert [t.key.rsplit(":", 1)[0] for t in tasks] == ["chapter:2:en", "verse:2.47:en"]

    p = ScriptedProvider("free", reply_for)
    router = LLMRouter([RoutedProvider(p)])
    stats = run_batch(ds, router, tmp_path, tasks, sleep=lambda s: None, log=lambda m: None)
    assert stats["generated"] == 2 and stats["failed"] == 0

    rec = json.loads((tmp_path / VERSE_FILE).read_text().splitlines()[0])
    assert rec["provider"] == "free" and rec["prompt_version"] == "verse-explain-v1"
    assert rec["content"]["word_meanings"][0]["word"] == "karmaṇi"
    assert (tmp_path / CHAPTER_FILE).exists()

    stats = run_batch(ds, router, tmp_path, tasks, sleep=lambda s: None, log=lambda m: None)
    assert stats == {"done_before": 2, "generated": 0, "failed": 0, "remaining": 0}
    assert p.calls == 2, "finished tasks are not regenerated"


def test_stops_when_all_providers_are_exhausted(ds, tmp_path):
    p = ScriptedProvider("limited", lambda prompt: RateLimited("quota", retry_after_s=None))
    router = LLMRouter([RoutedProvider(p, daily_request_budget=1)])
    tasks = [Task("verse", "2.47", "en"), Task("verse", "2.48", "en"), Task("verse", "2.49", "en")]
    logs = []
    stats = run_batch(ds, router, tmp_path, tasks, sleep=lambda s: None, log=logs.append)
    assert stats["generated"] == 0 and stats["failed"] == 1
    assert p.calls == 1
    assert any("stopping" in m for m in logs)
    assert (tmp_path / "failures.log").exists()


def test_falls_back_to_second_provider_on_invalid_output(ds, tmp_path):
    bad = ScriptedProvider("sloppy", lambda prompt: '{"simple": "x"}')
    good = ScriptedProvider("careful", reply_for)
    router = LLMRouter([RoutedProvider(bad), RoutedProvider(good)])
    run_batch(ds, router, tmp_path, [Task("verse", "2.47", "en")], sleep=lambda s: None, log=lambda m: None)
    rec = json.loads((tmp_path / VERSE_FILE).read_text())
    assert rec["provider"] == "careful"
    assert bad.calls == 2, "one attempt plus one repair"


@pytest.mark.parametrize(
    "text,bad",
    [
        ("Compare 3.19.", None),
        ("See 2.99.", "2.99"),
        ("As in (18.66), surrender.", None),
        ("BG 19:1 says", "19.1"),
        ("version 1.2.3 and 10.234 are not refs", None),
    ],
)
def test_reference_detection(text, bad):
    from workers.validation import check_references

    if bad is None:
        check_references(text, CANON, "f")
    else:
        with pytest.raises(ValidationFailed, match=bad.replace(".", r"\.")):
            check_references(text, CANON, "f")
