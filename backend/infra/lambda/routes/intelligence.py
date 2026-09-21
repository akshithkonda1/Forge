"""Native-client intelligence routes.

iOS (SwiftUI / Swift Charts) and Android (Compose / Kotlin charts) each render
their own UI. These endpoints return the Python facts both decode so neither
frontend reimplements readiness, habits, sleep story, or in-workout cues.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from aria_core import hr_zones
from aria_core import shared_intelligence
from aria_core import workout_coaching
from responses import RouteError, ok
from security import enforce_user_rate_limit


def _optional_float(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _optional_int(value: Any) -> int | None:
    number = _optional_float(value)
    return int(number) if number is not None else None


def _parse_datetime(value: Any) -> datetime | None:
    if isinstance(value, datetime):
        return value if value.tzinfo is not None else value.replace(tzinfo=timezone.utc)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return datetime.fromtimestamp(float(value), tz=timezone.utc)
    if isinstance(value, str) and value.strip():
        try:
            return datetime.fromisoformat(value.strip().replace("Z", "+00:00"))
        except ValueError:
            return None
    return None


def handle_post_intelligence_today(body: dict[str, Any], user_id: str) -> dict:
    """Shared Home / Watch / Lifestyle sidecar. Body is the client's vitals bag."""
    try:
        enforce_user_rate_limit(user_id, action="intelligence-today", limit=120, window_hours=1)
    except PermissionError as exc:
        raise RouteError(429, str(exc) or "Too many requests.") from exc
    return ok(shared_intelligence.from_payload(body if isinstance(body, dict) else {}))


def handle_post_intelligence_workout_cue(body: dict[str, Any], user_id: str) -> dict:
    """Live zone-boundary cue. Native Watch/phone render; Python decides."""
    try:
        enforce_user_rate_limit(user_id, action="intelligence-workout-cue", limit=600, window_hours=1)
    except PermissionError as exc:
        raise RouteError(429, str(exc) or "Too many requests.") from exc

    raw = body if isinstance(body, dict) else {}
    bpm = _optional_int(raw.get("bpm") if raw.get("bpm") is not None else raw.get("heartRate"))
    if bpm is None:
        raise RouteError(400, "bpm is required.")

    target = _optional_int(raw.get("targetZone") if raw.get("targetZone") is not None else raw.get("target"))
    if target is None:
        target = 2
    previous = _optional_int(raw.get("previousZone"))
    now = _parse_datetime(raw.get("now")) or datetime.now(timezone.utc)
    last_cue = _parse_datetime(raw.get("lastCueAt")) or datetime.fromtimestamp(0, tz=timezone.utc)
    allows = raw.get("allowsBuildingUp")
    if allows is None:
        allows = True

    zone = hr_zones.zone_for_bpm(bpm)
    decision = workout_coaching.cue(
        zone,
        previous,
        target,
        last_cue,
        now,
        allows_building_up=bool(allows),
    )
    return ok({
        "zone": zone.zone,
        "label": zone.label,
        "coachingLine": zone.coaching_line,
        "cue": None if decision is None else decision.cue,
        "firedAt": None if decision is None else decision.fired_at.isoformat(),
        "throttled": decision is None and previous != zone.zone,
    })
