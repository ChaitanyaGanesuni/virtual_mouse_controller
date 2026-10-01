"""LLM provider abstraction.

Every model the system talks to (free-tier hosted APIs, a local Ollama, a
paid API later) sits behind `LLMProvider`. Application code never imports a
vendor SDK; swapping or adding a provider is configuration (llm.yaml) plus,
at most, a new adapter class.
"""

from __future__ import annotations

from collections.abc import Iterator
from dataclasses import dataclass, field
from typing import Literal, Protocol, runtime_checkable

Role = Literal["system", "user", "assistant"]


@dataclass(frozen=True)
class Message:
    role: Role
    content: str


@dataclass(frozen=True)
class GenerateOptions:
    max_tokens: int = 1500
    temperature: float = 0.3
    json: bool = False  # ask for a JSON object (response_format=json_object)
    timeout_s: float = 60.0


@dataclass(frozen=True)
class Completion:
    text: str
    provider: str
    model: str
    tokens_in: int | None = None
    tokens_out: int | None = None
    raw: dict = field(default_factory=dict, repr=False, compare=False)


class LLMError(RuntimeError):
    """Base class. `retryable` tells the router whether to try again later
    or move on to the next provider."""

    retryable: bool = False


class RateLimited(LLMError):
    retryable = True

    def __init__(self, message: str, retry_after_s: float | None = None):
        super().__init__(message)
        self.retry_after_s = retry_after_s


class ProviderUnavailable(LLMError):
    """Network error, timeout, 5xx: try another provider."""

    retryable = True


class ProviderRejected(LLMError):
    """4xx other than 429 (bad key, bad request, model gone): do not retry this provider."""


class InvalidOutput(LLMError):
    """The model answered, but not in the required shape."""

    retryable = True


@runtime_checkable
class LLMProvider(Protocol):
    name: str
    model: str

    def generate(self, messages: list[Message], opts: GenerateOptions | None = None) -> Completion: ...

    def stream(self, messages: list[Message], opts: GenerateOptions | None = None) -> Iterator[str]: ...
