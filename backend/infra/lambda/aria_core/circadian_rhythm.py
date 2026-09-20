"""Circadian rhythm — the two-process model of alertness (Borbély, 1982).

Python port of ForgeCore's ``CircadianRhythm.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/CircadianRhythm.swift``),
kept numerically identical to it: same tunables, same phase estimator, same
energy curve, same named windows. Every constant and formula below cites the
exact Swift source line range it mirrors.

Predicts when someone will feel alert and when they will not, from their own
sleep history alone -- no questionnaire, no chronotype quiz. Alertness is the
difference between a homeostatic pressure that builds the longer you are
awake (process S) and a circadian rhythm running on its own ~24-hour clock
(process C), plus an explicitly-modelled afternoon dip that neither process
produces on its own (see ``DIP_*`` below and the Swift source's own note on
why it is empirical rather than derived).

Ported in full: every public function and constant in the Swift file.
Nothing was left out -- this module is self-contained pure arithmetic over
dates and hours, with no dependency on any other Swift or Python file.

One deliberate simplification: Swift's ``hourOfDay(_:calendar:)`` takes a
``Calendar`` to control which time zone a ``Date`` is read in (its own test
suite pins this to UTC specifically to dodge DST). Python's ``datetime``
already carries its wall-clock hour/minute directly once it is in the
desired zone (aware or naive), so there is no separate "calendar" parameter
here -- callers are simply expected to pass ``Night.onset``/``Night.wake``
already converted to the local wall-clock time zone that should drive the
phase estimate, the same responsibility Swift callers have when picking
which ``Calendar`` to pass.

Stdlib only. Deterministic. Pure -- no I/O.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime

# --- Tunables --------------------------------------------------------------
# Mirrors the "MARK: Tunables" constants (Swift L32-79).

# Time constants for process S. Rise is slow (you can stay up), decay is
# fast (sleep pays down pressure quickly). Standard literature values,
# not fitted per person.
PRESSURE_RISE_HOURS = 18.2
PRESSURE_DECAY_HOURS = 4.2

# The circadian alertness minimum sits roughly two hours before habitual
# wake -- close to core body temperature minimum.
NADIR_HOURS_BEFORE_WAKE = 2.0

# Melatonin onset is about two hours before habitual sleep onset.
MELATONIN_LEAD_HOURS = 2.0

# Where the afternoon dip sits relative to habitual wake, how wide it is,
# and how far it pulls the curve down. Empirical (Monk, 2005), not derived
# from the two-process model itself -- see the Swift source's own note.
DIP_HOURS_AFTER_WAKE = 7.5
DIP_WIDTH_HOURS = 1.5
DIP_DEPTH = 0.30

# Physiological bounds on sleep need.
MIN_SLEEP_NEED_HOURS = 6.5
MAX_SLEEP_NEED_HOURS = 9.5
DEFAULT_SLEEP_NEED_HOURS = 8.0

# Sleep debt accumulates over a rolling fortnight.
DEBT_WINDOW_NIGHTS = 14


def _swift_round(value: float) -> int:
    """Swift's ``Double.rounded()`` default rule: round half away from zero
    (schoolbook rounding), not Python's banker's-rounding ``round()``."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


# --- Inputs ------------------------------------------------------------------
# Mirrors Night (Swift L86-105).

@dataclass(frozen=True)
class Night:
    """One night, reduced to the three things the model needs."""

    onset: datetime
    wake: datetime
    # Actual time asleep, which is not `wake - onset` -- time in bed
    # includes the awake segments.
    asleep_hours: float

    @property
    def mid_sleep(self) -> datetime:
        """Mid-sleep, the standard circadian phase marker. Preferred over
        bedtime because bedtime is a decision and mid-sleep is closer to
        biology. (Not otherwise used by this module -- exposed because the
        Swift source exposes it.)"""
        return self.onset + (self.wake - self.onset) / 2


# --- Sleep need --------------------------------------------------------------
# Mirrors sleepNeedHours(from:)/sleepNeedHours(fromAsleepHours:) (Swift
# L111-139).

def sleep_need_hours(nights: list[Night]) -> float:
    return sleep_need_hours_from_durations([n.asleep_hours for n in nights])


def sleep_need_hours_from_durations(hours: list[float]) -> float:
    """How much sleep this person actually needs, from their own best
    nights. Uses a high percentile rather than a mean -- the mean of a
    sleep-deprived person's nights is their deprivation, not their need.
    Clamped to a physiological range so a single 14-hour flu night does not
    redefine "need"."""
    durations = sorted(h for h in hours if h > 1)
    # Under a week there is not enough signal; a confident wrong number is
    # worse than the population default.
    if len(durations) < 5:
        return DEFAULT_SLEEP_NEED_HOURS
    index = _swift_round((len(durations) - 1) * 0.9)
    estimate = durations[min(index, len(durations) - 1)]
    return min(max(estimate, MIN_SLEEP_NEED_HOURS), MAX_SLEEP_NEED_HOURS)


# --- Sleep debt ----------------------------------------------------------
# Mirrors sleepDebtHours(nights:need:window:)/sleepDebtHours(asleepHours:
# need:window:) (Swift L141-160). Only shortfalls count -- an extra hour
# one night does not bank credit against a future short one.

def sleep_debt_hours(nights: list[Night], need: float, window: int = DEBT_WINDOW_NIGHTS) -> float:
    return sleep_debt_hours_from_durations([n.asleep_hours for n in nights], need, window)


def sleep_debt_hours_from_durations(hours: list[float], need: float,
                                     window: int = DEBT_WINDOW_NIGHTS) -> float:
    recent = hours[max(0, len(hours) - window):] if window > 0 else []
    return sum(max(0.0, need - asleep) for asleep in recent)


# --- Phase -------------------------------------------------------------------
# Mirrors Phase (Swift L168-180) and phase(from:calendar:) (Swift L182-205).

@dataclass(frozen=True)
class Phase:
    """The user's circadian phase: habitual wake and onset times of day
    (hours past local midnight, fractional)."""

    wake_hour: float
    onset_hour: float
    # How much the recent nights agree, 0...1. Low confidence should make
    # the UI hedge rather than assert.
    confidence: float


def phase(nights: list[Night]) -> Phase | None:
    """Estimate phase from recent nights. Averaged as angles, not as
    numbers -- a 23:30 bedtime and a 00:30 bedtime average to midnight, but
    naive arithmetic on 23.5 and 0.5 gives noon, the exact opposite."""
    recent = nights[-DEBT_WINDOW_NIGHTS:] if DEBT_WINDOW_NIGHTS > 0 else []
    if not recent:
        return None

    wake_hours = [hour_of_day(n.wake) for n in recent]
    onset_hours = [hour_of_day(n.onset) for n in recent]

    wake = _circular_mean(wake_hours)
    onset = _circular_mean(onset_hours)

    # Spread of wake times is the honest confidence signal: a shift worker
    # has no stable phase and should be told so, not given a curve.
    spread = circular_spread(wake_hours)
    confidence = max(0.0, min(1.0, 1 - spread / 3.0))

    return Phase(wake_hour=wake, onset_hour=onset, confidence=confidence)


# --- The curve -----------------------------------------------------------
# Mirrors energy(atHour:phase:hoursAwake:sleepDebtHours:sleepNeedHours:)
# (Swift L217-250).

def energy(hour: float, phase_: Phase, hours_awake: float,
           sleep_debt_hours_: float = 0.0,
           sleep_need_hours_: float = DEFAULT_SLEEP_NEED_HOURS) -> float:
    """Predicted alertness at a moment, 0...1. `hour` drives process C via
    `phase_`; `hours_awake` drives process S. Sleep debt depresses the whole
    curve rather than changing its shape -- the dip is still a dip,
    everything is just lower."""
    # Process C: cosine peaking in the evening, trough ~2h before wake.
    nadir = normalized_hour(phase_.wake_hour - NADIR_HOURS_BEFORE_WAKE)
    radians = (hour - nadir) / 24.0 * 2 * math.pi
    circadian = (1 - math.cos(radians)) / 2  # 0 at nadir, 1 twelve hours later

    # The afternoon dip, placed by clock offset from wake rather than by
    # hours_awake -- overnight, hours_awake is a decaying residue rather
    # than real elapsed time and sweeps back down through 7.5 in the small
    # hours; anchoring the dip to it would carve a phantom slump into the
    # night.
    since_wake = normalized_hour(hour - phase_.wake_hour)
    from_dip_centre = (since_wake - DIP_HOURS_AFTER_WAKE) / DIP_WIDTH_HOURS
    circadian -= DIP_DEPTH * math.exp(-from_dip_centre * from_dip_centre / 2)

    # Process S: pressure rises the longer you have been awake, and
    # alertness is what is left over.
    pressure = 1 - math.exp(-max(0.0, hours_awake) / PRESSURE_RISE_HOURS)
    recovered = 1 - pressure

    # Weighted so neither process can flatten the other out.
    value = 0.55 * circadian + 0.45 * recovered

    # Debt is expressed relative to need, so eight hours owed means more to
    # someone who needs seven than to someone who needs nine.
    debt_ratio = min(1.5, sleep_debt_hours_ / max(1.0, sleep_need_hours_))
    value -= 0.22 * debt_ratio

    return min(1.0, max(0.0, value))


def curve(phase_: Phase, sleep_debt_hours_: float = 0.0,
          sleep_need_hours_: float = DEFAULT_SLEEP_NEED_HOURS,
          samples_per_hour: int = 4) -> list[tuple[float, float]]:
    """Samples the curve across a day. `samples_per_hour` of 4 gives a
    smooth enough path to draw without the view doing its own
    interpolation."""
    step = 1.0 / max(1, samples_per_hour)
    out: list[tuple[float, float]] = []
    hour = 0.0
    while hour < 24:
        out.append((hour, energy(hour, phase_, hours_awake(hour, phase_),
                                  sleep_debt_hours_, sleep_need_hours_)))
        hour += step
    return out


def hours_awake(hour: float, phase_: Phase) -> float:
    """Hours since habitual wake, wrapping across midnight, clamped to zero
    during the sleep window -- pressure decays while asleep rather than
    continuing to build."""
    since = normalized_hour(hour - phase_.wake_hour)
    awake_span = normalized_hour(phase_.onset_hour - phase_.wake_hour)
    if since > awake_span:
        # Past onset the person is asleep; pressure is falling, so report
        # the residue rather than a number that keeps climbing all night.
        asleep_for = since - awake_span
        at_onset = awake_span
        return max(0.0, at_onset * math.exp(-asleep_for / PRESSURE_DECAY_HOURS))
    return since


# --- Named windows -----------------------------------------------------------
# Mirrors Window (Swift L294-335): title + guidance copy, word for word.

SLEEP = "sleep"
GROGGINESS = "grogginess"
MORNING_PEAK = "morning_peak"
AFTERNOON_DIP = "afternoon_dip"
EVENING_PEAK = "evening_peak"
MELATONIN_WINDOW = "melatonin_window"
WINDING_DOWN = "winding_down"

WINDOWS = (SLEEP, GROGGINESS, MORNING_PEAK, AFTERNOON_DIP, EVENING_PEAK,
           MELATONIN_WINDOW, WINDING_DOWN)

WINDOW_TITLE: dict[str, str] = {
    SLEEP: "Sleep window",
    GROGGINESS: "Grogginess",
    MORNING_PEAK: "Morning peak",
    AFTERNOON_DIP: "Afternoon dip",
    EVENING_PEAK: "Evening peak",
    MELATONIN_WINDOW: "Melatonin window",
    WINDING_DOWN: "Winding down",
}

# One line on what to do with it. Written as guidance, not instruction --
# the model is a prediction about a body, not a schedule someone agreed to.
WINDOW_GUIDANCE: dict[str, str] = {
    SLEEP: "Your body expects to be asleep now.",
    GROGGINESS: ("Sleep inertia is normal and passes. Light and movement shorten it; "
                 "a decision made now is worth remaking later."),
    MORNING_PEAK: "Sharpest stretch of the day. Worth spending on the thing that needs thinking.",
    AFTERNOON_DIP: "A real circadian trough, not a failure of will. Good for routine work, bad for anything hard.",
    EVENING_PEAK: "A second wind, and the hardest time to fall asleep even when tired.",
    MELATONIN_WINDOW: "Melatonin is rising. Bright light and screens here are what push tomorrow later.",
    WINDING_DOWN: "The runway into sleep. Dim, quiet, and boring is the goal.",
}


def window(hour: float, phase_: Phase) -> str:
    """Which window a given hour falls into. Offsets are from habitual
    wake, which is why they hold for an early riser and a night owl alike:
    the afternoon dip is not at 3pm, it is about seven hours after you got
    up."""
    since_wake = normalized_hour(hour - phase_.wake_hour)
    awake_span = normalized_hour(phase_.onset_hour - phase_.wake_hour)
    melatonin_start = normalized_hour(awake_span - MELATONIN_LEAD_HOURS)

    if since_wake >= awake_span:
        return SLEEP
    if since_wake < 1.0:
        return GROGGINESS
    if since_wake >= melatonin_start:
        return MELATONIN_WINDOW
    if since_wake >= melatonin_start - 1.0:
        return WINDING_DOWN
    if 2.0 <= since_wake < 5.0:
        return MORNING_PEAK
    if 6.5 <= since_wake < 9.0:
        return AFTERNOON_DIP
    if 10.5 <= since_wake < 13.0:
        return EVENING_PEAK
    # Between the named stretches. Not every hour deserves a label, and
    # inventing one for all of them would make the real ones meaningless.
    return MORNING_PEAK if since_wake < 6.5 else EVENING_PEAK


def melatonin_onset_hour(phase_: Phase) -> float:
    """When melatonin starts rising, given a phase -- the practical start
    of the evening."""
    return normalized_hour(phase_.onset_hour - MELATONIN_LEAD_HOURS)


def next_window(hour: float, phase_: Phase) -> tuple[str, float] | None:
    """The next window boundary after `hour`, for "what's next" UI."""
    current = window(hour, phase_)
    probe = hour
    elapsed = 0.0
    # Quarter-hour steps over a full day. Bounded, so a phase that somehow
    # produces one uniform window returns None instead of spinning.
    while elapsed < 24:
        probe = normalized_hour(probe + 0.25)
        elapsed += 0.25
        nxt = window(probe, phase_)
        if nxt != current:
            return (nxt, elapsed)
    return None


# --- Clock arithmetic --------------------------------------------------------
# Mirrors hourOfDay/normalizedHour/circularMean/circularSpread (Swift
# L387-427).

def hour_of_day(dt: datetime) -> float:
    """Hours past local midnight, fractional."""
    return dt.hour + dt.minute / 60.0


def normalized_hour(hour: float) -> float:
    """Wrap into [0, 24) -- `-1.5` is 22:30, not a negative time."""
    wrapped = math.fmod(hour, 24.0)
    return wrapped + 24.0 if wrapped < 0 else wrapped


def _circular_mean(hours: list[float]) -> float:
    """Mean of clock times, via the unit circle. See the note on `phase`."""
    if not hours:
        return 0.0
    x = y = 0.0
    for hour in hours:
        radians = hour / 24 * 2 * math.pi
        x += math.cos(radians)
        y += math.sin(radians)
    angle = math.atan2(y / len(hours), x / len(hours))
    return normalized_hour(angle / (2 * math.pi) * 24)


def circular_spread(hours: list[float]) -> float:
    """Circular standard deviation, in hours. Zero when every night
    matches."""
    if len(hours) <= 1:
        return 0.0
    x = y = 0.0
    for hour in hours:
        radians = hour / 24 * 2 * math.pi
        x += math.cos(radians)
        y += math.sin(radians)
    n = len(hours)
    resultant = math.sqrt(x * x + y * y) / n
    if not (0 < resultant <= 1):
        return 0.0
    # Standard circular SD, converted from radians back to hours.
    return math.sqrt(-2 * math.log(resultant)) / (2 * math.pi) * 24
