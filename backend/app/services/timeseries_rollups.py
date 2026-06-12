"""Rolling time-series aggregates for wellness metrics."""
from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Any


def _parse_day(value: str) -> date | None:
    if not value:
        return None
    try:
        return date.fromisoformat(value[:10])
    except ValueError:
        return None


def _window_days(end_day: date, days: int) -> list[str]:
    return [(end_day - timedelta(days=offset)).isoformat() for offset in range(days - 1, -1, -1)]


def _avg(values: list[float]) -> float | None:
    if not values:
        return None
    return round(sum(values) / len(values), 2)


def _trend(current: float | None, previous: float | None) -> str:
    if current is None or previous is None:
        return "unknown"
    if previous == 0:
        return "rising" if current > 0 else "flat"
    delta_pct = (current - previous) / previous
    if delta_pct > 0.08:
        return "rising"
    if delta_pct < -0.08:
        return "falling"
    return "steady"


def build_metric_rollups(
    daily_rows: list[dict[str, Any]],
    *,
    end_date: str | None = None,
    windows: tuple[int, ...] = (7, 14),
) -> dict[str, Any]:
    """Compute rolling averages and trends for scalar daily metrics."""
    anchor = _parse_day(end_date or "") or datetime.now(timezone.utc).date()
    by_date: dict[str, dict[str, Any]] = {}
    for row in daily_rows:
        day = str(row.get("date") or "")
        if day:
            by_date[day] = row

    fields = (
        "steps",
        "activeCalories",
        "hrv",
        "restingHR",
        "oxygenSaturation",
        "deepSleep",
        "totalSleep",
        "sleepScore",
    )
    rollups: dict[str, Any] = {"anchorDate": anchor.isoformat(), "windows": {}}

    for window in windows:
        days = _window_days(anchor, window)
        prior_days = _window_days(anchor - timedelta(days=window), window)
        window_stats: dict[str, Any] = {}

        for field in fields:
            current_vals = [
                float(by_date[d][field])
                for d in days
                if d in by_date and by_date[d].get(field) is not None
            ]
            prior_vals = [
                float(by_date[d][field])
                for d in prior_days
                if d in by_date and by_date[d].get(field) is not None
            ]
            current_avg = _avg(current_vals)
            prior_avg = _avg(prior_vals)
            window_stats[field] = {
                "avg": current_avg,
                "priorAvg": prior_avg,
                "delta": round(current_avg - prior_avg, 2) if current_avg is not None and prior_avg is not None else None,
                "trend": _trend(current_avg, prior_avg),
                "coverageDays": len(current_vals),
            }

        rollups["windows"][str(window)] = window_stats

    return rollups