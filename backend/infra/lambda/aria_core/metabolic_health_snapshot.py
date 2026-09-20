"""MetabolicHealthSnapshot — meals + macros + glucose as one story.

Python port of ForgeCore's ``MetabolicHealthSnapshot.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/MetabolicHealthSnapshot.swift``),
kept numerically/textually identical to it: the meal <-> glucose pairing
algorithm, its response copy, and the honest "sold separately" accessory
framing are all carried over line for line and word for word.

Oura's metabolic wedge is meals, a nutritional breakdown, and glucose from
a CGM sold separately. Forge already logs meals; this is the missing meal
<-> glucose sentence — lifestyle copy, never a diagnosis (see
``testCopyNeverClaimsDiagnosis`` in the Swift suite, translated here too).

Ported: ``GlucosePoint``, ``MetabolicMealEvent``, ``MealGlucosePair``,
``MetabolicHealthSnapshot``, ``evaluate()``, the meal/glucose pairing
(``_pair_meals``/``_pair_line``), ``_build_story_line()``,
``accessory_line()``, ``_is_cgm_source()``, ``_cleaned_source()``.

Reduced, not ported, on purpose: Swift's ``accessoryLine`` /
``connectedMetabolicName`` take raw connected-device IDs and resolve a
human-readable name through ``HealthDeviceCatalog`` -- a large (400+
line), separately-maintained product registry (generation retention
cycles, remote rows, HealthKit discoveries) that is its own subsystem, not
part of "meal/glucose pairing." This port's ``accessory_line()`` instead
takes an already-resolved ``connected_metabolic_device_name: str | None``
directly; a caller that has the device catalog available resolves the
name itself before calling in. The two string constants
``TranslationCatalog`` supplies (``metabolicAccessoryNote``, the metabolic
pillar's four bullets) are copied here directly rather than porting all of
``TranslationCatalog`` (which also covers sleep/train/stress/women's-health
pillar copy unrelated to this task).

Stdlib only. Deterministic (given `now`). Pure -- no I/O.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timedelta

# --- Catalog copy --------------------------------------------------------
# Mirrors the two TranslationCatalog constants this file reads
# (TranslationCatalog.swift L34-35, L61-72) -- not the full catalog.

SOLD_SEPARATELY_LINE = (
    "Glucose via Stelo, Dexcom, Lingo, or Libre — sold separately. "
    "Forge reads it after you share it into Apple Health."
)

METABOLIC_BULLETS: tuple[str, ...] = (
    "Meals you logged",
    "Nutritional breakdown",
    "Hydration",
    "Glucose from a CGM",
)

_CGM_SOURCE_MARKERS = ("dexcom", "stelo", "libre", "librelink", "lingo", "abbott", "glucose")


def _swift_round(value: float) -> int:
    """Swift's ``Double.rounded()`` default rule: round half away from
    zero, not Python's banker's-rounding ``round()``."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


# --- Inputs ------------------------------------------------------------------
# Mirrors GlucosePoint (Swift L6-16) and MetabolicMealEvent (Swift L19-42).

@dataclass(frozen=True)
class GlucosePoint:
    """One blood-glucose reading, already converted to mg/dL.

    Lifestyle comparison only — never a glycemic diagnosis."""

    date: datetime
    mgdl: float
    source_name: str = ""


@dataclass(frozen=True)
class MetabolicMealEvent:
    """A logged meal used to pair carbs with the glucose that followed."""

    name: str
    date: datetime
    calories: float
    carbs: float
    protein: float = 0.0
    fat: float = 0.0


# --- Outputs -----------------------------------------------------------
# Mirrors MealGlucosePair (Swift L45-71) and MetabolicHealthSnapshot
# (Swift L78-174).

@dataclass(frozen=True)
class MealGlucosePair:
    """One meal and the glucose that showed up after it."""

    meal_name: str
    meal_date: datetime
    carbs: float
    calories: float
    peak_mgdl: float | None
    delta_mgdl: float | None
    line: str


@dataclass(frozen=True)
class MetabolicHealthSnapshot:
    latest_mgdl: float | None
    latest_date: datetime | None
    latest_source: str | None
    meal_count: int
    carbs_grams: float
    protein_grams: float
    fat_grams: float
    calories: float
    story_line: str
    accessory_line: str
    pairs: tuple[MealGlucosePair, ...]
    bullets: tuple[str, ...]

    @property
    def has_glucose(self) -> bool:
        return self.latest_mgdl is not None


EMPTY = MetabolicHealthSnapshot(
    latest_mgdl=None,
    latest_date=None,
    latest_source=None,
    meal_count=0,
    carbs_grams=0.0,
    protein_grams=0.0,
    fat_grams=0.0,
    calories=0.0,
    story_line="",
    accessory_line=SOLD_SEPARATELY_LINE,
    pairs=(),
    bullets=METABOLIC_BULLETS,
)


def evaluate(meals: list[MetabolicMealEvent], glucose: list[GlucosePoint],
             day_carbs: float | None = None, day_protein: float | None = None,
             day_fat: float | None = None, day_calories: float | None = None,
             connected_metabolic_device_name: str | None = None,
             now: datetime | None = None) -> MetabolicHealthSnapshot:
    if now is None:
        now = datetime.now()
    day_start = now.replace(hour=0, minute=0, second=0, microsecond=0)

    today_meals = sorted(
        (m for m in meals if day_start <= m.date <= now),
        key=lambda m: m.date, reverse=True,
    )
    readings = sorted(
        (g for g in glucose if 40 <= g.mgdl <= 400),
        key=lambda g: g.date, reverse=True,
    )
    latest = readings[0] if readings else None

    carbs = day_carbs if day_carbs is not None else sum(m.carbs for m in today_meals)
    protein = day_protein if day_protein is not None else sum(m.protein for m in today_meals)
    fat = day_fat if day_fat is not None else sum(m.fat for m in today_meals)
    calories = day_calories if day_calories is not None else sum(m.calories for m in today_meals)

    pairs = _pair_meals(today_meals, readings)
    accessory = accessory_line(connected_metabolic_device_name, latest.source_name if latest else None)
    story = _build_story_line(latest, today_meals, pairs, accessory)

    return MetabolicHealthSnapshot(
        latest_mgdl=(_swift_round(latest.mgdl * 10) / 10) if latest else None,
        latest_date=latest.date if latest else None,
        latest_source=_cleaned_source(latest.source_name) if latest else None,
        meal_count=len(today_meals),
        carbs_grams=_swift_round(carbs * 10) / 10,
        protein_grams=_swift_round(protein * 10) / 10,
        fat_grams=_swift_round(fat * 10) / 10,
        calories=float(_swift_round(calories)),
        story_line=story,
        accessory_line=accessory,
        pairs=tuple(pairs),
        bullets=METABOLIC_BULLETS,
    )


def accessory_line(connected_metabolic_device_name: str | None, latest_source: str | None) -> str:
    source = _cleaned_source(latest_source)
    if source is not None and _is_cgm_source(source):
        return f"Glucose is coming from {source} through Apple Health."
    if connected_metabolic_device_name:
        return (f"{connected_metabolic_device_name} is selected. Open its app and share Blood Glucose "
                f"with Apple Health. The sensor is sold separately.")
    return SOLD_SEPARATELY_LINE


# --- Pairing -----------------------------------------------------------
# Mirrors pairMeals/pairLine (Swift L178-226).

def _pair_meals(meals: list[MetabolicMealEvent], glucose: list[GlucosePoint]) -> list[MealGlucosePair]:
    out: list[MealGlucosePair] = []
    for meal in meals:
        pre_window = [
            g for g in glucose
            if meal.date - timedelta(minutes=45) <= g.date <= meal.date + timedelta(minutes=5)
        ]
        post_window = [
            g for g in glucose
            if meal.date + timedelta(minutes=20) <= g.date <= meal.date + timedelta(minutes=150)
        ]
        if not post_window:
            continue

        peak = max(g.mgdl for g in post_window)
        pre_sorted = sorted(pre_window, key=lambda g: g.date, reverse=True)
        baseline = pre_sorted[0].mgdl if pre_sorted else None
        delta = (peak - baseline) if baseline is not None else None
        out.append(MealGlucosePair(
            meal_name=meal.name,
            meal_date=meal.date,
            carbs=meal.carbs,
            calories=meal.calories,
            peak_mgdl=float(_swift_round(peak)),
            delta_mgdl=float(_swift_round(delta)) if delta is not None else None,
            line=_pair_line(meal.name, meal.carbs, peak, delta),
        ))
    return out


def _pair_line(name: str, carbs: float, peak: float | None, delta: float | None) -> str:
    meal = name.strip()
    title = meal if meal else "Meal"
    carb_bit = f" · {_swift_round(carbs)}g carbs" if carbs > 0 else ""
    if peak is not None and delta is not None:
        change = _swift_round(abs(delta))
        if delta >= 8:
            return f"{title}{carb_bit} · glucose rose {change} mg/dL after."
        if delta <= -8:
            return f"{title}{carb_bit} · glucose eased {change} mg/dL after."
        return f"{title}{carb_bit} · glucose held near {_swift_round(peak)} mg/dL after."
    if peak is not None:
        return f"{title}{carb_bit} · {_swift_round(peak)} mg/dL after the meal."
    return f"{title}{carb_bit}."


def _build_story_line(latest: GlucosePoint | None, meals: list[MetabolicMealEvent],
                       pairs: list[MealGlucosePair], accessory: str) -> str:
    if pairs:
        return pairs[0].line
    if latest is not None:
        value = _swift_round(latest.mgdl)
        if not meals:
            return f"Latest glucose {value} mg/dL. Log a meal to see how food lands."
        noun = "meal" if len(meals) == 1 else "meals"
        return f"Latest glucose {value} mg/dL. {len(meals)} {noun} today — waiting on a post-meal reading."
    if meals:
        noun = "meal" if len(meals) == 1 else "meals"
        return f"{len(meals)} {noun} logged. {accessory}"
    return "Log a meal. A glucose sensor, sold separately, turns that into a meal ↔ glucose story."


def _is_cgm_source(name: str) -> bool:
    folded = name.lower()
    return any(marker in folded for marker in _CGM_SOURCE_MARKERS)


def _cleaned_source(raw: str | None) -> str | None:
    trimmed = (raw or "").strip()
    return trimmed if trimmed else None
