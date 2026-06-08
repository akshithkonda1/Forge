from __future__ import annotations

from typing import Any

from data.seed_data import today_iso
from core.seed_policy import empty_daily_metrics
from storage import dynamodb, keys


_METRIC_FIELDS = (
    ("steps", "steps"),
    ("active-calories", "activeCalories"),
    ("resting-heart-rate", "restingHR"),
    ("hrv", "hrv"),
)


def load_daily_metrics(user_id: str, date: str | None = None) -> dict[str, Any]:
    """Build daily metrics from persisted METRIC# rows, or an empty snapshot in production."""
    target_date = date or today_iso()
    metrics = empty_daily_metrics()
    metrics["date"] = target_date
    sources: set[str] = set()

    for metric_type, field in _METRIC_FIELDS:
        items = dynamodb.query_prefix(keys.user_pk(user_id), f"METRIC#{metric_type}#{target_date}")
        if not items:
            continue
        item = max(items, key=lambda row: str(row.get("startedAt", "")))
        metrics[field] = item.get("value", metrics[field])
        source = item.get("source")
        if source:
            sources.add(str(source))

    sleep_items = dynamodb.query_prefix(keys.user_pk(user_id), f"SLEEP#{target_date}#")
    if sleep_items:
        latest = max(sleep_items, key=lambda row: str(row.get("source", "")))
        metrics["deepSleep"] = int(latest.get("deepMinutes", 0) or 0)
        metrics["totalSleep"] = int((float(latest.get("totalHours", 0) or 0)) * 60)
        source = latest.get("source")
        if source:
            sources.add(str(source))

    metrics["sources"] = sorted(sources)
    return metrics