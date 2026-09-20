"""ScheduleCorrector + ScheduleGoalParser — goal-directed wake-time phase
advance/delay, and conversational parsing of "up at 6am starting Monday"
into a schedule goal.

Python port of ForgeCore's ``ScheduleCorrector.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/ScheduleCorrector.swift``),
kept numerically identical to it. Every constant and formula below cites the
exact Swift source line range it mirrors. Depends on
``aria_core.circadian_rhythm`` for phase/sleep-need estimation and hour
normalization -- the same dependency the Swift source has on
``CircadianRhythm.swift``.

Sleep-medicine guidance is a 15-20 minute shift per night (jet-lag style),
not a single jump: ``ScheduleCorrector.tonight()`` takes the current phase
(from ``circadian_rhythm.phase()``) and a target, and ratchets toward it at
a capped nightly rate, spread evenly across the nights remaining until a
cutover date when one is set.

Ported: ``ScheduleGoal``, ``ScheduleCorrectionStep`` (including its
``guidance_line``/``coaching_reply`` copy, word for word), ``tonight()``,
``signed_hour_delta()``, ``clock_label()``, and the full
``ScheduleGoalParser`` (cue detection, the wake-hour regex, weekday cutover
parsing).

Not ported: ``ScheduleGoalStore`` (UserDefaults persistence, iOS-only --
same reasoning as ``QualityOfLifeLivingStore``/``SleepDepthBaselineStore``
in the earlier ports).

Stdlib only (aside from the sibling ``aria_core.circadian_rhythm`` import).
Deterministic (given `now`). Pure -- no I/O.
"""

from __future__ import annotations

import math
import re
from dataclasses import dataclass, field
from datetime import datetime, timedelta

from . import circadian_rhythm as cr


def _swift_round(value: float) -> int:
    """Swift's ``Double.rounded()`` default rule: round half away from
    zero, not Python's banker's-rounding ``round()``."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


# --- Goal ----------------------------------------------------------------
# Mirrors ScheduleGoal (Swift L8-34).

DEFAULT_MAX_SHIFT_MINUTES = 15.0
HARD_MAX_SHIFT_MINUTES = 20.0


@dataclass
class ScheduleGoal:
    """An explicit wake target and the first morning it should hold.

    Sleep-medicine guidance is a 15-20 minute shift per night -- jet-lag
    style -- not a single jump. `circadian_rhythm.phase()` is the current
    body-clock; this is the destination and the ratchet toward it."""

    target_wake_hour: float
    cutover_start: datetime
    max_shift_minutes_per_night: float = DEFAULT_MAX_SHIFT_MINUTES
    created_at: datetime = field(default_factory=datetime.now)
    is_active: bool = True

    def __post_init__(self) -> None:
        self.target_wake_hour = cr.normalized_hour(self.target_wake_hour)
        self.max_shift_minutes_per_night = min(
            HARD_MAX_SHIFT_MINUTES, max(5.0, self.max_shift_minutes_per_night)
        )


# --- Step ------------------------------------------------------------------
# Mirrors ScheduleCorrectionStep (Swift L37-91), including its guidance/
# coaching copy word for word.

@dataclass(frozen=True)
class ScheduleCorrectionStep:
    """Tonight's step on the ladder toward `ScheduleGoal`."""

    recommended_wake_hour: float
    recommended_onset_hour: float
    shift_minutes_tonight: float
    remaining_gap_minutes: float
    nights_remaining_estimate: int
    reached_target: bool
    current_wake_hour: float
    confidence: float
    target_wake_hour: float

    @property
    def guidance_line(self) -> str:
        target = clock_label(self.target_wake_hour)
        if self.reached_target:
            return f"Wake target is {target} — you're on it."
        minutes = _swift_round(abs(self.shift_minutes_tonight))
        direction = "earlier" if self.shift_minutes_tonight < 0 else "later"
        nights = max(1, self.nights_remaining_estimate)
        plural = "" if nights == 1 else "s"
        return f"Shifting {minutes} min {direction} toward {target} — about {nights} night{plural}."

    @property
    def coaching_reply(self) -> str:
        target = clock_label(self.target_wake_hour)
        bed = clock_label(self.recommended_onset_hour)
        if self.reached_target:
            return f"You're already up at {target}. I'll keep bedtime near {bed} so sleep holds tonight."
        minutes = _swift_round(abs(self.shift_minutes_tonight))
        direction = "earlier" if self.shift_minutes_tonight < 0 else "later"
        return f"I'll get you up at {target} — {minutes} min {direction} tonight so sleep lands near {bed}."


# --- Corrector -----------------------------------------------------------
# Mirrors ScheduleCorrector (Swift L95-171): stateless, current phase in,
# tonight's onset/wake out. Persistence lives in ScheduleGoalStore (not
# ported).

REACHED_THRESHOLD_MINUTES = 5.0


def signed_hour_delta(from_: float, to: float) -> float:
    """Shortest signed hour delta on the clock, -12...12."""
    delta = cr.normalized_hour(to) - cr.normalized_hour(from_)
    if delta > 12:
        delta -= 24
    if delta < -12:
        delta += 24
    return delta


def clock_label(hour: float) -> str:
    normalized = cr.normalized_hour(hour)
    whole = int(normalized)
    minute = _swift_round((normalized - whole) * 60)
    if minute >= 60:
        minute = 0
        whole = (whole + 1) % 24
    suffix = "pm" if whole >= 12 else "am"
    h12 = 12 if whole % 12 == 0 else whole % 12
    return f"{h12}:{minute:02d} {suffix}"


def tonight(goal: ScheduleGoal, nights: list[cr.Night],
            now: datetime | None = None) -> ScheduleCorrectionStep | None:
    if not goal.is_active:
        return None
    if now is None:
        now = datetime.now()
    phase = cr.phase(nights)
    if phase is None:
        return None

    need = cr.sleep_need_hours(nights)
    gap_hours = signed_hour_delta(phase.wake_hour, goal.target_wake_hour)
    gap_minutes = gap_hours * 60
    reached = abs(gap_minutes) < REACHED_THRESHOLD_MINUTES
    max_shift_hours = goal.max_shift_minutes_per_night / 60.0

    start_today = now.replace(hour=0, minute=0, second=0, microsecond=0)
    cutover_day = goal.cutover_start.replace(hour=0, minute=0, second=0, microsecond=0)
    days_until = (cutover_day - start_today).days

    if reached:
        shift_hours = 0.0
    elif days_until > 0:
        planned = gap_hours / days_until
        shift_hours = min(max_shift_hours, max(-max_shift_hours, planned))
    else:
        shift_hours = min(max_shift_hours, max(-max_shift_hours, gap_hours))

    tonight_wake = cr.normalized_hour(phase.wake_hour + shift_hours)
    tonight_onset = cr.normalized_hour(tonight_wake - need)
    remaining = abs(gap_minutes - shift_hours * 60)
    if reached:
        nights_left = 0
    else:
        nights_left = max(1, math.ceil(abs(gap_hours) / max(0.01, max_shift_hours)))

    return ScheduleCorrectionStep(
        recommended_wake_hour=tonight_wake,
        recommended_onset_hour=tonight_onset,
        shift_minutes_tonight=shift_hours * 60,
        remaining_gap_minutes=remaining,
        nights_remaining_estimate=nights_left,
        reached_target=reached,
        current_wake_hour=phase.wake_hour,
        confidence=phase.confidence,
        target_wake_hour=goal.target_wake_hour,
    )


# --- Parser ----------------------------------------------------------------
# Mirrors ScheduleGoalParser (Swift L195-291): conversational
# "up at 6am starting Monday" -> ScheduleGoal.

_SCHEDULE_CUES = (
    "up at", "wake at", "wake me", "get up at", "be up at",
    "getting up at", "alarm at", "wake time", "start waking",
    "waking up at", "need to be up",
)

_WAKE_HOUR_PATTERN = re.compile(
    r"(?:up at|wake(?: me)?(?: up)? at|get up at|be up at|getting up at|waking up at|alarm at|"
    r"wake time(?: of)?|need to be up(?: at)?)\s+(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?"
)

_WEEKDAY_CUES: tuple[tuple[int, str], ...] = (
    (1, "sunday"),
    (2, "monday"),
    (3, "tuesday"),
    (4, "wednesday"),
    (5, "thursday"),
    (6, "friday"),
    (7, "saturday"),
)


def is_schedule_ask(text: str) -> bool:
    return parse(text) is not None


def parse(text: str, now: datetime | None = None) -> ScheduleGoal | None:
    if now is None:
        now = datetime.now()
    lower = text.lower()
    if not _has_schedule_cue(lower):
        return None
    hour = parse_wake_hour(lower)
    if hour is None:
        return None
    cutover = _parse_cutover(lower, now)
    return ScheduleGoal(target_wake_hour=hour, cutover_start=cutover, created_at=now)


def _has_schedule_cue(lower: str) -> bool:
    return any(cue in lower for cue in _SCHEDULE_CUES)


def parse_wake_hour(lower: str) -> float | None:
    """Mirrors ``parseWakeHour(in:)`` (Swift L226-263) exactly, dead
    branches included: `hour` is clamped to [0, 23] a few lines above the
    `hour == 24`/`hour > 24` checks below, so those two (and the final
    "already 24h"/"hour == 12" no-op pair) can never actually fire --
    ported as-is rather than silently dropped, since removing unreachable
    code the Swift source itself carries would be an unrequested behavior
    change disguised as cleanup."""
    match = _WAKE_HOUR_PATTERN.search(lower)
    if not match:
        return None
    hour = int(match.group(1))
    minute = int(match.group(2)) if match.group(2) else 0
    stamp = match.group(3)
    is_pm: bool | None = None
    if stamp:
        if "p" in stamp:
            is_pm = True
        if "a" in stamp:
            is_pm = False

    hour = min(23, max(0, hour))
    minute = min(59, max(0, minute))
    if is_pm is not None:
        if is_pm and hour < 12:
            hour += 12
        if is_pm is False and hour == 12:
            hour = 0
    elif hour == 0 or hour == 24:  # unreachable: hour already clamped to <= 23
        hour = 0
    elif hour > 24:  # unreachable: hour already clamped to <= 23
        return None
    # Bare "6" on a wake ask is 6am, not 18:00. Both arms below are no-ops
    # given the clamp above -- ported for fidelity, not because they do
    # anything observable.
    if is_pm is None and 13 <= hour <= 23:
        pass
    elif is_pm is None and hour == 12:
        hour = 12

    return float(hour) + minute / 60.0


def _parse_cutover(lower: str, now: datetime) -> datetime:
    for code, name in _WEEKDAY_CUES:
        if name in lower:
            return _next_weekday(code, now)
    return now


def _next_weekday(weekday_code: int, from_: datetime) -> datetime:
    """`weekday_code` follows Foundation's ``Calendar.component(.weekday:)``
    numbering (Sunday=1 ... Saturday=7), matching the Swift source's own
    table exactly; converted here to Python's ``datetime.weekday()``
    numbering (Monday=0 ... Sunday=6) via `(code + 5) % 7`."""
    start = from_.replace(hour=0, minute=0, second=0, microsecond=0)
    target = (weekday_code + 5) % 7
    for offset in range(8):
        day = start + timedelta(days=offset)
        if day.weekday() == target:
            return day
    return start
