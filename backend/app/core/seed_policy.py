from __future__ import annotations

from typing import Any, Callable, TypeVar

from core.runtime import allow_seed_fallback

T = TypeVar("T")


def resolve(persisted: T | None, seed: Callable[[], T], empty: Callable[[], T]) -> T:
    """Return persisted data, demo seed (dev only), or an empty production shape."""
    if persisted is not None:
        return persisted
    if allow_seed_fallback():
        return seed()
    return empty()


def empty_profile() -> dict[str, Any]:
    return {
        "name": "",
        "fitnessGoals": [],
        "experienceLevel": "",
        "preferredWorkouts": [],
        "coachingStyle": "",
        "connectedDevices": [],
        "weeklySchedule": [],
    }


def empty_readiness() -> dict[str, Any]:
    return {
        "overall": 0,
        "sleepQuality": 0,
        "recoveryScore": 0,
        "stressLevel": 0,
        "energyBank": 0,
        "generatedAt": None,
    }


def empty_daily_metrics() -> dict[str, Any]:
    from data.seed_data import today_iso

    return {
        "date": today_iso(),
        "steps": 0,
        "activeCalories": 0,
        "hrv": 0,
        "restingHR": 0,
        "deepSleep": 0,
        "totalSleep": 0,
        "sources": [],
    }


def empty_workout_plan() -> dict[str, Any]:
    return {
        "id": "",
        "name": "",
        "type": "",
        "duration": 0,
        "intensity": "",
        "exercises": [],
        "status": "unplanned",
    }