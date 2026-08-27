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

    # hoursSinceLastWorkout/readinessOverall/readinessConfidence all feed
    # numeric comparisons inside watch_debrief (<=, <), which raise TypeError
    # on a non-numeric value exactly the way minutes/heartRateSettleBPM would
    # have without _optional_float — sanitize them here for the same reason.
    # watch_debrief already treats a missing/None value as "not enough
    # signal" rather than crashing, so coercing to None here is sufficient.
    safe_context = dict(context)
    for field in ("hoursSinceLastWorkout", "readinessOverall", "readinessConfidence"):
        if field in safe_context:
            safe_context[field] = _optional_float(safe_context[field])

    minutes = _optional_float(body.get("minutes")) or 0.0
    heart_rate_settle_bpm = _optional_float(body.get("heartRateSettleBPM"))

    return ok(watch_debrief.generate_debrief(safe_context, practice, minutes, heart_rate_settle_bpm))
