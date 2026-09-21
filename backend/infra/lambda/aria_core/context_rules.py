"""ContextEngine decision rules as pure functions.

Python port of ForgeCore's ``ContextRules.swift``. Motion / location stay
on the client; this decides.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

HEART_RATE_FRESHNESS_SECONDS = 15 * 60

DESK_CODING = "deskCoding"
DEEP_FOCUS = "deepFocus"
WIND_DOWN = "windDown"


@dataclass(frozen=True)
class HeartRateReading:
    bpm: float
    taken_at: datetime


def desk_block_nudge_due(
    mode: str | None,
    minutes_in_mode: float | None,
    already_fired_this_block: bool,
) -> bool:
    if mode not in (DESK_CODING, DEEP_FOCUS):
        return False
    if minutes_in_mode is None or minutes_in_mode < 90:
        return False
    if already_fired_this_block:
        return False
    return True


def evening_wind_down_due(
    now: datetime,
    predicted_wind_down: datetime | None,
    current_mode: str | None,
    pending_suggestion: str | None,
) -> bool:
    if current_mode == WIND_DOWN or pending_suggestion == WIND_DOWN:
        return False
    if predicted_wind_down is not None:
        return now >= predicted_wind_down
    return now.hour >= 21


def desk_mode_likely(
    stationary_share: float,
    hour: int,
    current_mode: str | None,
    pending_suggestion: str | None,
) -> bool:
    return (
        current_mode is None
        and pending_suggestion is None
        and stationary_share > 0.8
        and 9 <= hour < 19
    )


def gym_suggestion_allowed(recent_heart_rate: float | None) -> bool:
    if recent_heart_rate is None:
        return False
    return recent_heart_rate >= 100


def usable_heart_rate(
    reading: HeartRateReading | None,
    now: datetime,
    freshness: float = HEART_RATE_FRESHNESS_SECONDS,
) -> float | None:
    if reading is None:
        return None
    if abs((now - reading.taken_at).total_seconds()) > freshness:
        return None
    return reading.bpm
