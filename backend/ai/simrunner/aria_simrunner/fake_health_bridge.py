"""Map FakeHealthPack days onto the dummy reasoner's context shape.

The Swift pack writes a 30-day life into HealthKit on the simulator.
SimRunner still has its own stream. This bridge lets the dummy reasoner
read the same fields the pack already produces so the letter cites one
body, not two.
"""

from __future__ import annotations

from types import SimpleNamespace
from typing import Any


def _hours_from_minutes(minutes: Any) -> float | None:
    if minutes is None:
        return None
    try:
        return round(float(minutes) / 60.0, 2)
    except (TypeError, ValueError):
        return None


def context_from_pack_day(day: Any, *, persona: str | None = None) -> SimpleNamespace:
    """Accept a FakeHealthDay, a dict, or anything with the pack field names."""
    get = day.get if isinstance(day, dict) else lambda k, default=None: getattr(day, k, default)

    night = get("night") or {}
    if not isinstance(night, dict):
        night = {
            "totalMinutes": getattr(night, "totalMinutes", None),
            "deepMinutes": getattr(night, "deepMinutes", None),
            "remMinutes": getattr(night, "remMinutes", None),
        }

    sleep_h = _hours_from_minutes(night.get("totalMinutes"))
    if sleep_h is None:
        sleep_h = _hours_from_minutes(get("sleepMinutes"))

    workout = get("workout")
    last_type = None
    logged = False
    if workout:
        logged = True
        last_type = (
            workout.get("type") if isinstance(workout, dict)
            else getattr(workout, "type", None)
        )
        if last_type is not None:
            last_type = str(last_type).replace("ForgeWorkoutType.", "").lower()

    social = get("social") or []
    notable = ""
    if social:
        first = social[0]
        if isinstance(first, dict):
            notable = str(first.get("title") or first.get("kind") or "")
        else:
            notable = str(getattr(first, "title", None) or getattr(first, "kind", "") or "")

    today = SimpleNamespace(
        total_sleep_hours=sleep_h,
        readiness_score=float(get("sleepScore") or get("readiness") or 50),
        hrv=float(get("hrvMs")) if get("hrvMs") is not None else None,
        resting_hr=float(get("restingHR")) if get("restingHR") is not None else None,
        deep_sleep_minutes=float(night.get("deepMinutes") or 0) or None,
        rem_sleep_minutes=float(night.get("remMinutes") or 0) or None,
        workout_logged=logged,
        workout_type=last_type,
        acwr=float(get("acwr") or 1.0),
    )

    felt = str(get("felt") or "")
    story = str(get("storyLine") or "")
    occupation = (persona or get("personaLabel") or "").lower()
    if occupation in ("athlete", "highenergy", "high energy"):
        occupation = "triathlete"
    elif occupation in ("stressed",):
        occupation = "teacher"
    elif occupation in ("nightowl", "night owl"):
        occupation = "engineer"

    return SimpleNamespace(
        today=today,
        sleep_debt_7d_hours=float(get("sleepDebtHours") or 0.0),
        readiness_trend=str(get("readinessTrend") or "stable"),
        readiness_7d_avg=_opt(get("readiness7dAvg")),
        hrv_7d_trend=str(get("hrvTrend") or "stable"),
        hrv_7d_avg=_opt(get("hrv7dAvg")),
        target_sleep_hours=8.0,
        is_overtrained=bool(get("isOvertrained") or False),
        training_streak=int(get("trainingStreak") or (1 if logged else 0)),
        days_since_last_workout=0 if logged else int(get("daysSinceLastWorkout") or 2),
        has_sleep=sleep_h is not None,
        has_hrv=today.hrv is not None,
        is_data_sparse=sleep_h is None and today.hrv is None,
        occupation=occupation,
        chronotype="wolf" if occupation == "engineer" else "bear",
        life_season="build",
        experience_level="intermediate",
        last_workout_type=last_type,
        has_notable_event=bool(notable),
        notable_event_note=notable or story,
        felt=felt,
        story_line=story,
        acwr=today.acwr,
    )


def _opt(value):
    if value is None:
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None
