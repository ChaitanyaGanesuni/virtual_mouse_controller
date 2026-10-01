"""Free-tier-first routing: try providers in order, back off on rate limits,
skip providers that are cooling down or rejected, and enforce per-provider
daily request budgets so a batch job never burns through a free quota."""

from __future__ import annotations

import time
from collections.abc import Callable, Iterator
from dataclasses import dataclass, field

from .base import (
    Completion,
    GenerateOptions,
    LLMError,
    LLMProvider,
    Message,
    ProviderRejected,
    RateLimited,
)


class AllProvidersFailed(LLMError):
    def __init__(self, errors: list[tuple[str, Exception]]):
        self.errors = errors
        summary = "; ".join(f"{name}: {e}" for name, e in errors) or "no providers configured"
        super().__init__(f"all LLM providers failed ({summary})")


@dataclass
class _State:
    cooldown_until: float = 0.0
    disabled: bool = False
    requests_today: int = 0
    day: int = -1


@dataclass
class RoutedProvider:
    provider: LLMProvider
    daily_request_budget: int | None = None  # None = unlimited (e.g. local Ollama)
    default_cooldown_s: float = 60.0
    state: _State = field(default_factory=_State)


class LLMRouter:
    """An LLMProvider that delegates to an ordered list of providers."""

    def __init__(
        self,
        providers: list[RoutedProvider],
        clock: Callable[[], float] = time.time,
    ):
        self._providers = providers
        self._clock = clock
        self.name = "router"
        self.model = "+".join(p.provider.name for p in providers)

    def _available(self, rp: RoutedProvider) -> bool:
        now = self._clock()
        day = int(now // 86400)
        if rp.state.day != day:
            rp.state.day, rp.state.requests_today = day, 0
        if rp.state.disabled or now < rp.state.cooldown_until:
            return False
        return rp.daily_request_budget is None or rp.state.requests_today < rp.daily_request_budget

    def status(self) -> dict[str, str]:
        out = {}
        for rp in self._providers:
            s = rp.state
            if s.disabled:
                out[rp.provider.name] = "disabled"
            elif self._clock() < s.cooldown_until:
                out[rp.provider.name] = f"cooling down {s.cooldown_until - self._clock():.0f}s"
            else:
                budget = rp.daily_request_budget
                out[rp.provider.name] = f"{s.requests_today}/{budget if budget is not None else '∞'} today"
        return out

    def next_available_in(self) -> float | None:
        """Seconds until some provider can be tried again (None: none ever will today)."""
        waits = [
            max(0.0, rp.state.cooldown_until - self._clock())
            for rp in self._providers
            if not rp.state.disabled
            and (rp.daily_request_budget is None or rp.state.requests_today < rp.daily_request_budget)
        ]
        return min(waits) if waits else None

    def generate(self, messages: list[Message], opts: GenerateOptions | None = None) -> Completion:
        return self.call(lambda p: p.generate(messages, opts))

    def call(self, fn: Callable[[LLMProvider], Completion]) -> Completion:
        """Run `fn` against the first provider that succeeds. `fn` may raise
        InvalidOutput (e.g. failed schema validation) to move on to the next
        provider."""
        errors: list[tuple[str, Exception]] = []
        for rp in self._providers:
            if not self._available(rp):
                continue
            rp.state.requests_today += 1
            try:
                return fn(rp.provider)
            except RateLimited as e:
                rp.state.cooldown_until = self._clock() + (e.retry_after_s or rp.default_cooldown_s)
                errors.append((rp.provider.name, e))
            except ProviderRejected as e:
                rp.state.disabled = True  # bad key / unknown model: stop using it this run
                errors.append((rp.provider.name, e))
            except LLMError as e:
                errors.append((rp.provider.name, e))
        raise AllProvidersFailed(errors)

    def stream(self, messages: list[Message], opts: GenerateOptions | None = None) -> Iterator[str]:
        for rp in self._providers:
            if self._available(rp):
                rp.state.requests_today += 1
                return rp.provider.stream(messages, opts)
        raise AllProvidersFailed([])
