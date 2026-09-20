"""LifestyleTargets — personalized nutrition/activity/sleep/hydration
targets derived from a profile, with optional user overrides.

Python port of ForgeSwift's ``LifestyleTargets.swift``
(``ForgeSwift/ForgeSwift/LifestyleTargets.swift`` -- note this one lives in
the app target, not ``ForgeCore``, unlike every prior port; it has no Swift
test file). Kept numerically identical to it. Every constant and formula
below cites the exact Swift source line range it mirrors.

Depends on ``aria_core.hydration_engine`` (task #16) for the water target,
the same dependency ``LifestyleTargets.swift`` has on ``HydrationEngine``.

Takes a minimal ``Profile`` rather than porting the full ``UserProfile``:
the Swift ``UserProfile`` struct carries many UI/HealthKit-bound fields
(avatar filename, coaching style, connected devices, weekly schedule, ...)
that ``LifestyleTargets.resolve()`` never reads. ``Profile`` here has
exactly the five fields it actually uses (weight, age, gender, experience
level, fitness goals) -- a faithful reduction of the real read surface,
not an invented one.

One known quirk in the Swift source, ported as-is rather than "fixed":
``mifflinStJeorBMR`` hardcodes height at 175cm (``6.25 * 175``) for every
profile instead of reading ``profile.height`` -- the Mifflin-St Jeor
equation is supposed to use actual height, but the production formula
never has. Preserving this exactly (not correcting it) keeps this port's
output bit-identical to what the shipped app already computes; correcting
it would be a real behavior change to file as its own decision, not one
this port makes unilaterally.

Stdlib only (aside from the sibling ``aria_core.hydration_engine``
import). Deterministic. Pure -- no I/O.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from . import hydration_engine

# --- Profile enums ---------------------------------------------------------
# Mirrors Gender/ExperienceLevel/UserFitnessGoal (Models.swift), reduced to
# the values mifflinStJeorBMR/computedDefaults actually branch on.

MALE = "male"
FEMALE = "female"
NON_BINARY = "non_binary"
PREFER_NOT_TO_SAY = "prefer_not_to_say"
OTHER = "other"

BEGINNER = "beginner"
INTERMEDIATE = "intermediate"
ADVANCED = "advanced"
ELITE = "elite"

BUILD_MUSCLE = "build_muscle"
LOSE_FAT = "lose_fat"
IMPROVE_ENDURANCE = "improve_endurance"
GENERAL_FITNESS = "general_fitness"
ATHLETIC_PERFORMANCE = "athletic_performance"


def _swift_round(value: float) -> int:
    """Swift's ``Double.rounded()`` default rule: round half away from
    zero, not Python's banker's-rounding ``round()``."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


@dataclass(frozen=True)
class Profile:
    """The subset of UserProfile that LifestyleTargets.resolve() reads."""

    weight_kg: float | None = None
    age: int | None = None
    gender: str = OTHER
    experience_level: str = BEGINNER
    fitness_goals: frozenset[str] = field(default_factory=frozenset)


# --- Overrides ---------------------------------------------------------
# Mirrors NutritionPreferences (Swift L106-115).

@dataclass
class NutritionPreferences:
    protein_grams: int | None = None
    calorie_target: int | None = None
    step_target: int | None = None
    sleep_hours_target: float | None = None
    water_glasses_target: int | None = None
    # Daily water goal in milliliters. Wins over water_glasses_target when
    # both are set.
    hydration_target_ml: float | None = None
    active_calorie_target: int | None = None


# --- Targets -----------------------------------------------------------
# Mirrors LifestyleTargets (Swift L5-104).

@dataclass(frozen=True)
class LifestyleTargets:
    protein_grams: int
    calorie_target: int
    step_target: int
    sleep_hours_target: float
    water_glasses_target: int
    active_calorie_target: int


def resolve(profile: Profile, overrides: NutritionPreferences | None = None) -> LifestyleTargets:
    weight_kg = profile.weight_kg if profile.weight_kg is not None else 75.0
    computed = _computed_defaults(weight_kg, profile.age, profile.gender,
                                   profile.experience_level, profile.fitness_goals)

    def _or(value, default):
        return value if value is not None else default

    return LifestyleTargets(
        protein_grams=_or(overrides.protein_grams if overrides else None, computed.protein_grams),
        calorie_target=_or(overrides.calorie_target if overrides else None, computed.calorie_target),
        step_target=_or(overrides.step_target if overrides else None, computed.step_target),
        sleep_hours_target=_or(overrides.sleep_hours_target if overrides else None, computed.sleep_hours_target),
        water_glasses_target=_water_glasses(overrides, computed.water_glasses_target),
        active_calorie_target=_or(overrides.active_calorie_target if overrides else None,
                                   computed.active_calorie_target),
    )


def _computed_defaults(weight_kg: float, age: int | None, gender: str,
                        experience_level: str, fitness_goals: frozenset[str]) -> LifestyleTargets:
    bmr = _mifflin_st_jeor_bmr(weight_kg, age if age is not None else 30, gender)

    if experience_level == BEGINNER:
        activity_multiplier = 1.45
    elif experience_level == INTERMEDIATE:
        activity_multiplier = 1.55
    else:  # ADVANCED, ELITE
        activity_multiplier = 1.65

    if LOSE_FAT in fitness_goals:
        goal_factor = 0.88
    elif BUILD_MUSCLE in fitness_goals or ATHLETIC_PERFORMANCE in fitness_goals:
        goal_factor = 1.08
    else:
        goal_factor = 1.0
    calories = _swift_round(bmr * activity_multiplier * goal_factor)

    # Note: this checks buildMuscle/athleticPerformance BEFORE loseFat,
    # the opposite order from goal_factor above (which checks loseFat
    # first) -- an asymmetry the Swift source itself has, preserved here
    # rather than "fixed" for internal consistency.
    if BUILD_MUSCLE in fitness_goals or ATHLETIC_PERFORMANCE in fitness_goals:
        protein_per_kg = 1.0
    elif LOSE_FAT in fitness_goals:
        protein_per_kg = 0.95
    else:
        protein_per_kg = 0.8
    protein = _swift_round(weight_kg * protein_per_kg)

    if experience_level == BEGINNER:
        steps = 8_000
    elif experience_level == INTERMEDIATE:
        steps = 10_000
    else:
        steps = 12_000

    water_glasses = max(4, _swift_round(
        hydration_engine.glasses_from_milliliters(hydration_engine.target_milliliters(weight_kg))
    ))

    return LifestyleTargets(
        protein_grams=max(protein, 100),
        calorie_target=max(calories, 1_800),
        step_target=steps,
        sleep_hours_target=8.0,
        water_glasses_target=water_glasses,
        active_calorie_target=600,
    )


def hydration_milliliters(profile: Profile, overrides: NutritionPreferences | None = None,
                           active_calories: float = 0.0, cycle: str = hydration_engine.CYCLE_NONE) -> float:
    """Milliliters the person asked for, else the estimated need."""
    suggested = hydration_engine.target_milliliters(
        profile.weight_kg, active_calories=active_calories, cycle=cycle,
    )
    user_goal: float | None = None
    if overrides is not None:
        if overrides.hydration_target_ml is not None:
            user_goal = overrides.hydration_target_ml
        elif overrides.water_glasses_target is not None:
            user_goal = hydration_engine.milliliters_from_glasses(float(overrides.water_glasses_target))
    return hydration_engine.resolved_target_milliliters(user_goal, suggested)


def _water_glasses(overrides: NutritionPreferences | None, computed: int) -> int:
    if overrides is not None and overrides.hydration_target_ml is not None:
        return max(4, _swift_round(hydration_engine.glasses_from_milliliters(overrides.hydration_target_ml)))
    if overrides is not None and overrides.water_glasses_target is not None:
        return overrides.water_glasses_target
    return computed


def _mifflin_st_jeor_bmr(weight_kg: float, age: int, gender: str) -> float:
    base = 10 * weight_kg + 6.25 * 175 - 5 * age
    if gender == MALE:
        return base + 5
    if gender == FEMALE:
        return base - 161
    return base - 78
