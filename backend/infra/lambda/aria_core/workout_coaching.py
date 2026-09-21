"""Zone-boundary coaching cue — when to speak, and what to say.

Python port of ForgeCore's ``WorkoutCoaching.swift``. A cue fires only on a
genuine zone change and no more than once per throttle window. Wording never
instructs; the user owns the effort.

Native Watch/iOS/Android render the cue; this module is the decision.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timezone

from .hr_zones import HRZone

THROTTLE_SECONDS = 45.0


def _aware(dt: datetime) -> datetime:
    return dt if dt.tzinfo is not None else dt.replace(tzinfo=timezone.utc)


@dataclass(frozen=True)
class CoachingDecision:
    cue: str
    fired_at: datetime


def cue(
    zone: HRZone,
    previous_zone: int | None,
    target: int,
    last_cue_at: datetime,
    now: datetime,
    *,
    allows_building_up: bool = True,
    throttle: float = THROTTLE_SECONDS,
) -> CoachingDecision | None:
    if zone.zone == previous_zone:
        return None
    if (_aware(now) - _aware(last_cue_at)).total_seconds() <= throttle:
        return None

    if zone.zone > target + 1:
        line = "Running above the day's plan — easing off a touch keeps this sustainable. Your call."
    elif zone.zone < target - 1 and allows_building_up:
        line = f"Plenty in reserve if you want to build toward Zone {target}. No rush."
    else:
        line = zone.coaching_line
    return CoachingDecision(cue=line, fired_at=now)
