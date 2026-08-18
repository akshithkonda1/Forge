"""Data generator — turn a 30-day stream into the ARIAContext ARIA receives.

``build_context`` can snapshot any day in the stream, so SimRunner can probe
ARIA at Day 7, 14, 21, 29 and catch failures that only emerge once a pattern
(rising load, accumulating debt, a regime change) has developed.
"""

from __future__ import annotations

from dataclasses import dataclass

from .behavior_engine import DailyRecord

_CHRONO_SLEEP_TARGET = {"bear": 8.0, "lion": 7.5, "wolf": 7.5, "dolphin": 6.5}
_CHRONO_WAKE_HOUR = {"bear": 7.0, "lion": 6.0, "wolf": 8.5, "dolphin": 6.5}


@dataclass
class ARIAContext:
    # User identity
    user_name: str
    chronotype: str
    experience_level: str
    coaching_style: str
    occupation: str
    life_season: str

    # Today's snapshot
    today: DailyRecord

    # Recent trend (last 7 days)
    hrv_7d_avg: float
    hrv_7d_trend: str            # "rising" | "falling" | "stable"
    sleep_debt_7d_hours: float
    readiness_7d_avg: float
    readiness_trend: str         # "rising" | "falling" | "stable"

    # Training load
    acwr: float
    training_streak: int
    days_since_last_workout: int

    # Chronotype targets
    target_sleep_hours: float
    target_wake_hour: float

    # Flags
    is_overtrained: bool
    is_sleep_deprived: bool
    has_notable_event: bool
    notable_event_note: str | None

    # Raw history (last 14 days)
    history: list[DailyRecord]


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _trend(values: list[float], threshold: float) -> str:
    """Compare the early half of the window to the late half."""
    if len(values) < 4:
        return "stable"
    half = len(values) // 2
    delta = _mean(values[half:]) - _mean(values[:half])
    if delta > threshold:
        return "rising"
    if delta < -threshold:
        return "falling"
    return "stable"


def build_context(stream: list[DailyRecord], profile: dict, day_index: int = 29) -> ARIAContext:
    if not stream:
        raise ValueError("stream is empty")
    day_index = max(0, min(day_index, len(stream) - 1))
    today = stream[day_index]

    window7 = stream[max(0, day_index - 6): day_index + 1]
    chrono = profile.get("chronotype", "bear")
    target_sleep = _CHRONO_SLEEP_TARGET.get(chrono, 8.0)

    hrv_7d = [r.hrv for r in window7]
    readiness_7d = [r.readiness_score for r in window7]
    sleep_debt = sum(max(0.0, target_sleep - r.total_sleep_hours) for r in window7)

    # Training streak + recency.
    streak = 0
    for record in reversed(stream[: day_index + 1]):
        if record.workout_logged:
            streak += 1
        else:
            break
    days_since = 0
    for record in reversed(stream[: day_index + 1]):
        if record.workout_logged:
            break
        days_since += 1

    return ARIAContext(
        user_name=str(profile.get("occupation", "user")).title().split("→")[0],
        chronotype=chrono,
        experience_level=profile.get("experience_level", "intermediate"),
        coaching_style=profile.get("coaching_style", "balanced"),
        occupation=profile.get("occupation", "unknown"),
        life_season=profile.get("season", "maintenance"),
        today=today,
        hrv_7d_avg=round(_mean(hrv_7d), 1),
        hrv_7d_trend=_trend(hrv_7d, threshold=2.0),
        sleep_debt_7d_hours=round(sleep_debt, 1),
        readiness_7d_avg=round(_mean(readiness_7d), 1),
        readiness_trend=_trend(readiness_7d, threshold=3.0),
        acwr=today.acwr,
        training_streak=streak,
        days_since_last_workout=days_since,
        target_sleep_hours=target_sleep,
        target_wake_hour=_CHRONO_WAKE_HOUR.get(chrono, 7.0),
        is_overtrained=today.acwr > 1.4,
        is_sleep_deprived=sleep_debt > 4.0,
        has_notable_event=today.notes is not None,
        notable_event_note=today.notes,
        history=stream[max(0, day_index - 13): day_index + 1],
    )
