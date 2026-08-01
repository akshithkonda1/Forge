"""Canonical biometric taxonomy — "sort the data into what it is".

Every incoming sample, from any source (Apple Health today; Oura / WHOOP /
Garmin / a glucose monitor tomorrow), is mapped onto one ``MetricType`` with a
single canonical unit, a physiological valid-range, and the body *system* it
informs. This registry is the source of truth the rest of the package reasons
over, so classification, statistics, estimation, and the body model never have
to special-case a provider's naming or units.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from enum import Enum
from typing import Any


class System(str, Enum):
    """Physiological system a metric informs (used for cross-signal fusion)."""

    CARDIOVASCULAR = "cardiovascular"
    AUTONOMIC = "autonomic"        # HRV, recovery — autonomic nervous system
    RESPIRATORY = "respiratory"
    METABOLIC = "metabolic"
    ACTIVITY = "activity"
    SLEEP = "sleep"
    BODY = "body"                  # composition
    NUTRITION = "nutrition"


class Kind(str, Enum):
    """How a sample relates to time — governs how it aggregates."""

    INSTANTANEOUS = "instantaneous"  # a point reading (HR now, BP now, weight)
    INTERVAL = "interval"            # spans a window (a sleep stage's minutes)
    CUMULATIVE = "cumulative"        # accrues over a day (steps, active energy)


class Agg(str, Enum):
    """Default aggregation when collapsing a window of samples to one value."""

    LATEST = "latest"
    MEAN = "mean"
    SUM = "sum"
    MIN = "min"
    MAX = "max"


class MetricType(str, Enum):
    # Cardiovascular
    HEART_RATE = "heart_rate"
    RESTING_HEART_RATE = "resting_heart_rate"
    BLOOD_PRESSURE_SYSTOLIC = "blood_pressure_systolic"
    BLOOD_PRESSURE_DIASTOLIC = "blood_pressure_diastolic"
    VO2_MAX = "vo2_max"
    # Autonomic
    HRV_SDNN = "hrv_sdnn"
    # Respiratory
    RESPIRATORY_RATE = "respiratory_rate"
    OXYGEN_SATURATION = "oxygen_saturation"
    # Metabolic
    BLOOD_GLUCOSE = "blood_glucose"
    BODY_TEMPERATURE = "body_temperature"
    # Activity
    STEPS = "steps"
    ACTIVE_ENERGY = "active_energy"
    DISTANCE = "distance"
    EXERCISE_MINUTES = "exercise_minutes"
    # Sleep
    SLEEP_DURATION = "sleep_duration"
    SLEEP_DEEP = "sleep_deep"
    SLEEP_REM = "sleep_rem"
    SLEEP_LIGHT = "sleep_light"
    SLEEP_AWAKE = "sleep_awake"
    SLEEP_EFFICIENCY = "sleep_efficiency"
    # Body composition
    BODY_MASS = "body_mass"
    BODY_FAT = "body_fat"
    LEAN_MASS = "lean_mass"
    # Nutrition
    DIETARY_ENERGY = "dietary_energy"
    DIETARY_PROTEIN = "dietary_protein"
    WATER = "water"


@dataclass(frozen=True)
class MetricSpec:
    unit: str                    # canonical unit
    low: float                   # physiologically plausible minimum (inclusive)
    high: float                  # physiologically plausible maximum (inclusive)
    system: System
    kind: Kind
    agg: Agg
    higher_is_better: bool | None = None  # for deviation interpretation; None = ambiguous


# The registry. Ranges are deliberately wide plausibility bounds for *rejecting
# impossible* samples, not clinical reference ranges (those live in estimators).
METRIC_REGISTRY: dict[MetricType, MetricSpec] = {
    MetricType.HEART_RATE: MetricSpec("bpm", 25, 250, System.CARDIOVASCULAR, Kind.INSTANTANEOUS, Agg.MEAN, False),
    MetricType.RESTING_HEART_RATE: MetricSpec("bpm", 25, 150, System.CARDIOVASCULAR, Kind.INSTANTANEOUS, Agg.LATEST, False),
    MetricType.BLOOD_PRESSURE_SYSTOLIC: MetricSpec("mmHg", 60, 260, System.CARDIOVASCULAR, Kind.INSTANTANEOUS, Agg.LATEST, False),
    MetricType.BLOOD_PRESSURE_DIASTOLIC: MetricSpec("mmHg", 30, 160, System.CARDIOVASCULAR, Kind.INSTANTANEOUS, Agg.LATEST, False),
    MetricType.VO2_MAX: MetricSpec("ml/kg/min", 10, 90, System.CARDIOVASCULAR, Kind.INSTANTANEOUS, Agg.LATEST, True),
    MetricType.HRV_SDNN: MetricSpec("ms", 1, 400, System.AUTONOMIC, Kind.INSTANTANEOUS, Agg.MEAN, True),
    MetricType.RESPIRATORY_RATE: MetricSpec("breaths/min", 4, 60, System.RESPIRATORY, Kind.INSTANTANEOUS, Agg.MEAN, False),
    MetricType.OXYGEN_SATURATION: MetricSpec("fraction", 0.5, 1.0, System.RESPIRATORY, Kind.INSTANTANEOUS, Agg.MEAN, True),
    MetricType.BLOOD_GLUCOSE: MetricSpec("mg/dL", 20, 600, System.METABOLIC, Kind.INSTANTANEOUS, Agg.MEAN, None),
    MetricType.BODY_TEMPERATURE: MetricSpec("celsius", 30, 45, System.METABOLIC, Kind.INSTANTANEOUS, Agg.LATEST, None),
    MetricType.STEPS: MetricSpec("count", 0, 200000, System.ACTIVITY, Kind.CUMULATIVE, Agg.SUM, True),
    MetricType.ACTIVE_ENERGY: MetricSpec("kcal", 0, 20000, System.ACTIVITY, Kind.CUMULATIVE, Agg.SUM, True),
    MetricType.DISTANCE: MetricSpec("m", 0, 500000, System.ACTIVITY, Kind.CUMULATIVE, Agg.SUM, True),
    MetricType.EXERCISE_MINUTES: MetricSpec("min", 0, 1440, System.ACTIVITY, Kind.CUMULATIVE, Agg.SUM, True),
    MetricType.SLEEP_DURATION: MetricSpec("min", 0, 1440, System.SLEEP, Kind.INTERVAL, Agg.SUM, True),
    MetricType.SLEEP_DEEP: MetricSpec("min", 0, 1440, System.SLEEP, Kind.INTERVAL, Agg.SUM, True),
    MetricType.SLEEP_REM: MetricSpec("min", 0, 1440, System.SLEEP, Kind.INTERVAL, Agg.SUM, True),
    MetricType.SLEEP_LIGHT: MetricSpec("min", 0, 1440, System.SLEEP, Kind.INTERVAL, Agg.SUM, None),
    MetricType.SLEEP_AWAKE: MetricSpec("min", 0, 1440, System.SLEEP, Kind.INTERVAL, Agg.SUM, False),
    MetricType.SLEEP_EFFICIENCY: MetricSpec("fraction", 0, 1, System.SLEEP, Kind.INSTANTANEOUS, Agg.LATEST, True),
    MetricType.BODY_MASS: MetricSpec("kg", 20, 500, System.BODY, Kind.INSTANTANEOUS, Agg.LATEST, None),
    MetricType.BODY_FAT: MetricSpec("fraction", 0.02, 0.75, System.BODY, Kind.INSTANTANEOUS, Agg.LATEST, False),
    MetricType.LEAN_MASS: MetricSpec("kg", 10, 200, System.BODY, Kind.INSTANTANEOUS, Agg.LATEST, True),
    MetricType.DIETARY_ENERGY: MetricSpec("kcal", 0, 20000, System.NUTRITION, Kind.CUMULATIVE, Agg.SUM, None),
    MetricType.DIETARY_PROTEIN: MetricSpec("g", 0, 500, System.NUTRITION, Kind.CUMULATIVE, Agg.SUM, True),
    MetricType.WATER: MetricSpec("mL", 0, 20000, System.NUTRITION, Kind.CUMULATIVE, Agg.SUM, True),
}


def spec(metric: MetricType) -> MetricSpec:
    return METRIC_REGISTRY[metric]


def metrics_for_system(system: System) -> list[MetricType]:
    return [m for m, s in METRIC_REGISTRY.items() if s.system == system]


@dataclass
class Observation:
    """One classified, unit-normalized sample on the canonical scale."""

    metric: MetricType
    value: float
    unit: str
    timestamp: datetime
    source: str = "unknown"
    confidence: float = 1.0          # 1.0 measured; < 1.0 derived/estimated
    meta: dict[str, Any] = field(default_factory=dict)

    @property
    def system(self) -> System:
        return METRIC_REGISTRY[self.metric].system

    def to_dict(self) -> dict[str, Any]:
        return {
            "metric": self.metric.value,
            "value": self.value,
            "unit": self.unit,
            "timestamp": self.timestamp.isoformat(),
            "source": self.source,
            "confidence": round(self.confidence, 3),
            "system": self.system.value,
            "meta": self.meta,
        }


def utcnow() -> datetime:
    return datetime.now(timezone.utc)
