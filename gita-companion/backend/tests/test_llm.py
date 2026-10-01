"""LLM provider layer, tested against a fake HTTP server (no network, no keys)."""

import json

import httpx
import pytest

from app.providers.llm import (
    AllProvidersFailed,
    GenerateOptions,
    InvalidOutput,
    LLMRouter,
    Message,
    OpenAICompatibleProvider,
    ProviderRejected,
    RateLimited,
    RoutedProvider,
    ValidationFailed,
    build_router,
    generate_structured,
    parse_json_object,
)

MSGS = [Message("user", "hi")]


def ok(text: str, model: str = "m") -> httpx.Response:
    return httpx.Response(
        200,
        json={
            "model": model,
            "choices": [{"message": {"content": text}}],
            "usage": {"prompt_tokens": 3, "completion_tokens": 5},
        },
    )


def provider(handler, name="p", **kw) -> OpenAICompatibleProvider:
    return OpenAICompatibleProvider(
        name=name,
        base_url="https://llm.test/v1",
        model="m",
        api_key="secret-key",
        client=httpx.Client(transport=httpx.MockTransport(handler)),
        **kw,
    )


def test_request_shape_and_completion():
    seen = {}

    def handler(req: httpx.Request):
        seen["url"] = str(req.url)
        seen["auth"] = req.headers["authorization"]
        seen["body"] = json.loads(req.content)
        return ok("hello")

    c = provider(handler).generate(MSGS, GenerateOptions(json=True, max_tokens=50))
    assert c.text == "hello" and (c.tokens_in, c.tokens_out) == (3, 5)
    assert seen["url"] == "https://llm.test/v1/chat/completions"
    assert seen["auth"] == "Bearer secret-key"
    assert seen["body"]["response_format"] == {"type": "json_object"}
    assert seen["body"]["max_tokens"] == 50


def test_api_key_never_in_repr():
    assert "secret-key" not in repr(provider(lambda r: ok("x")))


@pytest.mark.parametrize(
    "status,headers,exc",
    [(429, {"retry-after": "7"}, RateLimited), (401, {}, ProviderRejected), (503, {}, Exception)],
)
def test_error_mapping(status, headers, exc):
    p = provider(lambda r: httpx.Response(status, headers=headers, text="nope"))
    with pytest.raises(exc) as info:
        p.generate(MSGS)
    if status == 429:
        assert info.value.retry_after_s == 7


def test_network_error_is_retryable():
    def handler(req):
        raise httpx.ConnectError("down")

    with pytest.raises(Exception) as info:
        provider(handler).generate(MSGS)
    assert getattr(info.value, "retryable", False)


def test_stream():
    chunks = [
        'data: {"choices":[{"delta":{"content":"Hel"}}]}',
        'data: {"choices":[{"delta":{"content":"lo"}}]}',
        "data: [DONE]",
    ]

    def handler(req):
        return httpx.Response(200, text="\n\n".join(chunks))

    assert "".join(provider(handler).stream(MSGS)) == "Hello"


class Clock:
    def __init__(self):
        self.t = 1_000_000.0

    def __call__(self):
        return self.t


def test_router_falls_back_and_cools_down_rate_limited_provider():
    calls = []

    def limited(req):
        calls.append("a")
        return httpx.Response(429, headers={"retry-after": "30"})

    def fine(req):
        calls.append("b")
        return ok("from b")

    clock = Clock()
    router = LLMRouter(
        [RoutedProvider(provider(limited, "a")), RoutedProvider(provider(fine, "b"))], clock=clock
    )
    assert router.generate(MSGS).provider == "b"
    assert router.generate(MSGS).provider == "b"
    assert calls == ["a", "b", "b"], "a is skipped while cooling down"
    clock.t += 31
    router.generate(MSGS)
    assert calls[-2:] == ["a", "b"], "a is tried again after its cooldown"


def test_router_disables_rejected_provider_and_respects_daily_budget():
    clock = Clock()
    router = LLMRouter(
        [
            RoutedProvider(provider(lambda r: httpx.Response(401), "badkey")),
            RoutedProvider(provider(lambda r: ok("x"), "budgeted"), daily_request_budget=2),
        ],
        clock=clock,
    )
    router.generate(MSGS)
    router.generate(MSGS)
    with pytest.raises(AllProvidersFailed):
        router.generate(MSGS)
    assert router.status()["badkey"] == "disabled"
    clock.t += 86400
    assert router.generate(MSGS).provider == "budgeted", "budget resets the next day"


def test_parse_json_object_is_lenient_about_fences_and_prose():
    assert parse_json_object('```json\n{"a": 1}\n```') == {"a": 1}
    assert parse_json_object('Sure! Here it is: {"a": 1} Hope this helps.') == {"a": 1}
    with pytest.raises(ValidationFailed):
        parse_json_object("no json here")
    with pytest.raises(ValidationFailed):
        parse_json_object("[1, 2]")


def _needs_answer(obj: dict) -> str:
    if "answer" not in obj:
        raise ValidationFailed("missing 'answer'")
    return obj["answer"]


def test_structured_repairs_once():
    replies = iter(['{"wrong": 1}', '{"answer": "42"}'])
    out = generate_structured(provider(lambda r: ok(next(replies))), MSGS, _needs_answer)
    assert out.value == "42" and out.repaired


def test_structured_moves_to_next_provider_after_failed_repair():
    router = LLMRouter(
        [
            RoutedProvider(provider(lambda r: ok('{"wrong": 1}'), "sloppy")),
            RoutedProvider(provider(lambda r: ok('{"answer": "ok"}'), "careful")),
        ]
    )
    out = generate_structured(router, MSGS, _needs_answer)
    assert out.value == "ok" and out.completion.provider == "careful"


def test_structured_single_provider_failure_raises():
    with pytest.raises(InvalidOutput):
        generate_structured(provider(lambda r: ok("{}")), MSGS, _needs_answer)


def test_build_router_skips_providers_without_keys():
    router, notes = build_router(env={"GROQ_API_KEY": "k"})
    assert router.model == "groq"
    assert any("GEMINI_API_KEY not set" in n for n in notes)
    assert any("OLLAMA_BASE_URL not set" in n for n in notes)


def test_build_router_user_data_filter_and_model_override():
    env = {"GEMINI_API_KEY": "k", "GROQ_API_KEY": "k", "GROQ_MODEL": "other-model"}
    router, notes = build_router(env=env, require_user_data_ok=True)
    assert router.model == "groq"
    assert any("gemini: skipped (not approved for user data)" in n for n in notes)
    assert router._providers[0].provider.model == "other-model"
