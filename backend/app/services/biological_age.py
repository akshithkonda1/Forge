"""Consumer biological age estimate from wellness markers (not clinical)."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from services.data_fusion import load_wellness_snapshot
from storage import dynamodb, keys


def _profile_age(profile: dict[str, Any] | None) -> int:
    if not profile:
        return 30
    age = profile.get("age") or profile.get("biologicalAgeBaseline")
    try:
        return max(18, min(80, int(age)))
    except (TypeError, ValueError):
        return 30


def compute_biological_age(
    user_id: str,
    *,
    profile: dict[str, Any] | None = None,
    date: str | None = None,
) -> dict[str, Any]:
    """Estimate biological age from VO2, HRV, sleep, activity vs chronological age."""
    snapshot = load_wellness_snapshot(user_id, date=date)
    today = snapshot.get("today") or {}
    readiness = snapshot.get("readiness") or {}
    chronological = _profile_age(profile)

    hrv = float(today.get("hrv") or 0)
    resting_hr = float(today.get("restingHR") or 0)
    sleep_score = float(today.get("sleepScore") or readiness.get("sleepQuality") or 0)
    steps = float(today.get("steps") or 0)
    recovery = float(readiness.get("recoveryScore") or readiness.get("overall") or 0)

    adjustment = 0.0
    if hrv >= 50:
        adjustment -= 2.5
    elif hrv < 35 and hrv > 0:
        adjustment += 3.0
    if resting_hr > 0:
        if resting_hr <= 58:
            adjustment -= 1.5
        elif resting_hr >= 72:
            adjustment += 2.0
    if sleep_score >= 80:
        adjustment -= 2.0
    elif sleep_score < 60 and sleep_score > 0:
        adjustment += 2.5
    if steps >= 8000:
        adjustment -= 1.0
    elif steps < 4000 and steps > 0:
        adjustment += 1.0
    if recovery >= 75:
        adjustment -= 1.5
    elif recovery < 50 and recovery > 0:
        adjustment += 2.0

    biological = round(max(18, min(85, chronological + adjustment)), 1)
    delta = round(biological - chronological, 1)

    drivers: list[str] = []
    if hrv >= 50:
        drivers.append("strong_hrv")
    if sleep_score >= 80:
        drivers.append("quality_sleep")
    if steps >= 8000:
        drivers.append("active_lifestyle")
    if delta > 1:
        drivers.append("recovery_lag")
    if delta < -1:
        drivers.append("youthful_markers")

    return {
        "chronologicalAge": chronological,
        "biologicalAge": biological,
        "deltaYears": delta,
        "drivers": drivers,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }


def get_or_compute_biological_age(
    user_id: str,
    *,
    profile: dict[str, Any] | None = None,
    date: str | None = None,
) -> dict[str, Any]:
    result = compute_biological_age(user_id, profile=profile, date=date)
    item = {
        **keys.biological_age_key(user_id, result.get("generatedAt", "")[:10]),
        **result,
    }
    dynamodb.put_item(item)
    return result