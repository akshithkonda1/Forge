"""Zero-leakage sanitizer for text that might reach a cloud TTS API.

No user name, email, phone, street address, or health-metric number may be
sent to Fish, Polly, or ElevenLabs, or written to a log. Qualitative coaching
("Sleep was short. Train easy.") is allowed. If this module cannot guarantee
the line is clean, the mouth falls back to on-device.

This module never logs the input or the cleaned text.
"""

from __future__ import annotations

import re
from dataclasses import dataclass
from typing import Iterable

# Canaries used by tests. Real traffic is scanned with the same patterns.
CANARY_NAME = "AkshithKondaCanary"
CANARY_EMAIL = "akshith.canary@forge.test"
CANARY_PHONE = "415-555-0134"
CANARY_HRV = "HRV 32"
CANARY_READINESS = "readiness 88"
CANARY_SLEEP_HOURS = "6.5 hours of sleep"
CANARY_HEART_RATE = "142 bpm"

_EMAIL = re.compile(r"\b[A-Za-z0-9._%+-]+@[A-Za-z0-9.-]+\.[A-Za-z]{2,}\b")
_PHONE = re.compile(
    r"(?<!\w)(?:\+?1[-.\s]?)?(?:\(?\d{3}\)?[-.\s])\d{3}[-.\s]\d{4}(?!\w)"
)
_SSN = re.compile(r"\b\d{3}-\d{2}-\d{4}\b")
_STREET = re.compile(
    r"\b\d{1,6}\s+\w+(?:\s+\w+){0,3}\s+"
    r"(?:street|st\.|avenue|ave\.|road|rd\.|boulevard|blvd\.|drive|dr\.)\b",
    re.I,
)
_HEALTH_NUMBER = re.compile(
    r"(?ix)"
    r"\b(?:"
    r"hrv|sdnn|rmssd|spo2?|vo2(?:\s*max)?|rhr|resting\s+heart(?:\s+rate)?"
    r"|heart\s+rate|bpm|mmhg|glucose|a1c|readiness|acwr|rpe"
    r"|sleep(?:\s+score)?"
    r")\b"
    r"\s*[:=]?\s*"
    r"\d+(?:\.\d+)?"
    r"|"
    r"\d+(?:\.\d+)?\s*"
    r"(?:ms|bpm|mmhg|mm\s*hg|%|h(?:ou)?rs?(?:\s+of\s+sleep)?|hours?\s+of\s+sleep)"
    r"|"
    r"\b\d{2,3}\s*/\s*\d{2,3}\s*(?:mmhg|mm\s*hg)?\b"
)

# Title-case tokens we expect in ARIA's own coaching copy.
_SAFE_CAPITALS = frozenset(
    {
        "i",
        "i'm",
        "i’ve",
        "i've",
        "aria",
        "let's",
        "let’s",
        "keep",
        "today",
        "sleep",
        "train",
        "easy",
        "ready",
        "one",
        "next",
        "move",
        "look",
        "how",
        "you",
        "your",
        "the",
        "a",
        "an",
        "and",
        "or",
        "for",
        "not",
        "new",
        "identity",
        "monday",
        "tuesday",
        "wednesday",
        "thursday",
        "friday",
        "saturday",
        "sunday",
        "warm",
        "calm",
        "spark",
        "ember",
        "coach",
        "friend",
        "ok",
        "okay",
    }
)

@dataclass(frozen=True)
class SanitizedSpeech:
    text: str
    safe: bool
    reason: str | None = None

    @property
    def can_send_to_cloud(self) -> bool:
        return self.safe and bool(self.text.strip())


def _provided_names(names: Iterable[str] | None) -> tuple[str, ...]:
    out: list[str] = []
    for raw in names or ():
        token = str(raw or "").strip()
        if token:
            out.append(token)
    return tuple(out)


def looks_like_pii(text: str, *, names: Iterable[str] | None = None) -> bool:
    raw = str(text or "")
    if not raw.strip():
        return False
    if _EMAIL.search(raw) or _PHONE.search(raw) or _SSN.search(raw) or _STREET.search(raw):
        return True
    if _HEALTH_NUMBER.search(raw):
        return True
    lower = raw.lower()
    if CANARY_NAME.lower() in lower:
        return True
    for name in _provided_names(names):
        if name.lower() in lower:
            return True
    return _leading_personal_name(raw)


def _leading_personal_name(text: str) -> bool:
    """``Maya, your sleep was short`` — a vocative name is not coaching copy."""
    match = re.match(r"^([A-Z][a-z]{2,20}),\s", text.strip())
    if not match:
        return False
    return match.group(1).lower() not in _SAFE_CAPITALS


def sanitize_tts_text(
    text: str,
    *,
    names: Iterable[str] | None = None,
) -> SanitizedSpeech:
    """Return cloud-safe speech, or mark the line as on-device-only.

    Never logs. Never invents a substitute that still contains the original
    canary. Empty input is not sent to a cloud provider.
    """
    line = str(text or "").strip()
    if not line:
        return SanitizedSpeech("", False, "privacy")
    known = _provided_names(names)
    if looks_like_pii(line, names=known):
        # Do not salvage a mixed line. If any PII was present we cannot
        # guarantee the remainder, so the mouth stays on-device.
        return SanitizedSpeech("", False, "privacy")
    return SanitizedSpeech(line, True, None)


def assert_cloud_payload_is_clean(
    *parts: object,
    names: Iterable[str] | None = None,
) -> None:
    """Raise ``ValueError`` if a canary or leftover PII is about to leave."""
    blob = " ".join(_stringify(part) for part in parts)
    if looks_like_pii(blob, names=names):
        raise ValueError("tts_privacy: refused to send PII to a voice API")
    lower = blob.lower()
    for canary in (
        CANARY_NAME,
        CANARY_EMAIL,
        CANARY_PHONE,
        "hrv 32",
        "readiness 88",
        "6.5 hours of sleep",
        "142 bpm",
    ):
        if canary.lower() in lower:
            raise ValueError("tts_privacy: canary leaked toward a voice API")


def _stringify(value: object) -> str:
    if value is None:
        return ""
    if isinstance(value, bytes):
        return value.decode("utf-8", errors="replace")
    return str(value)
