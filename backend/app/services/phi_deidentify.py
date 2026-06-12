"""Strip direct identifiers before sending conclusions to the LLM pipeline."""
from __future__ import annotations

from typing import Any


_REDACT_KEYS = frozenset({
    "name",
    "email",
    "phone",
    "address",
    "terraUserId",
    "referenceId",
})


def _scrub(obj: Any) -> Any:
    if isinstance(obj, dict):
        cleaned: dict[str, Any] = {}
        for key, value in obj.items():
            if key in _REDACT_KEYS:
                continue
            cleaned[key] = _scrub(value)
        return cleaned
    if isinstance(obj, list):
        return [_scrub(item) for item in obj]
    return obj


def deidentify_conclusions(conclusions: dict[str, Any]) -> dict[str, Any]:
    """Return a PHI-safe coaching package for cloud inference."""
    scrubbed = _scrub(conclusions)
    return {
        "coachingBrief": scrubbed.get("coachingBrief"),
        "coveragePct": scrubbed.get("coveragePct"),
        "readiness": scrubbed.get("readiness"),
        "signals": scrubbed.get("signals"),
        "compoundFlags": scrubbed.get("compoundFlags"),
        "dashboardHints": scrubbed.get("dashboardHints"),
        "snapshot": {
            "today": (scrubbed.get("snapshot") or {}).get("today"),
            "trainingLoad": (scrubbed.get("snapshot") or {}).get("trainingLoad"),
            "recoveryTrend": (scrubbed.get("snapshot") or {}).get("recoveryTrend"),
        },
    }