from __future__ import annotations

from typing import Any

# Canonical units per metric type.
_CANONICAL_UNIT: dict[str, str] = {
    "steps": "count",
    "active-calories": "kcal",
    "hrv": "ms",
    "resting-heart-rate": "bpm",
    "heart-rate": "bpm",
    "sleep-stage": "minutes",
    "body-weight": "lbs",
    "distance": "meters",
}

# Conversion factors: (from_unit -> multiplier to reach canonical unit)
_CONVERSIONS: dict[str, dict[str, float]] = {
    "body-weight": {
        "kg": 2.20462,
        "lbs": 1.0,
        "lb": 1.0,
    },
    "distance": {
        "meters": 1.0,
        "m": 1.0,
        "km": 1000.0,
        "miles": 1609.34,
        "mi": 1609.34,
        "feet": 0.3048,
        "ft": 0.3048,
    },
    "hrv": {
        "ms": 1.0,
        "s": 1000.0,
    },
}


def normalize_metric(metric: dict[str, Any]) -> dict[str, Any]:
    """Return a copy of metric with value and unit normalized to canonical form."""
    result = dict(metric)
    metric_type = metric.get("metricType", "")
    raw_unit = str(metric.get("unit", "")).lower().strip()
    value = metric.get("value", 0)

    is_numeric = isinstance(value, (int, float)) and not isinstance(value, bool)

    canonical = _CANONICAL_UNIT.get(metric_type)
    if canonical and metric_type in _CONVERSIONS and is_numeric:
        factor = _CONVERSIONS[metric_type].get(raw_unit)
        if factor is not None and factor != 1.0:
            result["originalValue"] = value
            result["originalUnit"] = metric.get("unit")
            result["value"] = round(value * factor, 4)

    if canonical:
        result["unit"] = canonical

    return result
