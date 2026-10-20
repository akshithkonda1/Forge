"""Health conditions stay on-device unless the user opted in.

Wearable metrics (sleep, HRV, steps) are coaching signals. Clinical
conditions, medications, and diagnoses are not — they reach a prompt only
when ``shareHealth`` is true *and* the item itself is opted in. Raw health
text must never be logged.

Stdlib-only. Wraps ``aria_context_memory.server_context`` so /ai/chat,
memory inject, and fusion share one gate.
"""

from __future__ import annotations

import re
from typing import Any

from . import aria_context_memory as acm

_HEALTH_LOG_RE = re.compile(
    r"(?i)\b(?:seizure|epilep\w*|diagnos\w*|medication|prescription|"
    r"condition|allergy|allergies|insulin|cholesterol|asthma|diabet\w*)\b"
)


def share_flags(payload: dict[str, Any] | None) -> dict[str, bool]:
    """Read opt-in flags. Missing keys are False — fail closed."""
    raw = payload if isinstance(payload, dict) else {}
    nested = raw.get("share") if isinstance(raw.get("share"), dict) else {}
    memory = raw.get("memoryShare") if isinstance(raw.get("memoryShare"), dict) else {}
    permissions = raw.get("permissions") if isinstance(raw.get("permissions"), dict) else {}
    return {
        "shareHealth": _flag(
            raw.get("shareHealth"),
            nested.get("shareHealth"),
            memory.get("shareHealth"),
            permissions.get("shareHealth"),
        ),
        "shareDreams": _flag(
            raw.get("shareDreams"),
            nested.get("shareDreams"),
            memory.get("shareDreams"),
            permissions.get("shareDreams"),
        ),
    }


def health_opted_in(payload: dict[str, Any] | None) -> bool:
    return bool(share_flags(payload)["shareHealth"])


def filter_memory_items(
    items: list[dict[str, Any]] | None,
    payload: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Drop health/dream items the user has not opted to share with the server."""
    share = share_flags(payload)
    kept: list[dict[str, Any]] = []
    for item in items or []:
        if not isinstance(item, dict):
            continue
        domain = str(item.get("domain") or "") or acm.classify(
            str(item.get("text") or item.get("summary") or "")
        )
        row = dict(item)
        row["domain"] = domain
        opt = bool(row.get("shareOptIn"))
        if domain == "health_constraints" and not (share["shareHealth"] and opt):
            continue
        if domain == "sleep_dreams" and not (share["shareDreams"] and opt):
            continue
        kept.append(row)
    return kept


def server_context(
    items: list[dict[str, Any]] | None,
    payload: dict[str, Any] | None = None,
) -> dict[str, str]:
    """Prompt-safe memory summaries. Empty when nothing is shareable."""
    return acm.server_context(filter_memory_items(items, payload), share_flags(payload))


def filter_memory_text(text: str, payload: dict[str, Any] | None = None) -> str:
    """Drop health-classified lines from a rendered memory block unless opted in."""
    if health_opted_in(payload):
        return str(text or "")
    kept: list[str] = []
    for raw in str(text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        domain = acm.classify(line)
        if domain in acm.SENSITIVE:
            continue
        if _HEALTH_LOG_RE.search(line):
            continue
        kept.append(raw)
    return "\n".join(kept)


def redact_clinical_context(ctx: Any, payload: dict[str, Any] | None) -> Any:
    """Zero clinical lists on an ARIAContext unless shareHealth is on.

    Wearable domains are untouched. The original object is copied only when
    redaction is needed so callers can still compare.
    """
    if health_opted_in(payload):
        return ctx
    clinical = getattr(ctx, "clinical_data", None)
    if clinical is None:
        return ctx
    empty = not any(
        getattr(clinical, field, None)
        for field in (
            "allergies",
            "medications",
            "conditions",
            "immunizations",
            "lab_results",
            "procedures",
        )
    )
    if empty and not getattr(getattr(ctx, "medication_layer", None), "on_file", None):
        return ctx
    from . import aria_engine

    sanitized, _restricted = aria_engine.apply_permissions(
        ctx,
        aria_engine.DataPermissions.from_payload({"clinical_data": False}),
    )
    return sanitized


def redact_for_log(text: str) -> str:
    """Replace raw health tokens before a line reaches CloudWatch."""
    raw = str(text or "")
    if not raw:
        return raw
    return _HEALTH_LOG_RE.sub("[health-redacted]", raw)


def contains_raw_health(text: str) -> bool:
    return bool(_HEALTH_LOG_RE.search(text or ""))


def _flag(*values: Any) -> bool:
    for value in values:
        if isinstance(value, bool):
            return value
        if isinstance(value, str) and value.strip().lower() in {"1", "true", "yes", "on"}:
            return True
    return False
