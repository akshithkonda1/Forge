"""Health-condition and PII handling for prompts and logs.

Health conditions stay on-device unless the user opted in (``shareHealth``
plus an item-level ``shareOptIn``, or an explicit ``clinical_data`` grant).
Raw health payloads must never land in logs. Memory retrieval uses the same
filter so every model tier sees the same redacted context.
"""

from __future__ import annotations

import re
from typing import Any, Iterable, Mapping

from . import aria_context_memory as memory

_HEALTH_LOG_KEYS = (
    "hrv",
    "heart",
    "sleep",
    "glucose",
    "blood_pressure",
    "bloodpressure",
    "spo2",
    "oxygen",
    "temperature",
    "condition",
    "diagnos",
    "medication",
    "seizure",
    "epilep",
    "clinical",
)
_HEALTH_TOKEN = re.compile(
    r"(?i)\b("
    r"seizure|epilep\w*|diabetes|diabetic|asthma|cancer|depression|"
    r"anxiety disorder|medication|metformin|insulin|ssri|"
    r"hrv|sdnn|spo2|glucose|mmhg|bpm"
    r")\b"
)
_SECRET_TOKEN = re.compile(
    r"(?i)("
    r"(?:api[_-]?key|secret[_-]?key|password|aws_secret(?:_access_key)?)"
    r"\s*[:=]\s*\S+"
    r"|bearer\s+[A-Za-z0-9._\-]+"
    r")"
)


def share_flags(payload: Mapping[str, Any] | None) -> dict[str, bool]:
    raw = payload if isinstance(payload, Mapping) else {}
    share = raw.get("share") if isinstance(raw.get("share"), dict) else raw
    return {
        "shareDreams": bool(share.get("shareDreams") or share.get("share_dreams")),
        "shareHealth": bool(share.get("shareHealth") or share.get("share_health")),
    }


def clinical_opted_in(permissions: Any | None, share: Mapping[str, bool] | None = None) -> bool:
    """True only when clinical_data is explicitly granted or shareHealth is on."""
    flags = share or {"shareHealth": False}
    if flags.get("shareHealth"):
        return True
    allows = getattr(permissions, "allows", None)
    if callable(allows):
        return bool(allows("clinical_data"))
    granted = getattr(permissions, "granted", None)
    if isinstance(granted, dict):
        return bool(granted.get("clinical_data"))
    return False


def filter_memory_items(
    items: Iterable[dict[str, Any]] | None,
    *,
    share: Mapping[str, bool] | None = None,
) -> list[dict[str, Any]]:
    """Drop dreams/health unless both the global flag and item opt-in are on."""
    flags = dict(share or {"shareDreams": False, "shareHealth": False})
    kept: list[dict[str, Any]] = []
    for item in items or []:
        if not isinstance(item, dict):
            continue
        domain = str(item.get("domain") or memory.classify(str(item.get("text") or item.get("summary") or "")))
        opt = bool(item.get("shareOptIn") or item.get("share_opt_in"))
        if domain == "sleep_dreams" and not (flags.get("shareDreams") and opt):
            continue
        if domain == "health_constraints" and not (flags.get("shareHealth") and opt):
            continue
        kept.append(item)
    return kept


def memory_prompt_text(
    items: Iterable[dict[str, Any]] | None,
    *,
    share: Mapping[str, bool] | None = None,
) -> str:
    allowed = filter_memory_items(items, share=share)
    return " | ".join(
        str(row.get("summary") or row.get("text") or "")[:96] for row in allowed[:12]
    )


def strip_health_conditions(text: str) -> str:
    """Remove condition-like tokens from a memory/insight line when not opted in."""
    return _HEALTH_TOKEN.sub("[health withheld]", text or "")


def redact_for_log(value: Any) -> str:
    """Log-safe rendering: drop secrets and raw health tokens, never raise."""
    text = str(value or "")
    text = _SECRET_TOKEN.sub("[redacted-secret]", text)
    text = _HEALTH_TOKEN.sub("[redacted-health]", text)
    if any(key in text.lower() for key in _HEALTH_LOG_KEYS) and len(text) > 240:
        return text[:120] + "…[redacted-health]…"
    if len(text) > 500:
        return text[:500] + "…"
    return text


def looks_like_raw_health(text: str) -> bool:
    return bool(_HEALTH_TOKEN.search(text or ""))
