"""AI tutor: grounding, citation validation, quotas, cache, safety.

The LLM is scripted, so these tests show exactly what the server does with
good, bad and fabricated answers. The exit criterion of Phase 6 is here:
every answer that reaches the app carries validated sources, and invalid
references are rejected.
"""

import pytest
from sqlalchemy import text

from app.providers.llm import ProviderRejected, ProviderUnavailable, RateLimited
from tests.conftest import ScriptedLLM, answer, signup


def _conv(client, t, **body):
    r = client.post("/v1/tutor/conversations", json=body, headers=t["headers"])
    assert r.status_code == 201, r.text
    return r.json()["id"]


def _ask(client, t, conv, question, **extra):
    return client.post(
        f"/v1/tutor/conversations/{conv}/messages", json={"question": question, **extra}, headers=t["headers"]
    )


def _prompt(llm_call) -> str:
    return llm_call[-1].content  # the final user turn


# ---- grounding ----------------------------------------------------------------


def test_pinned_answer_has_validated_sources_and_ai_label(make_client):
    fake = ScriptedLLM(replies=[answer()])
    client, _ = make_client(fake)
    t = signup(client)
    conv = _conv(client, t, pinned_verse_id="2.47")
    r = _ask(client, t, conv, "What does this verse teach?")
    assert r.status_code == 200, r.text
    a = r.json()["answer"]
    assert a["ai_generated"] and a["model"] == "fake-model" and a["provider"] == "fake"
    assert a["prompt_version"] == "tutor-v1"
    assert a["citations"] == [{"verse": "2.47", "source_id": "bg-sanskrit-gita-json"}]
    assert a["retrieval"] == ["pinned"] and a["flags"] == []

    prompt = _prompt(fake.calls[0])
    # The real text of the pinned verse and its neighbours is in the prompt.
    assert "[BG 2.47 | sanskrit | bg-sanskrit-gita-json]" in prompt
    assert "karmaṇyevādhikāraste" in prompt
    assert "BG 2.46 | sanskrit" in prompt and "BG 2.48 | sanskrit" in prompt
    assert "Allowed citations: 2.47, 2.46, 2.48." in prompt


@pytest.mark.parametrize(
    "bad_text, complaint",
    [
        ("See BG 2.99 for more.", "2.99, which does not exist"),
        ("Compare BG 19.1.", "19.1, which does not exist"),
        ("Chapter 20 says otherwise.", "chapter 20"),
        ("This echoes BG 3.19.", "3.19, which is not among the passages"),
    ],
)
def test_invalid_references_are_rejected_and_repaired(make_client, bad_text, complaint):
    fake = ScriptedLLM(replies=[answer(f"Act without clinging (BG 2.47). {bad_text}"), answer()])
    client, _ = make_client(fake)
    t = signup(client)
    r = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "Explain.")
    assert r.status_code == 200
    a = r.json()["answer"]
    assert "repaired" in a["flags"]
    assert a["content"] == "Act without clinging to results (BG 2.47)."
    repair_request = fake.calls[1][-1].content
    assert "rejected" in repair_request and complaint in repair_request


def test_fabricating_model_falls_back_to_next_provider(make_client):
    liar = ScriptedLLM("liar", [answer("See BG 2.99."), answer("See BG 18.80.")])
    honest = ScriptedLLM("honest", [answer()])
    client, _ = make_client(liar, honest)
    t = signup(client)
    r = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "Explain.")
    assert r.status_code == 200 and r.json()["answer"]["provider"] == "honest"


def test_no_verified_answer_when_every_provider_fabricates(make_client):
    a = ScriptedLLM("a", [answer("BG 2.99"), answer("BG 2.99")])
    b = ScriptedLLM("b", [answer("BG 4.99"), answer("BG 4.99")])
    client, _ = make_client(a, b)
    t = signup(client)
    conv = _conv(client, t, pinned_verse_id="2.47")
    r = _ask(client, t, conv, "Explain.")
    assert r.status_code == 502 and r.json()["error"]["code"] == "no_verified_answer"
    # Nothing unverified was stored.
    detail = client.get(f"/v1/tutor/conversations/{conv}", headers=t["headers"]).json()
    assert detail["messages"] == []


def test_invalid_citation_entries_are_removed_not_shown(make_client):
    fake = ScriptedLLM(
        replies=[answer("Act without clinging to results.", cites=("2.47", "18.99", "3.19", "2.48"))]
    )
    client, _ = make_client(fake)
    t = signup(client)
    r = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "Explain.")
    a = r.json()["answer"]
    assert [c["verse"] for c in a["citations"]] == ["2.47", "2.48"]
    assert "citations_removed" in a["flags"]


def test_answer_must_cite_something(make_client):
    fake = ScriptedLLM(replies=[answer("Be calm.", cites=()), answer()])
    client, _ = make_client(fake)
    t = signup(client)
    r = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "Explain.")
    assert r.status_code == 200
    assert "cite at least one" in fake.calls[1][-1].content


def test_inline_references_become_citations_and_bad_sources_are_replaced(make_client):
    reply = answer("Work without attachment (BG 2.47), with evenness (BG 2.48).", cites=())
    reply["citations"] = [{"verse": "BG 2.47", "source_id": "made-up-source"}]
    client, _ = make_client(ScriptedLLM(replies=[reply]))
    t = signup(client)
    a = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "Explain.").json()["answer"]
    assert a["citations"] == [
        {"verse": "2.47", "source_id": "bg-sanskrit-gita-json"},
        {"verse": "2.48", "source_id": "bg-sanskrit-gita-json"},
    ]


def test_quotes_are_checked_against_the_passages(make_client):
    real = '"mā phaleṣu kadācana" (BG 2.47)'
    fake_quote = '"you must always win every battle you fight" (BG 2.47)'
    client, _ = make_client(ScriptedLLM(replies=[answer(f"Krishna says {real}. Some claim {fake_quote}.")]))
    t = signup(client)
    a = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "Explain.").json()["answer"]
    assert '"mā phaleṣu kadācana"' in a["content"]
    assert '"you must always' not in a["content"] and "you must always win every battle" in a["content"]
    assert "unverified_quotes" in a["flags"]


def test_wrong_language_is_repaired(make_client):
    te = answer("ఫలితాలపై ఆసక్తి లేకుండా కర్మ చేయండి (BG 2.47).")
    fake = ScriptedLLM(replies=[answer(), te])
    client, _ = make_client(fake)
    t = signup(client)
    a = _ask(client, t, _conv(client, t, pinned_verse_id="2.47", language="te"), "వివరించండి").json()["answer"]
    assert a["content"].startswith("ఫలితాలపై") and a["language"] == "te"
    assert "Telugu script" in fake.calls[1][-1].content


def test_out_of_scope_needs_no_citation(make_client):
    reply = answer("I can help with questions about the Bhagavad Gita.", cites=(), out_of_scope=True)
    client, _ = make_client(ScriptedLLM(replies=[reply]))
    t = signup(client)
    a = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "What is the capital of France?").json()[
        "answer"
    ]
    assert a["out_of_scope"] and a["citations"] == []


def test_uncertain_points_are_returned_and_checked(make_client):
    fake = ScriptedLLM(
        replies=[
            answer(uncertain_points=["Whether BG 4.99 applies"]),
            answer(uncertain_points=["How literally to read 'adhikāra' here"], confidence="low"),
        ]
    )
    client, _ = make_client(fake)
    t = signup(client)
    a = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "Explain.").json()["answer"]
    assert a["uncertain_points"] == ["How literally to read 'adhikāra' here"] and a["confidence"] == "low"


# ---- retrieval ----------------------------------------------------------------


def test_explicit_references_and_chapters_in_the_question(make_client):
    fake = ScriptedLLM(replies=[answer("Compare BG 3.19 with BG 18.66.", cites=("3.19", "18.66"))])
    client, _ = make_client(fake)
    t = signup(client)
    r = _ask(client, t, _conv(client, t), "How do 3.19 and chapter 18, verse 66 relate? And chapter 12?")
    a = r.json()["answer"]
    assert a["retrieval"] == ["explicit"]
    prompt = _prompt(fake.calls[0])
    assert "[BG 3.19 | sanskrit" in prompt and "[BG 18.66 | sanskrit" in prompt
    assert "[BG chapter 12 | summary | gita-companion-editorial] (AI-generated, unreviewed)" in prompt


def test_model_suggested_verses_are_checked_against_the_table(make_client):
    fake = ScriptedLLM(replies=[{"verses": ["2.47", "BG 2.99", "6.5"]}, answer(cites=("2.47",))])
    client, _ = make_client(fake)
    t = signup(client)
    r = _ask(client, t, _conv(client, t), "How can I stop worrying about outcomes?")
    a = r.json()["answer"]
    assert a["retrieval"] == ["suggested"]
    prompt = _prompt(fake.calls[1])
    assert "Allowed citations: 2.47, 6.5." in prompt and "2.99" not in prompt


def test_keyword_retrieval_over_translations(make_client, seeded):
    fake = ScriptedLLM(replies=[answer()])
    client, _ = make_client(fake)
    t = signup(client)
    with seeded.begin() as c:
        c.execute(
            text(
                "INSERT INTO verse_text (id, verse_id, source_id, kind, language, body) VALUES "
                "(gen_random_uuid(), '2.47', 'gita-companion-editorial', 'simple', 'en', "
                "'Do your duty, but do not cling to the fruits of action.')"
            )
        )
    try:
        r = _ask(client, t, _conv(client, t), "Why shouldn't I cling to the fruits of my work?")
        assert r.json()["answer"]["retrieval"] == ["keyword"]
        assert "[BG 2.47 | simple | gita-companion-editorial] (AI-generated, unreviewed)" in _prompt(
            fake.calls[0]
        )
    finally:
        with seeded.begin() as c:
            c.execute(text("DELETE FROM verse_text WHERE kind = 'simple' AND verse_id = '2.47'"))


def test_follow_up_questions_keep_earlier_citations(make_client):
    fake = ScriptedLLM(
        replies=[answer("See BG 3.19.", cites=("3.19",)), answer("As in BG 3.19.", cites=("3.19",))]
    )
    client, _ = make_client(fake)
    t = signup(client)
    conv = _conv(client, t)
    assert _ask(client, t, conv, "What does 3.19 say?").status_code == 200
    r = _ask(client, t, conv, "Can you say more about that?")
    assert r.status_code == 200 and r.json()["answer"]["retrieval"] == ["conversation"]
    # History is sent to the model.
    roles = [m.role for m in fake.calls[1]]
    assert roles == ["system", "user", "assistant", "user"]


# ---- limits, cache, errors -----------------------------------------------------


def test_daily_quota(make_client):
    fake = ScriptedLLM(replies=[answer(), answer()])
    client, _ = make_client(fake, tutor_daily_questions=2)
    t = signup(client)
    conv = _conv(client, t, pinned_verse_id="2.47")
    assert _ask(client, t, conv, "One?").status_code == 200
    assert _ask(client, t, conv, "Two?").status_code == 200
    r = _ask(client, t, conv, "Three?")
    assert r.status_code == 429 and r.json()["error"]["code"] == "quota_exceeded"
    assert int(r.headers["retry-after"]) > 0
    status = client.get("/v1/tutor/status", headers=t["headers"]).json()
    assert status == {"available": True, "daily_limit": 2, "questions_left_today": 0}


def test_first_questions_are_cached_across_users_and_do_not_use_quota(make_client):
    fake = ScriptedLLM(replies=[answer()])
    client, _ = make_client(fake, tutor_daily_questions=1)
    for i in range(3):
        t = signup(client)
        conv = _conv(client, t, pinned_verse_id="2.47")
        r = client.post(
            f"/v1/tutor/conversations/{conv}/explain", json={"mode": "practical"}, headers=t["headers"]
        )
        assert r.status_code == 200
        a = r.json()["answer"]
        assert a["citations"][0]["verse"] == "2.47"
        if i:
            assert a["provider"] == "cache" and "cached" in a["flags"] and a["model"] == "fake-model"
    assert len(fake.calls) == 1
    status = client.get("/v1/tutor/status", headers=t["headers"]).json()
    assert status["questions_left_today"] == 1


def test_tutor_without_providers_is_unavailable(make_client):
    client, _ = make_client()
    t = signup(client)
    r = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "Explain.")
    assert r.status_code == 503 and r.json()["error"]["code"] == "tutor_unavailable"


def test_busy_providers(make_client):
    a = ScriptedLLM("a", [RateLimited("slow down", retry_after_s=30)])
    b = ScriptedLLM("b", [ProviderRejected("bad key")])
    client, _ = make_client(a, b)
    t = signup(client)
    conv = _conv(client, t, pinned_verse_id="2.47")
    r = _ask(client, t, conv, "Explain.")
    assert r.status_code == 503 and r.json()["error"]["code"] == "providers_busy"
    assert r.headers["retry-after"] == "30"  # a cools down for 30 s; b is disabled

    # A transient failure: try again straight away.
    client2, _ = make_client(ScriptedLLM("c", [ProviderUnavailable("timeout")]))
    t2 = signup(client2)
    r = _ask(client2, t2, _conv(client2, t2, pinned_verse_id="2.47"), "Explain.")
    assert r.status_code == 503 and r.headers["retry-after"] == "1"


def test_conversations_are_private(make_client):
    client, _ = make_client(ScriptedLLM(replies=[answer()]))
    owner, other = signup(client), signup(client)
    conv = _conv(client, owner, pinned_verse_id="2.47")
    assert client.get(f"/v1/tutor/conversations/{conv}", headers=other["headers"]).status_code == 404
    assert _ask(client, other, conv, "Explain.").status_code == 404
    assert client.get("/v1/tutor/conversations", headers=other["headers"]).json() == []


def test_conversation_history_and_delete(make_client):
    client, _ = make_client(ScriptedLLM(replies=[answer()]))
    t = signup(client)
    conv = _conv(client, t, pinned_verse_id="2.47", mode="simple")
    _ask(client, t, conv, "What is my duty here?")
    listed = client.get("/v1/tutor/conversations", headers=t["headers"]).json()
    assert listed[0]["id"] == conv and listed[0]["title"] == "What is my duty here?"
    detail = client.get(f"/v1/tutor/conversations/{conv}", headers=t["headers"]).json()
    assert [m["role"] for m in detail["messages"]] == ["user", "assistant"]
    assert detail["messages"][1]["citations"][0]["verse"] == "2.47"
    assert client.delete(f"/v1/tutor/conversations/{conv}", headers=t["headers"]).status_code == 204
    assert client.get(f"/v1/tutor/conversations/{conv}", headers=t["headers"]).status_code == 404


def test_unknown_pinned_verse_and_bad_input(make_client):
    client, _ = make_client(ScriptedLLM())
    t = signup(client)
    r = client.post("/v1/tutor/conversations", json={"pinned_verse_id": "2.99"}, headers=t["headers"])
    assert r.status_code == 404
    r = client.post("/v1/tutor/conversations", json={"mode": "gossip"}, headers=t["headers"])
    assert r.status_code == 422 and r.json()["error"]["code"] == "invalid_request"
    conv = _conv(client, t)
    assert _ask(client, t, conv, "x" * 1001).status_code == 422


def test_distress_adds_support_note(make_client):
    client, _ = make_client(ScriptedLLM(replies=[answer()]))
    t = signup(client)
    a = _ask(client, t, _conv(client, t, pinned_verse_id="2.47"), "I failed again and I want to die").json()[
        "answer"
    ]
    assert "14416" in a["support"]


def test_only_providers_approved_for_user_data_answer_questions():
    from app.providers.llm import build_router

    env = {
        "GEMINI_API_KEY": "k",
        "GROQ_API_KEY": "k",
        "OPENROUTER_API_KEY": "k",
        "OLLAMA_BASE_URL": "http://o/v1",
    }
    router, notes = build_router(env=env, require_user_data_ok=True)
    assert router.model == "groq+ollama"
    assert any("gemini" in n and "not approved" in n for n in notes)
