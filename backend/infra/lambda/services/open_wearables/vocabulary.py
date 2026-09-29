"""Kebab-case, SI-aligned metric vocabulary for Open Wearables → Forge.

Open Wearables uses snake_case type names (``heart_rate``, ``active_energy``).
Forge ingest (``POST /health/batch``) and the iOS/web contracts use kebab-case
(``heart-rate``, ``active-calories``). ARIA classification already accepts both
spellings; this module is the single mapping table so a new provider type is
added once.

Units are SI-aligned: kg, m, s, °C, plus the clinical conventions the rest of
Forge already stores (bpm = min⁻¹, kcal, ms). ``/health/batch`` still persists
``body-weight`` in pounds today — the adapter emits kilograms and lets that
route's existing converter run at the boundary. See
``docs/open-wearables-integration.md``.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class ForgeMetricSpec:
    """One canonical Forge metric."""

    name: str
    unit: str
    batch_name: str | None
    batch_unit: str | None
    kind: str  # instantaneous | interval | cumulative


# batch_name is the /health/batch allowlist spelling, or None when the sample
# should only go through /ai/observe (richer taxonomy).
FORGE_METRICS: dict[str, ForgeMetricSpec] = {
    "heart-rate": ForgeMetricSpec("heart-rate", "bpm", "heart-rate", "bpm", "instantaneous"),
    "resting-heart-rate": ForgeMetricSpec(
        "resting-heart-rate", "bpm", "resting-heart-rate", "bpm", "instantaneous"
    ),
    "hrv-sdnn": ForgeMetricSpec("hrv-sdnn", "ms", "hrv", "ms", "instantaneous"),
    "hrv-rmssd": ForgeMetricSpec("hrv-rmssd", "ms", None, None, "instantaneous"),
    "hrv": ForgeMetricSpec("hrv", "ms", "hrv", "ms", "instantaneous"),
    "steps": ForgeMetricSpec("steps", "count", "steps", "count", "cumulative"),
    "active-energy": ForgeMetricSpec(
        "active-energy", "kcal", "active-calories", "kcal", "cumulative"
    ),
    "basal-energy": ForgeMetricSpec("basal-energy", "kcal", None, None, "cumulative"),
    "body-mass": ForgeMetricSpec("body-mass", "kg", "body-weight", "kg", "instantaneous"),
    "body-fat": ForgeMetricSpec("body-fat", "fraction", None, None, "instantaneous"),
    "lean-mass": ForgeMetricSpec("lean-mass", "kg", None, None, "instantaneous"),
    "distance": ForgeMetricSpec("distance", "m", "distance", "meters", "cumulative"),
    "vo2-max": ForgeMetricSpec("vo2-max", "ml/kg/min", "vo2-max", "ml/kg/min", "instantaneous"),
    "oxygen-saturation": ForgeMetricSpec(
        "oxygen-saturation", "fraction", None, None, "instantaneous"
    ),
    "respiratory-rate": ForgeMetricSpec(
        "respiratory-rate", "breaths/min", None, None, "instantaneous"
    ),
    "blood-glucose": ForgeMetricSpec("blood-glucose", "mg/dL", None, None, "instantaneous"),
    "blood-pressure-systolic": ForgeMetricSpec(
        "blood-pressure-systolic", "mmHg", None, None, "instantaneous"
    ),
    "blood-pressure-diastolic": ForgeMetricSpec(
        "blood-pressure-diastolic", "mmHg", None, None, "instantaneous"
    ),
    "body-temperature": ForgeMetricSpec("body-temperature", "C", None, None, "instantaneous"),
    "skin-temperature": ForgeMetricSpec("skin-temperature", "C", None, None, "instantaneous"),
    "exercise-minutes": ForgeMetricSpec(
        "exercise-minutes", "min", None, None, "cumulative"
    ),
    "sleep-duration": ForgeMetricSpec("sleep-duration", "s", None, None, "interval"),
    "sleep-deep": ForgeMetricSpec("sleep-deep", "s", "sleep-stage", "minutes", "interval"),
    "sleep-rem": ForgeMetricSpec("sleep-rem", "s", "sleep-stage", "minutes", "interval"),
    "sleep-light": ForgeMetricSpec("sleep-light", "s", "sleep-stage", "minutes", "interval"),
    "sleep-awake": ForgeMetricSpec("sleep-awake", "s", "sleep-stage", "minutes", "interval"),
    "sleep-efficiency": ForgeMetricSpec(
        "sleep-efficiency", "fraction", None, None, "instantaneous"
    ),
    "fitness-age": ForgeMetricSpec("fitness-age", "years", "fitness-age", "years", "instantaneous"),
    "cardio-age": ForgeMetricSpec("cardio-age", "years", "cardio-age", "years", "instantaneous"),
}


# Open Wearables snake_case type → Forge kebab-case name.
_OW_TYPE_TO_FORGE: dict[str, str] = {
    "heart_rate": "heart-rate",
    "resting_heart_rate": "resting-heart-rate",
    "heart_rate_variability_sdnn": "hrv-sdnn",
    "heart_rate_variability_rmssd": "hrv-rmssd",
    "hrv": "hrv",
    "steps": "steps",
    "active_energy": "active-energy",
    "energy": "active-energy",
    "basal_energy": "basal-energy",
    "weight": "body-mass",
    "body_fat_percentage": "body-fat",
    "lean_body_mass": "lean-mass",
    "distance_walking_running": "distance",
    "distance_cycling": "distance",
    "distance_swimming": "distance",
    "distance_other": "distance",
    "vo2_max": "vo2-max",
    "oxygen_saturation": "oxygen-saturation",
    "respiratory_rate": "respiratory-rate",
    "blood_glucose": "blood-glucose",
    "blood_pressure_systolic": "blood-pressure-systolic",
    "blood_pressure_diastolic": "blood-pressure-diastolic",
    "body_temperature": "body-temperature",
    "skin_temperature": "skin-temperature",
    "exercise_time": "exercise-minutes",
    "garmin_fitness_age": "fitness-age",
    "cardiovascular_age": "cardio-age",
    "sleep_duration": "sleep-duration",
    "sleep_efficiency": "sleep-efficiency",
}


_SLEEP_STAGE_TO_FORGE: dict[str, str] = {
    "deep": "sleep-deep",
    "rem": "sleep-rem",
    "light": "sleep-light",
    "core": "sleep-light",
    "awake": "sleep-awake",
    "wake": "sleep-awake",
}


def map_open_wearables_type(ow_type: str, *, stage: str | None = None) -> ForgeMetricSpec | None:
    """Return the Forge spec for an Open Wearables type, or None if unmapped."""
    key = (ow_type or "").strip().lower().replace("-", "_").replace(" ", "_")
    if key in {"sleep_stage", "sleep_analysis"} and stage:
        mapped = _SLEEP_STAGE_TO_FORGE.get(stage.strip().lower())
        return FORGE_METRICS.get(mapped) if mapped else None
    forge_name = _OW_TYPE_TO_FORGE.get(key)
    if not forge_name:
        return None
    return FORGE_METRICS[forge_name]


def sleep_stage_spec(stage: str) -> ForgeMetricSpec | None:
    mapped = _SLEEP_STAGE_TO_FORGE.get((stage or "").strip().lower())
    return FORGE_METRICS.get(mapped) if mapped else None
