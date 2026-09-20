"""WindDownPredictor — local heuristic for "when should tonight start
winding down?"

Python port of ForgeCore's ``WindDownPredictor.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/WindDownPredictor.swift``),
kept numerically identical to it. Every constant and formula below cites the
exact Swift source line range it mirrors. No test file exists on the Swift
side for this module (unlike ``CircadianRhythmTests.swift``/
``SleepDepthScorerTests.swift``), so every expected value in this port's own
test suite was hand-derived from the algorithm below and independently
verified, not just re-run against the port.

No network, no model, just circadian common sense made explicit::

    typical onset    = the onset near the middle of recent sleep-start times
    sleep debt       = mean shortfall vs sleep need over recent nights
    tonight's window = typical onset, pulled earlier by debt/2
                        (capped at 45 min -- dramatic shifts backfire)
    wind-down start  = 20 min before the window opens

Epistemic honesty: fewer than 3 recent onsets -> ``None``. The caller
should say "still learning your rhythm" instead of inventing a bedtime.

Ported in full -- the Swift file is self-contained. One deliberate
simplification, same as ``circadian_rhythm.py``: Swift's
``minutesSinceNoon(of:calendar:)`` takes an explicit ``Calendar`` to
control which time zone a ``Date`` is read in; Python's ``datetime``
already carries wall-clock hour/minute directly once converted to the
desired zone, so there is no separate "calendar" parameter here -- callers
pass ``recent_onsets``/``now`` already in the zone whose wall-clock hour
should drive the prediction.

Stdlib only. Deterministic (given `now`). Pure -- no I/O.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime, timedelta

# --- Tunables ----------------------------------------------------------------
# Mirrors WindDownPredictor's static lets (Swift L31-33).

MAX_EARLIER_SHIFT_MINUTES = 45.0
WINDOW_LENGTH_MINUTES = 45.0
WIND_DOWN_LEAD_MINUTES = 20.0


@dataclass(frozen=True)
class WindDownPlan:
    """Mirrors WindDownPlan (Swift L17-27)."""

    wind_down_start: datetime
    bedtime_window_start: datetime
    bedtime_window_end: datetime


def minutes_since_noon(dt: datetime) -> float:
    """Minutes since noon, wrapped to [0, 1440): 22:30 -> 630, 00:15 -> 735.
    Anchoring at noon keeps the midnight crossing monotonic for any
    realistic sleeper. Mirrors ``minutesSinceNoon(of:calendar:)`` (Swift
    L81-86)."""
    raw = (dt.hour * 60 + dt.minute) - 12 * 60
    return raw + 24 * 60 if raw < 0 else raw


def plan(recent_onsets: list[datetime], recent_sleep_minutes: list[float],
         sleep_need_minutes: float = 8 * 60, now: datetime | None = None) -> WindDownPlan | None:
    """Mirrors ``plan(recentOnsets:recentSleepMinutes:sleepNeedMinutes:now:
    calendar:)`` (Swift L40-79).

    Args:
        recent_onsets: sleep-start timestamps from recent nights.
        recent_sleep_minutes: asleep minutes for those nights.
        sleep_need_minutes: target (default 8h).
        now: "today" anchor, injectable for tests. Defaults to
            ``datetime.now()`` -- evaluated at call time, not import time,
            same as Swift's per-call ``Date()`` default.
    """
    if len(recent_onsets) < 3:
        return None
    if now is None:
        now = datetime.now()

    # Median-ish onset as minutes-since-noon. `count // 2` on a sorted list
    # is not a true statistical median for an even count (it takes the
    # upper-middle element, not the average of the two middle ones) --
    # this mirrors Swift's `onsetMinutes[onsetMinutes.count / 2]` exactly,
    # not `statistics.median`.
    onset_minutes = sorted(minutes_since_noon(d) for d in recent_onsets)
    median = onset_minutes[len(onset_minutes) // 2]

    # Debt pulls tonight earlier, gently.
    if not recent_sleep_minutes:
        debt = 0.0
    else:
        shortfalls = [max(0.0, sleep_need_minutes - m) for m in recent_sleep_minutes]
        debt = sum(shortfalls) / len(shortfalls)
    shift = min(debt / 2, MAX_EARLIER_SHIFT_MINUTES)

    target_minutes = median - shift
    noon = now.replace(hour=12, minute=0, second=0, microsecond=0)
    window_start = noon + timedelta(minutes=target_minutes)
    # If we're computing after midnight (already inside "tonight"), the
    # anchor noon is the following day's -- pull back one day.
    if (window_start - now).total_seconds() > 20 * 3600:
        window_start -= timedelta(hours=24)

    return WindDownPlan(
        wind_down_start=window_start - timedelta(minutes=WIND_DOWN_LEAD_MINUTES),
        bedtime_window_start=window_start,
        bedtime_window_end=window_start + timedelta(minutes=WINDOW_LENGTH_MINUTES),
    )
