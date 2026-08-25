"""Honest empty responses for a user who has not logged anything yet.

``seed_data`` exists to make demo builds look alive. These are its production
counterparts: the same keys, in the same shapes, carrying no invented facts.
Keeping the keys present matters as much as dropping the values -- a client
decoding a fixed schema must not start failing just because the account is new.

The distinction a caller has to keep straight is that absent data is ``None``
here, not zero. Nobody's resting heart rate is 0 bpm, and a UI that renders a
missing HRV as "0 ms" is telling the user something false in a different way.
"""

from __future__ import annotations

from typing import Any

from seed_data import today_iso


def empty_profile() -> dict[str, Any]:
    """A profile shell for an account that has never completed onboarding."""
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
    """Readiness with nothing to compute it from.

    ``available`` is additive: existing clients read the scalar fields and get
    null, and a client that knows about the flag can tell "not yet measured"
    apart from "measured and low".
    """
    return {
        "overall": None,
        "sleepQuality": None,
        "recoveryScore": None,
        "stressLevel": None,
        "energyBank": None,
        "generatedAt": None,
        "available": False,
    }


def empty_daily_metrics(day: str | None = None) -> dict[str, Any]:
    """Today's metric row before any sample has been ingested."""
    return {
        "date": day or today_iso(),
        "steps": None,
        "activeCalories": None,
        "hrv": None,
        "restingHR": None,
        "deepSleep": None,
        "totalSleep": None,
        "sources": [],
    }
