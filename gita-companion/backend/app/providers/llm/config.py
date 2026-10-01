"""Build the provider chain from llm.yaml + environment variables."""

from __future__ import annotations

import os
from dataclasses import dataclass
from pathlib import Path

import httpx
import yaml

from .openai_compat import OpenAICompatibleProvider
from .router import LLMRouter, RoutedProvider

DEFAULT_CONFIG = Path(__file__).resolve().parents[3] / "llm.yaml"


@dataclass(frozen=True)
class ProviderSpec:
    name: str
    base_url: str | None
    model: str
    api_key_env: str | None
    base_url_env: str | None
    daily_request_budget: int | None
    user_data_ok: bool
    supports_json_mode: bool
    extra_headers: dict[str, str]


def load_specs(path: Path = DEFAULT_CONFIG) -> list[ProviderSpec]:
    data = yaml.safe_load(path.read_text(encoding="utf-8"))
    specs = []
    for p in data["providers"]:
        specs.append(
            ProviderSpec(
                name=p["name"],
                base_url=p.get("base_url"),
                model=p["model"],
                api_key_env=p.get("api_key_env"),
                base_url_env=p.get("base_url_env"),
                daily_request_budget=p.get("daily_request_budget"),
                user_data_ok=bool(p.get("user_data_ok", False)),
                supports_json_mode=bool(p.get("supports_json_mode", True)),
                extra_headers=dict(p.get("extra_headers") or {}),
            )
        )
    return specs


def build_router(
    path: Path = DEFAULT_CONFIG,
    env: dict[str, str] | None = None,
    only: list[str] | None = None,
    require_user_data_ok: bool = False,
    client: httpx.Client | None = None,
) -> tuple[LLMRouter, list[str]]:
    """Returns the router and a list of human-readable notes about skipped providers."""
    env = dict(os.environ) if env is None else env
    routed, notes = [], []
    for spec in load_specs(path):
        if only and spec.name not in only:
            continue
        if require_user_data_ok and not spec.user_data_ok:
            notes.append(f"{spec.name}: skipped (not approved for user data)")
            continue
        base_url = env.get(spec.base_url_env) if spec.base_url_env else spec.base_url
        if not base_url:
            notes.append(f"{spec.name}: skipped ({spec.base_url_env} not set)")
            continue
        key = env.get(spec.api_key_env) if spec.api_key_env else None
        if spec.api_key_env and not key:
            notes.append(f"{spec.name}: skipped ({spec.api_key_env} not set)")
            continue
        provider = OpenAICompatibleProvider(
            name=spec.name,
            base_url=base_url,
            model=env.get(f"{spec.name.upper()}_MODEL", spec.model),
            api_key=key,
            extra_headers=spec.extra_headers,
            supports_json_mode=spec.supports_json_mode,
            client=client,
        )
        routed.append(RoutedProvider(provider, daily_request_budget=spec.daily_request_budget))
    return LLMRouter(routed), notes
