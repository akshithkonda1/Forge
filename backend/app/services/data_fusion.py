"""Fuse persisted health, sleep, and workout data into a WellnessSnapshot."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from data.seed_data import today_iso
from services import readiness, scoring, timeseries_rollups
from storage import dynamodb, keys


_METRIC_FIELDS = (
    ("steps", "steps"),
    ("active-calories", "activeCalories"),
    ("resting-heart-rate", "restingHR"),
    ("hrv", "hrv"),
    ("oxygen-saturation", "oxygenSaturation"),
)


def _strip(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def _metric_for_day(user_id: str, metric_type: str, day: str) -> float | None:
    items = dynamodb.query_prefix(keys.user_pk(user_id), f"METRIC#{metric_type}#{day}")
    if not items:
        return None
    latest = max(items, key=lambda row: str(row.get("startedAt", "")))
    value = latest.get("value")
    return float(value) if value is not None else None


def _daily_row(user_id: str, day: str) -> dict[str, Any]:
    row: dict[str, Any] = {
        "date": day,
        "steps": 0,
        "activeCalories": 0,
        "hrv": 0,
        "restingHR": 0,
        "oxygenSaturation": None,
        "deepSleep": 0,
        "totalSleep": 0,
        "sleepScore": None,
        "sources": [],
    }
    sources: set[str] = set()

    for metric_type, field in _METRIC_FIELDS:
        value = _metric_for_day(user_id, metric_type, day)
        if value is not None:
            row[field] = int(value) if field in ("steps", "activeCalories", "restingHR") else value
            sources.add("metrics")

    sleep_items = dynamodb.query_prefix(keys.user_pk(user_id), f"SLEEP#{day}#")
    if sleep_items:
        latest = max(sleep_items, key=lambda row: str(row.get("source", "")))
        row["deepSleep"] = int(latest.get("deepMinutes", 0) or 0)
        row["totalSleep"] = int(float(latest.get("totalHours", 0) or 0) * 60)
        row["sleepScore"] = int(latest.get("score", 0) or 0)
        source = latest.get("source")
        if source:
            sources.add(str(source))

    row["sources"] = sorted(sources)
    return row


def load_wellness_snapshot(user_id: str, *, days: int = 14, date: str | None = None) -> dict[str, Any]:
    """Build a fused wellness snapshot with daily series and rollups."""
    anchor = date or today_iso()
    anchor_date = datetime.strptime(anchor[:10], "%Y-%m-%d").date()

    daily_series = []
    for offset in range(days - 1, -1, -1):
        day = (anchor_date - timedelta(days=offset)).isoformat()
        daily_series.append(_daily_row(user_id, day))

    today_row = daily_series[-1] if daily_series else _daily_row(user_id, anchor)

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    recent_sleep = [_strip(i) for i in sleep_items]

    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=14)
    recent_workouts = [_strip(i) for i in workout_items]

    hrv = today_row.get("hrv")
    readiness_block = readiness.compute_readiness(
        recent_sleep,
        hrv=float(hrv) if hrv else None,
    )

    return {
        "date": anchor,
        "today": today_row,
        "dailySeries": daily_series,
        "rollups": timeseries_rollups.build_metric_rollups(daily_series, end_date=anchor),
        "readiness": readiness_block,
        "trainingLoad": scoring.training_load_trend(recent_workouts),
        "recoveryTrend": scoring.recovery_trend(recent_sleep),
        "recentSleep": recent_sleep[:7],
        "recentWorkouts": recent_workouts[:7],
        "sources": sorted({s for row in daily_series for s in row.get("sources", [])}),
    }