"""generate_structured(): JSON output that must pass a validator.

Free-tier models do not all support strict JSON schemas, so we ask for a
JSON object, parse it leniently (code fences, leading prose), validate it
in code, and give the same model one chance to repair its answer before the
router moves on to the next provider.
"""

from __future__ import annotations

import json
import re
from collections.abc import Callable
from dataclasses import dataclass
from typing import Generic, TypeVar

from .base import Completion, GenerateOptions, InvalidOutput, LLMProvider, Message
from .router import LLMRouter

T = TypeVar("T")

_FENCE = re.compile(r"^```(?:json)?\s*|\s*```$", re.IGNORECASE)


class ValidationFailed(ValueError):
    """Raised by validators; the message is shown to the model when repairing."""


@dataclass(frozen=True)
class Structured(Generic[T]):
    value: T
    completion: Completion
    repaired: bool


def parse_json_object(text: str) -> dict:
    s = _FENCE.sub("", text.strip())
    try:
        obj = json.loads(s)
    except ValueError:
        start, end = s.find("{"), s.rfind("}")
        if start < 0 or end <= start:
            raise ValidationFailed("the answer is not a JSON object") from None
        try:
            obj = json.loads(s[start : end + 1])
        except ValueError as e:
            raise ValidationFailed(f"invalid JSON: {e}") from None
    if not isinstance(obj, dict):
        raise ValidationFailed("the answer must be a JSON object")
    return obj


def generate_structured(
    llm: LLMProvider | LLMRouter,
    messages: list[Message],
    validate: Callable[[dict], T],
    opts: GenerateOptions | None = None,
) -> Structured[T]:
    opts = opts or GenerateOptions(json=True)
    result: dict = {}

    def attempt(provider: LLMProvider) -> Completion:
        first = provider.generate(messages, opts)
        try:
            result["value"], result["repaired"] = validate(parse_json_object(first.text)), False
            return first
        except ValidationFailed as problem:
            repair = [
                *messages,
                Message("assistant", first.text),
                Message(
                    "user",
                    f"Your answer was rejected: {problem}. Reply again with only the corrected JSON object.",
                ),
            ]
            second = provider.generate(repair, opts)
            try:
                result["value"], result["repaired"] = validate(parse_json_object(second.text)), True
            except ValidationFailed as again:
                raise InvalidOutput(f"{provider.name}: {again}") from again
            return second

    completion = llm.call(attempt) if isinstance(llm, LLMRouter) else attempt(llm)
    return Structured(value=result["value"], completion=completion, repaired=result["repaired"])
