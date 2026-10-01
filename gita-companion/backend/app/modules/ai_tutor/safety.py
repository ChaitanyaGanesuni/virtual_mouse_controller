"""A deterministic check for messages that suggest the person may harm
themselves. It never blocks the answer; it adds a support note with real,
free help, shown above the answer. Keyword matching is crude, so it errs
toward showing the note."""

from __future__ import annotations

import re

_PATTERNS = [
    r"\bsuicid",
    r"\bkill (?:my ?self|me)\b",
    r"\bend (?:my|it) (?:life|all)\b",
    r"\bwant(?:ed)? to die\b",
    r"\bdon'?t want to (?:live|be alive)\b",
    r"\bself[- ]?harm",
    r"\bhurt(?:ing)? my ?self\b",
    r"\bno reason to live\b",
    r"ఆత్మహత్య",
    r"చనిపోవాల",
    r"చచ్చిపోవాల",
    r"బతకాలని లేదు",
]
_RE = re.compile("|".join(_PATTERNS), re.IGNORECASE)

SUPPORT = {
    "en": (
        "If you are thinking about harming yourself, please talk to someone now. In India you can call "
        "Tele-MANAS on 14416 or 1800-891-4416 (free, 24×7, in many Indian languages), or 112 in an "
        "emergency. You are not alone."
    ),
    "te": (
        "మీకు మిమ్మల్ని మీరు హాని చేసుకోవాలనే ఆలోచనలు వస్తుంటే, దయచేసి ఇప్పుడే ఎవరితోనైనా మాట్లాడండి. "
        "టెలి-మానస్: 14416 లేదా 1800-891-4416 (ఉచితం, 24×7). అత్యవసరమైతే 112కు కాల్ చేయండి. "
        "మీరు ఒంటరి కాదు."
    ),
}


def support_note(text: str, language: str) -> str | None:
    return SUPPORT.get(language, SUPPORT["en"]) if _RE.search(text) else None
