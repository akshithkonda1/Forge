from __future__ import annotations

from typing import Any


def training_load_trend(workouts: list[dict[str, Any]]) -> dict[str, Any]:
    """Compute current vs prior 7-day training load (sum of duration * intensity weight)."""
    if not workouts:
        return {"current": 0, "previous": 0, "delta": 0, "trend": "flat"}

    intensity_weight = {"low": 1.0, "moderate": 1.5, "high": 2.0, "max": 2.5}

    def load_for(window: list[dict[str, Any]]) -> int:
        total = 0.0
        for w in window:
            duration = float(w.get("duration", 0) or 0)
            weight = intensity_weight.get(str(w.get("intensity", "moderate")), 1.5)
            total += duration * weight
        return round(total)

    current = load_for(workouts[:7])
    previous = load_for(workouts[7:14])
    delta = current - previous

    if previous == 0:
        trend = "rising" if current > 0 else "flat"
    elif delta > previous * 0.1:
        trend = "rising"
    elif delta < -previous * 0.1:
        trend = "falling"
    else:
        trend = "steady"

    return {"current": current, "previous": previous, "delta": delta, "trend": trend}


def recovery_trend(sleep_records: list[dict[str, Any]]) -> dict[str, Any]:
    """Compare last 7 vs prior 7 nights of sleep score."""
    if not sleep_records:
        return {"current": 0, "previous": 0, "delta": 0}

    def avg(window: list[dict[str, Any]]) -> int:
        if not window:
            return 0
        return round(sum(float(r.get("score", 0) or 0) for r in window) / len(window))

    current = avg(sleep_records[:7])
    previous = avg(sleep_records[7:14])
    return {"current": current, "previous": previous, "delta": current - previous}


def detect_personal_records(workouts: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Return one PR entry per exercise based on max weight across logs that include exercises."""
    best: dict[str, dict[str, Any]] = {}
    for w in workouts:
        exercises = w.get("exercises") or []
        date = w.get("date") or w.get("startedAt") or ""
        for ex in exercises:
            if not isinstance(ex, dict):
                continue
            name = ex.get("name")
            weight = ex.get("weight")
            if not name or not isinstance(weight, (int, float)):
                continue
            current = best.get(name)
            if current is None or weight > current["value"]:
                best[name] = {
                    "exercise": name,
                    "value": float(weight),
                    "unit": "lbs",
                    "date": date,
                }
    return sorted(best.values(), key=lambda r: r["value"], reverse=True)


def baseline_workout_recommendation(
    readiness_overall: int | None,
    last_workout_type: str | None,
) -> dict[str, Any]:
    """Pick a workout focus given readiness and the most recent workout type.

    Unknown readiness is treated as the conservative band rather than assumed
    average: prescribing high intensity to someone whose recovery state has never
    been measured is the one error here with a physical cost.
    """
    if readiness_overall is None:
        return {
            "focus": "technique",
            "intensity": "low",
            "suggestedType": "strength",
            "readinessKnown": False,
        }

    if readiness_overall >= 80:
        focus = "power"
        intensity = "high"
    elif readiness_overall >= 65:
        focus = "hypertrophy"
        intensity = "moderate"
    elif readiness_overall >= 50:
        focus = "technique"
        intensity = "low"
    else:
        focus = "recovery"
        intensity = "low"

    rotate = {
        "strength": "cardio",
        "cardio": "strength",
        "hiit": "mobility",
        "mobility": "strength",
        "yoga": "strength",
    }
    suggested_type = rotate.get(str(last_workout_type or "").lower(), "strength")

    return {
        "focus": focus,
        "intensity": intensity,
        "suggestedType": suggested_type,
    }
