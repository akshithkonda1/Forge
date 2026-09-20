"""HydrationEngine — how much water this person actually needs today, and
whether they are on pace to drink it.

Python port of ForgeCore's ``HydrationEngine.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/HydrationEngine.swift``),
kept numerically identical to it. Every constant and formula below cites the
exact Swift source line range it mirrors.

The "eight glasses" rule is a slogan, not a measurement. Need scales with
body mass, rises with work already done, and ticks up in the luteal phase
and during a period. Evening is a taper, not a catch-up: slamming the
remaining target at 10pm just fragments sleep.

Ported in full -- the Swift file is self-contained (imports only
Foundation). Reuses ``aria_core.circadian_rhythm.normalized_hour`` rather
than re-deriving the same wrap-hour formula a third time in this package;
``quality_of_life.py``'s ``_hydration_pillar`` was written against a
guessed approximation of this exact target/glasses formula before this
file existed and has since been updated to call these functions directly
(see that module's own history).

Stdlib only (aside from the sibling ``aria_core.circadian_rhythm``
import). Deterministic. Pure -- no I/O.
"""

from __future__ import annotations

import math
from dataclasses import dataclass

from .circadian_rhythm import normalized_hour

# --- Constants ---------------------------------------------------------
# Mirrors HydrationEngine's static lets (Swift L20-37).

MILLILITERS_PER_KILOGRAM = 33.0  # Midpoint of the commonly cited 30-35 ml/kg range.
GLASS_MILLILITERS = 237.0        # One US cup. A display unit, not the model of need.
MILLILITERS_PER_FLUID_OUNCE = 29.5735

MINIMUM_TARGET_MILLILITERS = 1_500.0
MAXIMUM_TARGET_MILLILITERS = 5_000.0
DEFAULT_WEIGHT_KILOGRAMS = 70.0

LUTEAL_BONUS_MILLILITERS = 200.0        # Progesterone raises core temperature.
MENSTRUATION_BONUS_MILLILITERS = 300.0  # Fluid loss across a bleed, plus the usual advice.

# Hours after wake before the pace line starts, and hours before onset
# when it should already be finished.
MORNING_RAMP_HOURS = 0.5
EVENING_TAPER_HOURS = 2.0

# --- CycleAdjustment / Status ---------------------------------------------
# Mirrors CycleAdjustment/Status (Swift L39-50).

CYCLE_NONE = "none"
CYCLE_LUTEAL = "luteal"
CYCLE_MENSTRUATION = "menstruation"

STATUS_BEHIND = "behind"
STATUS_ON_TRACK = "on_track"
STATUS_MET = "met"
STATUS_OVER = "over"


@dataclass(frozen=True)
class Preset:
    """Mirrors Preset (Swift L52-64)."""

    id: str
    title: str
    milliliters: float
    symbol_name: str


# The four sizes people actually pour. Glasses first because that is what
# the Lifestyle card still logs in one tap. Mirrors `presets` (Swift L68-73).
PRESETS: tuple[Preset, ...] = (
    Preset(id="glass", title="Glass", milliliters=250, symbol_name="cup.and.saucer.fill"),
    Preset(id="small", title="Small bottle", milliliters=350, symbol_name="drop.circle"),
    Preset(id="bottle", title="Bottle", milliliters=500, symbol_name="drop.circle.fill"),
    Preset(id="large", title="Large", milliliters=750, symbol_name="jug.fill"),
)


# --- Target ------------------------------------------------------------
# Mirrors targetMilliliters/resolvedTargetMilliliters/glasses(fromMilliliters:)/
# milliliters(fromGlasses:)/milliliters(fromFluidOunces:)/fluidOunces(from
# Milliliters:) (Swift L85-131).

def target_milliliters(weight_kilograms: float | None, active_calories: float = 0.0,
                        cycle: str = CYCLE_NONE, hot_environment: bool = False) -> float:
    """Today's need in milliliters.

    `active_calories` adds 1 ml per kcal already burned -- a 500 kcal
    session is half a litre, the usual gym-floor advice without
    pretending sweat rate was measured. Capped so a long ride cannot push
    the target into "drink a gallon" territory."""
    mass = max(35.0, weight_kilograms if weight_kilograms is not None else DEFAULT_WEIGHT_KILOGRAMS)
    base = mass * MILLILITERS_PER_KILOGRAM
    activity = min(1_200.0, max(0.0, active_calories))
    heat = 400.0 if hot_environment else 0.0
    if cycle == CYCLE_LUTEAL:
        cycle_bonus = LUTEAL_BONUS_MILLILITERS
    elif cycle == CYCLE_MENSTRUATION:
        cycle_bonus = MENSTRUATION_BONUS_MILLILITERS
    else:
        cycle_bonus = 0.0
    return min(MAXIMUM_TARGET_MILLILITERS,
               max(MINIMUM_TARGET_MILLILITERS, base + activity + heat + cycle_bonus))


def resolved_target_milliliters(user_goal: float | None, suggested: float) -> float:
    """A goal the person set themselves, otherwise the estimated need.
    Clamped to the same physiological range as the estimate so a typo
    cannot become "drink 80 litres."."""
    if user_goal is None:
        return suggested
    return min(MAXIMUM_TARGET_MILLILITERS, max(MINIMUM_TARGET_MILLILITERS, user_goal))


def glasses_from_milliliters(ml: float) -> float:
    return ml / GLASS_MILLILITERS


def milliliters_from_glasses(glasses: float) -> float:
    return glasses * GLASS_MILLILITERS


def milliliters_from_fluid_ounces(ounces: float) -> float:
    return ounces * MILLILITERS_PER_FLUID_OUNCE


def fluid_ounces_from_milliliters(ml: float) -> float:
    return ml / MILLILITERS_PER_FLUID_OUNCE


# --- Pace --------------------------------------------------------------
# Mirrors expectedMilliliters/status/guidance (Swift L141-197).

def expected_milliliters(hour: float, target: float, wake_hour: float = 7.0,
                          onset_hour: float = 23.0) -> float:
    """How much of today's target should already be in by `hour`, given a
    wake and a bedtime. The line is flat overnight, climbs across the
    waking day, and is finished `EVENING_TAPER_HOURS` before onset so the
    last drinks are not happening in bed."""
    now = normalized_hour(hour)
    wake = normalized_hour(wake_hour)
    onset = normalized_hour(onset_hour)
    since_wake = normalized_hour(now - wake)
    awake_span = normalized_hour(onset - wake)
    drink_span = max(1.0, awake_span - MORNING_RAMP_HOURS - EVENING_TAPER_HOURS)

    if since_wake < MORNING_RAMP_HOURS:
        return 0.0
    if since_wake >= MORNING_RAMP_HOURS + drink_span:
        return target
    progressed = (since_wake - MORNING_RAMP_HOURS) / drink_span
    return target * min(1.0, max(0.0, progressed))


def status(consumed: float, target: float, expected: float) -> str:
    if target <= 0:
        return STATUS_ON_TRACK
    if consumed >= target * 1.15:
        return STATUS_OVER
    if consumed >= target:
        return STATUS_MET
    if consumed + 80 >= expected * 0.85:
        return STATUS_ON_TRACK
    return STATUS_BEHIND


def guidance(status_: str, remaining: float, hours_until_onset: float) -> str:
    """One line on what to do with the rest of the day. Written as
    guidance, not a scolding -- the model does not know about a long
    meeting."""
    left = max(0.0, remaining)
    if status_ == STATUS_MET:
        return "Need is covered. Sip if you are thirsty; there is nothing to catch up."
    if status_ == STATUS_OVER:
        return "Past today's need. Extra water is fine, but the next litre will not do extra work."
    if status_ == STATUS_ON_TRACK:
        if hours_until_onset <= EVENING_TAPER_HOURS:
            return "On pace, and the evening taper has started. Small sips only from here."
        return "On pace. Keep a bottle in reach and this finishes itself."
    # STATUS_BEHIND
    if hours_until_onset <= EVENING_TAPER_HOURS:
        return "Still short, but it is late to chase the number. A small glass, then stop."
    glasses = max(1, math.ceil(left / GLASS_MILLILITERS))
    plural = "" if glasses == 1 else "es"
    return f"About {glasses} glass{plural} behind the day's pace. Spread them, do not chug."
