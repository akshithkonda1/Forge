from __future__ import annotations

from typing import Any

from responses import RouteError, ok
from services import watch_debrief


def _optional_float(value: Any) -> float | None:
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def handle_post_watch_aria_suggest(body: dict[str, Any], user_id: str) -> dict:
    """Deeper-coaching debrief for the Watch app's ARIAWatchService.

    ``user_id`` is accepted (and will back future personalization/logging)
    but the v1 debrief is fully deterministic and does not branch on it.
    """
    practice = str(body.get("practice") or "").strip()
    context = body.get("context")
    if not practice or not isinstance(context, dict):
        raise RouteError(400, "practice and context are required.")

    minutes = _optional_float(body.get("minutes")) or 0.0
    heart_rate_settle_bpm = _optional_float(body.get("heartRateSettleBPM"))

    return ok(watch_debrief.generate_debrief(context, practice, minutes, heart_rate_settle_bpm))
