"""Adaptive smart-wake window and early-fire decision.

Python port of the *pure* pieces of ForgeCore's ``SleepWakeAdaptation.swift``.
UserDefaults stores (``WakeStruggleStore``, ``SmartWakeEarlyFireStore``) stay
on the phone; callers pass the rolling snooze average in.

Stdlib only. Deterministic. Pure -- no I/O.
"""

from __future__ import annotations

from datetime import datetime

LION = "lion"
BEAR = "bear"
WOLF = "wolf"
DOLPHIN = "dolphin"

IGNORE = "ignore"
FIRE_EARLY = "fireEarly"
ALREADY_PAST_HARD = "alreadyPastHard"

MAX_SAMPLE_AGE_SECONDS = 20 * 60
STRUGGLER_THRESHOLD = 1.5
WINDOW_DAYS = 14


def smart_alarm_minutes(
    base: int,
    recent_score: int | None,
    debt_hours: float,
    bias: str,
    struggle_average_snoozes: float = 0.0,
) -> int:
    window = base
    if recent_score is not None:
        if recent_score < 70:
            window = min(45, window + 15)
        elif recent_score >= 85:
            window = max(15, window - 10)
    if debt_hours > 3:
        window = min(45, window + 5)
    if bias in (DOLPHIN, WOLF):
        window = min(45, window + 5)
    elif bias == LION:
        window = max(15, window - 5)
    if struggle_average_snoozes >= 1.5:
        window = min(45, window + 10)
    return max(15, min(45, window))


def average_snoozes(counts: list[int]) -> float:
    if not counts:
        return 0.0
    return sum(max(0, n) for n in counts) / len(counts)


def is_repeat_struggler(counts: list[int]) -> bool:
    return average_snoozes(counts) >= STRUGGLER_THRESHOLD


def decide_early_fire(
    now: datetime,
    smart_fire: datetime | None,
    hard_fire: datetime | None,
    sample_end: datetime,
    stage: str,
) -> str:
    if smart_fire is None or hard_fire is None:
        return IGNORE
    if now >= hard_fire:
        return ALREADY_PAST_HARD
    if now < smart_fire:
        return IGNORE
    age = (now - sample_end).total_seconds()
    if age < -60 or age > MAX_SAMPLE_AGE_SECONDS:
        return IGNORE
    if stage in ("core", "awake"):
        return FIRE_EARLY
    return IGNORE


def record_snooze_day(
    existing: list[tuple[str, int]],
    *,
    day_key: str,
    snoozes: int,
    window_days: int = WINDOW_DAYS,
) -> list[tuple[str, int]]:
    days = [(k, n) for k, n in existing if k != day_key]
    days.append((day_key, max(0, snoozes)))
    days.sort(key=lambda item: item[0])
    if len(days) > window_days:
        days = days[-window_days:]
    return days


def day_key(when: datetime) -> str:
    return f"{when.year:04d}-{when.month:02d}-{when.day:02d}"


def early_fire_token(alarm_id: str, day_key_value: str) -> str:
    return f"{alarm_id}|{day_key_value}"
