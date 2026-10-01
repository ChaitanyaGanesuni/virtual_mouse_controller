"""Adapter for any OpenAI-compatible chat-completions API.

Covers Google Gemini (OpenAI-compatible endpoint), Groq, OpenRouter,
Mistral, a local Ollama or vLLM server, and others, so one adapter serves
every free-tier provider in llm.yaml.
"""

from __future__ import annotations

import json
from collections.abc import Iterator

import httpx

from .base import (
    Completion,
    GenerateOptions,
    LLMError,
    Message,
    ProviderRejected,
    ProviderUnavailable,
    RateLimited,
)


class OpenAICompatibleProvider:
    def __init__(
        self,
        name: str,
        base_url: str,
        model: str,
        api_key: str | None = None,
        extra_headers: dict[str, str] | None = None,
        supports_json_mode: bool = True,
        client: httpx.Client | None = None,
    ):
        self.name = name
        self.model = model
        self._url = base_url.rstrip("/") + "/chat/completions"
        self._headers = {"Content-Type": "application/json", **(extra_headers or {})}
        if api_key:
            self._headers["Authorization"] = f"Bearer {api_key}"
        self._json_mode = supports_json_mode
        self._client = client or httpx.Client()

    def __repr__(self) -> str:  # never print the API key
        return f"OpenAICompatibleProvider({self.name!r}, model={self.model!r})"

    def _body(self, messages: list[Message], opts: GenerateOptions, stream: bool) -> dict:
        body: dict = {
            "model": self.model,
            "messages": [{"role": m.role, "content": m.content} for m in messages],
            "max_tokens": opts.max_tokens,
            "temperature": opts.temperature,
        }
        if opts.json and self._json_mode:
            body["response_format"] = {"type": "json_object"}
        if stream:
            body["stream"] = True
        return body

    def _raise_for(self, resp: httpx.Response) -> None:
        if resp.status_code < 400:
            return
        detail = resp.text[:300]
        if resp.status_code == 429:
            retry = resp.headers.get("retry-after")
            try:
                retry_s = float(retry) if retry else None
            except ValueError:
                retry_s = None
            raise RateLimited(f"{self.name}: rate limited ({detail})", retry_after_s=retry_s)
        if resp.status_code >= 500:
            raise ProviderUnavailable(f"{self.name}: HTTP {resp.status_code} ({detail})")
        raise ProviderRejected(f"{self.name}: HTTP {resp.status_code} ({detail})")

    def generate(self, messages: list[Message], opts: GenerateOptions | None = None) -> Completion:
        opts = opts or GenerateOptions()
        try:
            resp = self._client.post(
                self._url,
                headers=self._headers,
                json=self._body(messages, opts, False),
                timeout=opts.timeout_s,
            )
        except httpx.HTTPError as e:
            raise ProviderUnavailable(f"{self.name}: {type(e).__name__}: {e}") from e
        self._raise_for(resp)
        try:
            data = resp.json()
            text = data["choices"][0]["message"]["content"] or ""
        except (ValueError, KeyError, IndexError, TypeError) as e:
            raise ProviderUnavailable(f"{self.name}: malformed response: {resp.text[:200]}") from e
        usage = data.get("usage") or {}
        return Completion(
            text=text,
            provider=self.name,
            model=data.get("model") or self.model,
            tokens_in=usage.get("prompt_tokens"),
            tokens_out=usage.get("completion_tokens"),
            raw=data,
        )

    def stream(self, messages: list[Message], opts: GenerateOptions | None = None) -> Iterator[str]:
        opts = opts or GenerateOptions()
        try:
            with self._client.stream(
                "POST",
                self._url,
                headers=self._headers,
                json=self._body(messages, opts, True),
                timeout=opts.timeout_s,
            ) as resp:
                if resp.status_code >= 400:
                    resp.read()
                    self._raise_for(resp)
                for line in resp.iter_lines():
                    if not line.startswith("data:"):
                        continue
                    payload = line[5:].strip()
                    if payload == "[DONE]":
                        return
                    try:
                        delta = json.loads(payload)["choices"][0].get("delta", {}).get("content")
                    except (ValueError, KeyError, IndexError) as e:
                        raise LLMError(f"{self.name}: malformed stream chunk") from e
                    if delta:
                        yield delta
        except httpx.HTTPError as e:
            raise ProviderUnavailable(f"{self.name}: {type(e).__name__}: {e}") from e
