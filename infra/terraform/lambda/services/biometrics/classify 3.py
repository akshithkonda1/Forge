"""Source-agnostic classification — turn any app's raw samples into typed,
unit-normalized ``Observation``s.

The same heart-rate reading arrives as ``"heart-rate"`` from our own client,
``"HKQuantityTypeIdentifierHeartRate"`` from Apple Health, and ``"hr"`` or
``"bpm"`` from a third-party export. This module collapses all of those onto
``MetricType.HEART_RATE`` on one canonical unit, so everything downstream
(statistics, estimators, the body model) is provider-blind. Unknown or
physiologically impossible samples are rejected with a reason rather than
silently dropped.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from .types import METRIC_REGISTRY, MetricType, Observation

# --- identifier -> MetricType -----------------------------------------------
# Keys are lowercased and stripped of the common HealthKit prefixes.
_ALIASES: dict[str, MetricType] = {
    # heart rate
    "heart_rate": MetricType.HEART_RATE, "heartrate": MetricType.HEART_RATE,
    "heart-rate": MetricType.HEART_RATE, "hr": MetricType.HEART_RATE, "bpm": MetricType.HEART_RATE,
    "resting_heart_rate": MetricType.RESTING_HEART_RATE, "resting-heart-rate": MetricType.RESTING_HEART_RATE,
    "restingheartrate": MetricType.RESTING_HEART_RATE, "rhr": MetricType.RESTING_HEART_RATE,
    # hrv
    "hrv": MetricType.HRV_SDNN, "heartratevariabilitysdnn": MetricType.HRV_SDNN,
    "hrv_sdnn": MetricType.HRV_SDNN, "sdnn": MetricType.HRV_SDNN, "rmssd": MetricType.HRV_SDNN,
    # blood pressure
    "blood_pressure_systolic": MetricType.BLOOD_PRESSURE_SYSTOLIC, "bloodpressuresystolic": MetricType.BLOOD_PRESSURE_SYSTOLIC,
    "systolic": MetricType.BLOOD_PRESSURE_SYSTOLIC, "bp_systolic": MetricType.BLOOD_PRESSURE_SYSTOLIC, "sbp": MetricType.BLOOD_PRESSURE_SYSTOLIC,
    "blood_pressure_diastolic": MetricType.BLOOD_PRESSURE_DIASTOLIC, "bloodpressurediastolic": MetricType.BLOOD_PRESSURE_DIASTOLIC,
    "diastolic": MetricType.BLOOD_PRESSURE_DIASTOLIC, "bp_diastolic": MetricType.BLOOD_PRESSURE_DIASTOLIC, "dbp": MetricType.BLOOD_PRESSURE_DIASTOLIC,
    # respiratory
    "respiratory_rate": MetricType.RESPIRATORY_RATE, "respiratoryrate": MetricType.RESPIRATORY_RATE,
    "respiration": MetricType.RESPIRATORY_RATE, "breathing_rate": MetricType.RESPIRATORY_RATE,
    "oxygen_saturation": MetricType.OXYGEN_SATURATION, "oxygensaturation": MetricType.OXYGEN_SATURATION,
    "spo2": MetricType.OXYGEN_SATURATION, "blood_oxygen": MetricType.OXYGEN_SATURATION,
    # metabolic
    "blood_glucose": MetricType.BLOOD_GLUCOSE, "bloodglucose": MetricType.BLOOD_GLUCOSE,
    "glucose": MetricType.BLOOD_GLUCOSE, "blood_sugar": MetricType.BLOOD_GLUCOSE,
    "body_temperature": MetricType.BODY_TEMPERATURE, "bodytemperature": MetricType.BODY_TEMPERATURE,
    "temperature": MetricType.BODY_TEMPERATURE, "temp": MetricType.BODY_TEMPERATURE,
    # activity
    "steps": MetricType.STEPS, "stepcount": MetricType.STEPS, "step_count": MetricType.STEPS,
    "active_energy": MetricType.ACTIVE_ENERGY, "active-calories": MetricType.ACTIVE_ENERGY,
    "activeenergyburned": MetricType.ACTIVE_ENERGY, "active_calories": MetricType.ACTIVE_ENERGY, "calories": MetricType.ACTIVE_ENERGY,
    "distance": MetricType.DISTANCE, "distancewalkingrunning": MetricType.DISTANCE,
    "exercise_minutes": MetricType.EXERCISE_MINUTES, "appleexercisetime": MetricType.EXERCISE_MINUTES, "exercise_time": MetricType.EXERCISE_MINUTES,
    "vo2max": MetricType.VO2_MAX, "vo2_max": MetricType.VO2_MAX,
    # body
    "body_mass": MetricType.BODY_MASS, "bodymass": MetricType.BODY_MASS, "body-weight": MetricType.BODY_MASS,
    "weight": MetricType.BODY_MASS, "body_weight": MetricType.BODY_MASS,
    "body_fat": MetricType.BODY_FAT, "bodyfatpercentage": MetricType.BODY_FAT, "body_fat_percentage": MetricType.BODY_FAT,
    "lean_mass": MetricType.LEAN_MASS, "leanbodymass": MetricType.LEAN_MASS,
    # nutrition
    "dietary_energy": MetricType.DIETARY_ENERGY, "dietaryenergyconsumed": MetricType.DIETARY_ENERGY, "calories_in": MetricType.DIETARY_ENERGY,
    "dietary_protein": MetricType.DIETARY_PROTEIN, "dietaryprotein": MetricType.DIETARY_PROTEIN, "protein": MetricType.DIETARY_PROTEIN,
    "water": MetricType.WATER, "dietarywater": MetricType.WATER, "hydration": MetricType.WATER,
    # sleep (duration; staged values handled separately)
    "sleep": MetricType.SLEEP_DURATION, "sleep_duration": MetricType.SLEEP_DURATION,
    "sleep_efficiency": MetricType.SLEEP_EFFICIENCY, "efficiency": MetricType.SLEEP_EFFICIENCY,
}

_SLEEP_STAGE_TYPES = {"sleep-stage", "sleep_stage", "sleepanalysis", "sleep_analysis", "hkcategorytypeidentifiersleepanalysis"}
_SLEEP_STAGE_MAP = {
    "deep": MetricType.SLEEP_DEEP, "rem": MetricType.SLEEP_REM, "core": MetricType.SLEEP_LIGHT,
    "light": MetricType.SLEEP_LIGHT, "awake": MetricType.SLEEP_AWAKE, "wake": MetricType.SLEEP_AWAKE,
    "asleep": MetricType.SLEEP_DURATION, "inbed": MetricType.SLEEP_DURATION, "in_bed": MetricType.SLEEP_DURATION,
}

# --- unit normalization to canonical ----------------------------------------
_LINEAR_CONVERSIONS: dict[MetricType, dict[str, float]] = {
    MetricType.BODY_MASS: {"kg": 1.0, "lb": 0.453592, "lbs": 0.453592, "g": 0.001, "st": 6.35029},
    MetricType.LEAN_MASS: {"kg": 1.0, "lb": 0.453592, "lbs": 0.453592, "g": 0.001},
    MetricType.DISTANCE: {"m": 1.0, "meter": 1.0, "meters": 1.0, "km": 1000.0, "mi": 1609.34, "mile": 1609.34, "miles": 1609.34, "ft": 0.3048, "feet": 0.3048},
    MetricType.HRV_SDNN: {"ms": 1.0, "s": 1000.0, "sec": 1000.0},
    MetricType.BLOOD_GLUCOSE: {"mg/dl": 1.0, "mg": 1.0, "mmol/l": 18.0182, "mmol": 18.0182},
    MetricType.ACTIVE_ENERGY: {"kcal": 1.0, "cal": 1.0, "kj": 0.239006},
    MetricType.DIETARY_ENERGY: {"kcal": 1.0, "cal": 1.0, "kj": 0.239006},
    MetricType.WATER: {"ml": 1.0, "l": 1000.0, "liter": 1000.0, "oz": 29.5735, "floz": 29.5735},
    MetricType.SLEEP_DURATION: {"min": 1.0, "minutes": 1.0, "minute": 1.0, "h": 60.0, "hr": 60.0, "hour": 60.0, "hours": 60.0, "s": 1.0 / 60.0, "sec": 1.0 / 60.0},
}
_FRACTION_TYPES = {MetricType.OXYGEN_SATURATION, MetricType.SLEEP_EFFICIENCY, MetricType.BODY_FAT}
for _m in (MetricType.SLEEP_DEEP, MetricType.SLEEP_REM, MetricType.SLEEP_LIGHT, MetricType.SLEEP_AWAKE):
    _LINEAR_CONVERSIONS[_m] = _LINEAR_CONVERSIONS[MetricType.SLEEP_DURATION]


@dataclass
class Reject:
    raw: Any
    reason: str

    def to_dict(self) -> dict[str, Any]:
        return {"reason": self.reason, "raw": self.raw}


@dataclass
class ClassificationResult:
    observations: list[Observation] = field(default_factory=list)
    rejects: list[Reject] = field(default_factory=list)

    def by_type(self) -> dict[MetricType, list[Observation]]:
        grouped: dict[MetricType, list[Observation]] = {}
        for obs in self.observations:
            grouped.setdefault(obs.metric, []).append(obs)
        return grouped

    @property
    def counts(self) -> dict[str, int]:
        return {"accepted": len(self.observations), "rejected": len(self.rejects)}


def _identifier(raw: dict[str, Any]) -> str:
    for key in ("metric", "metricType", "type", "identifier", "name", "dataType", "quantityType"):
        if raw.get(key):
            return str(raw[key])
    return ""


def _norm_identifier(identifier: str) -> str:
    key = identifier.strip().lower()
    for prefix in ("hkquantitytypeidentifier", "hkcategorytypeidentifier", "hkdatatypeidentifier"):
        if key.startswith(prefix):
            key = key[len(prefix):]
    return key.replace("-", "_").replace(" ", "_")


def _value(raw: dict[str, Any]) -> float | None:
    for key in ("value", "quantity", "amount", "qty"):
        if raw.get(key) is not None:
            try:
                return float(raw[key])
            except (TypeError, ValueError):
                return None
    return None


def _timestamp(raw: dict[str, Any]) -> datetime:
    """Always returns a timezone-aware datetime. Samples fused from different
    sources mix tz-aware and tz-naive strings; normalizing here keeps the
    chronological sort in classify_batch from raising on the comparison."""
    for key in ("timestamp", "startedAt", "startDate", "start", "date", "time"):
        val = raw.get(key)
        if isinstance(val, datetime):
            return val if val.tzinfo else val.replace(tzinfo=timezone.utc)
        if isinstance(val, str) and val:
            try:
                dt = datetime.fromisoformat(val.replace("Z", "+00:00"))
            except ValueError:
                continue
            return dt if dt.tzinfo else dt.replace(tzinfo=timezone.utc)
    return datetime.now(timezone.utc)


def _source(raw: dict[str, Any]) -> str:
    for key in ("source", "provider", "app", "device", "sourceName"):
        if raw.get(key):
            return str(raw[key])
    return "unknown"


def _resolve_type(raw: dict[str, Any], identifier: str) -> MetricType | None:
    norm = _norm_identifier(identifier)
    if norm in _SLEEP_STAGE_TYPES:
        meta = raw.get("metadata") if isinstance(raw.get("metadata"), dict) else {}
        stage = str(raw.get("stage") or raw.get("category") or meta.get("stage") or "").strip().lower()
        return _SLEEP_STAGE_MAP.get(stage.replace(" ", "_"))
    return _ALIASES.get(norm)


def _normalize_value(metric: MetricType, value: float, unit: str) -> float:
    unit = unit.strip().lower().replace("percent", "%")
    if metric in _FRACTION_TYPES:
        if unit in ("%", "pct") or value > 1.5:  # 97 (%) vs 0.97 (fraction)
            return value / 100.0
        return value
    if metric == MetricType.BODY_TEMPERATURE:
        if unit in ("f", "fahrenheit", "degf") or value > 50:  # 98.6F vs 37C
            return round((value - 32.0) * 5.0 / 9.0, 3)
        return value
    table = _LINEAR_CONVERSIONS.get(metric)
    if table is not None:
        factor = table.get(unit)
        if factor is not None:
            return value * factor
    return value


def classify_sample(raw: dict[str, Any]) -> Observation | Reject:
    if not isinstance(raw, dict):
        return Reject(raw, "sample is not an object")

    identifier = _identifier(raw)
    if not identifier:
        return Reject(raw, "no metric identifier")

    metric = _resolve_type(raw, identifier)
    if metric is None:
        return Reject(raw, f"unrecognized metric '{identifier}'")

    value = _value(raw)
    if value is None:
        return Reject(raw, f"missing/invalid value for '{identifier}'")

    spec = METRIC_REGISTRY[metric]
    normalized = _normalize_value(metric, value, str(raw.get("unit", "")))

    if not (spec.low <= normalized <= spec.high):
        return Reject(raw, f"{metric.value}={normalized} outside plausible range [{spec.low}, {spec.high}]")

    return Observation(
        metric=metric,
        value=round(normalized, 4),
        unit=spec.unit,
        timestamp=_timestamp(raw),
        source=_source(raw),
        confidence=1.0,
        meta={k: raw[k] for k in ("device", "endedAt", "context") if k in raw},
    )


def classify_batch(raw_samples: list[Any]) -> ClassificationResult:
    result = ClassificationResult()
    for raw in raw_samples or []:
        outcome = classify_sample(raw)
        if isinstance(outcome, Observation):
            result.observations.append(outcome)
        else:
            result.rejects.append(outcome)
    # Chronological order keeps trend/streaming math correct.
    result.observations.sort(key=lambda o: o.timestamp)
    return result
