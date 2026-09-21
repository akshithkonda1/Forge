"""One phone wind-down fire time per evening.

Python port of ForgeCore's ``SleepWindDownNotice.swift``. Notification
identifiers stay on the client; this module only computes when to fire.
"""

from __future__ import annotations

from . import circadian_rhythm as cr
from .schedule_corrector import ScheduleGoal

PHONE_IDENTIFIER = "forge.notification.sleep.winddown"
RETIRED_PHONE_IDENTIFIERS = (
    "forge.notification.lifestyle.sleep",
    "sleep-wind-down",
)
FALLBACK_HOUR = 21
FALLBACK_MINUTE = 0
LEAD_MINUTES = 60


def _swift_round(value: float) -> int:
    return int(value + 0.5) if value >= 0 else -int(-value + 0.5)


def fire_hour_minute(bedtime_hour: float | None) -> tuple[int, int]:
    """Personal bedtime minus one hour, else 21:00."""
    if bedtime_hour is None:
        return FALLBACK_HOUR, FALLBACK_MINUTE
    hour = cr.normalized_hour(bedtime_hour - LEAD_MINUTES / 60.0)
    whole = int(hour)
    minute = _swift_round((hour - whole) * 60)
    if minute >= 60:
        minute = 0
        whole = (whole + 1) % 24
    if minute < 0:
        minute = 0
    return whole, minute


def inferred_bedtime_hour(
    goal: ScheduleGoal | None,
    need_hours: float = cr.DEFAULT_SLEEP_NEED_HOURS,
) -> float | None:
    if goal is None or not goal.is_active:
        return None
    return cr.normalized_hour(goal.target_wake_hour - need_hours)
