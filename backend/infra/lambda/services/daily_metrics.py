"""Aggregate a day's ingested health samples into the dashboard's metric row.

``POST /health/batch`` has always persisted samples under ``METRIC#{type}#{startedAt}``,
but nothing read them back: ``/dashboard/today`` returned a fixture unconditionally.
This module is that missing read.
"""

from __future__ import annotations

from typing import Any

from seed_data import today_iso
from storage import dynamodb, keys

# Counters that accumulate over a day (a step is never un-taken) versus
# instantaneous measures that are averaged.
_CUMULATIVE = {"steps": "steps", "active-calories": "activeCalories"}
_INSTANTANEOUS = {"hrv": "hrv", "resting-heart-rate": "restingHR"}


def _samples(user_id: str, metric_type: str, day: str) -> list[dict[str, Any]]:
    return dynamodb.query_prefix(keys.user_pk(user_id), f"METRIC#{metric_type}#{day}")


def _numeric(samples: list[dict[str, Any]]) -> list[float]:
    values = []
    for s in samples:
        v = s.get("value")
        if isinstance(v, bool) or not isinstance(v, (int, float)):
            continue
        values.append(float(v))
    return values


def _cumulative_total(values: list[float]) -> int | None:
    """Take the largest reading rather than the sum.

    A source may upload either per-interval deltas or a running day total, and
    the batch endpoint accepts both without distinguishing them. Summing running
    totals inflates the figure several-fold; taking the maximum is exact for a
    running total and merely conservative for deltas. In a health app an
    understated step count is a much cheaper error than an invented one.
    """
    if not values:
        return None
    return int(round(max(values)))


def _average(values: list[float]) -> int | None:
    if not values:
        return None
    return int(round(sum(values) / len(values)))


def load_daily_metrics(user_id: str, day: str | None = None) -> dict[str, Any] | None:
    """Today's metrics from ingested samples, or ``None`` if nothing was ingested.

    ``recent_sleep`` is not read here; the caller already holds it and supplies
    the sleep minutes, so this stays a single-purpose read of the metric store.
    """
    day = day or today_iso()

    row: dict[str, Any] = {"date": day}
    sources: set[str] = set()
    seen_any = False

    for metric_type, field in {**_CUMULATIVE, **_INSTANTANEOUS}.items():
        samples = _samples(user_id, metric_type, day)
        values = _numeric(samples)
        if metric_type in _CUMULATIVE:
            row[field] = _cumulative_total(values)
        else:
            row[field] = _average(values)
        if values:
            seen_any = True
        for s in samples:
            source = s.get("source")
            if isinstance(source, str) and source:
                sources.add(source)

    if not seen_any:
        return None

    row["sources"] = sorted(sources)
    return row


def apply_sleep_minutes(row: dict[str, Any], recent_sleep: list[dict[str, Any]]) -> dict[str, Any]:
    """Fill deepSleep/totalSleep from the most recent night, if one exists."""
    latest = recent_sleep[0] if recent_sleep else None

    deep = latest.get("deepMinutes") if isinstance(latest, dict) else None
    row["deepSleep"] = int(round(deep)) if isinstance(deep, (int, float)) and not isinstance(deep, bool) else None

    hours = latest.get("totalHours") if isinstance(latest, dict) else None
    if isinstance(hours, (int, float)) and not isinstance(hours, bool):
        row["totalSleep"] = int(round(float(hours) * 60))
    else:
        row["totalSleep"] = None

    return row
