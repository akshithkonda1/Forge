"""Zero-leakage helpers for the Dummy / local ARIA path.

Learned personality and Memory stay in-process. User names, personal
identifiers, and raw health values must not appear in Dummy log lines,
analytics events, or anything Dummy would send off-box. Live ``/ai/chat``
with Bedrock on is a different path — see the PR note.
"""

from __future__ import annotations

import re
from typing import Any, Iterable

REDACTED = "[redacted]"

_NAME_KEYS = (
    "user_name", "userName", "name", "display_name", "displayName",
    "full_name", "fullName", "given_name", "first_name",
)
_HEALTH_KEYS = (
    "hrv", "hrv_ms", "hrvMs", "readiness_score", "readinessScore",
    "recovery_score", "recoveryScore", "total_sleep_hours", "totalSleepHours",
    "duration_minutes", "durationMinutes", "resting_hr", "restingHR",
    "resting_heart_rate", "sleep_debt_7d_hours", "sleepDebt7dHours",
    "acwr", "spo2", "vo2", "vo2_max", "steps", "active_calories",
)
_METRIC_WORD = re.compile(
    r"(?i)\b(?:hrv|readiness|sleep|bpm|ms|mmhg|spo2|vo2|acwr)\b"
)


def _add(needles: list[str], value: Any) -> None:
    if value is None or isinstance(value, bool):
        return
    if isinstance(value, (int, float)):
        token = f"{value:g}"
        # Skip tiny counts that appear in ordinary speech ("1 session").
        if token and token not in {"0", "1", "2", "3", "4", "5", "6", "7"}:
            needles.append(token)
        return
    text = str(value).strip()
    if text and text not in {REDACTED, ""}:
        needles.append(text)
        for part in re.split(r"\s+", text):
            if len(part) >= 3:
                needles.append(part)


def needles_from_context(ctx: Any = None, payload: dict | None = None) -> list[str]:
    """Names and health values Dummy is allowed to know — never to emit."""
    found: list[str] = []
    if ctx is not None:
        _add(found, getattr(ctx, "user_name", None))
        today = getattr(ctx, "today", None)
        if today is not None:
            for key in _HEALTH_KEYS:
                _add(found, getattr(today, key, None))
        for key in _HEALTH_KEYS:
            _add(found, getattr(ctx, key, None))
    bag = payload if isinstance(payload, dict) else {}
    for key in _NAME_KEYS:
        _add(found, bag.get(key))
    context = bag.get("context") if isinstance(bag.get("context"), dict) else {}
    profile = context.get("profile") if isinstance(context.get("profile"), dict) else {}
    for key in _NAME_KEYS:
        _add(found, context.get(key))
        _add(found, profile.get(key))
    for section in context.values():
        if not isinstance(section, dict):
            continue
        for key, value in section.items():
            if key in _NAME_KEYS or key in _HEALTH_KEYS or _METRIC_WORD.search(str(key)):
                _add(found, value)
    # Longest first so "13.37" wins over "13".
    uniq: list[str] = []
    seen: set[str] = set()
    for item in sorted((n for n in found if n), key=len, reverse=True):
        if item not in seen and item.lower() not in {"train", "sleep", "today"}:
            seen.add(item)
            uniq.append(item)
    return uniq


def redact_text(text: str, needles: Iterable[str]) -> str:
    cleaned = str(text or "")
    for needle in needles:
        if needle and needle in cleaned:
            cleaned = cleaned.replace(needle, REDACTED)
    return cleaned


def redact_obj(value: Any, needles: Iterable[str]) -> Any:
    names = list(needles)
    if isinstance(value, str):
        return redact_text(value, names)
    if isinstance(value, list):
        return [redact_obj(item, names) for item in value]
    if isinstance(value, dict):
        return {str(k): redact_obj(v, names) for k, v in value.items()}
    return value


def leak_hits(blob: str, needles: Iterable[str]) -> list[str]:
    text = str(blob or "")
    return [n for n in needles if n and n in text]


def emit_analytics(_event: str, _payload: dict | None = None) -> None:
    """Dummy never sends analytics. Tests patch this to prove no outbound."""
    return None
