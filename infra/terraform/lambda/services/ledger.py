"""Phase 2 ledger — ingest lands, readiness persists, ARIA gets real context."""

from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any

from seed_data import today_iso
from services import readiness as readiness_service
from services import source_map
from services.aria_context import CoachContextEngine
from storage import dynamodb, keys

_context = CoachContextEngine()


def strip(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def load_sleep(user_id: str, days: int = 14) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=days)
    return [strip(item) for item in items]


def load_workouts(user_id: str, days: int = 30) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=days)
    return [strip(item) for item in items]


def load_metrics(user_id: str, limit: int = 80) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "METRIC#", limit=limit)
    return [strip(item) for item in items]


def load_profile(user_id: str) -> dict[str, Any]:
    item = dynamodb.get_item(**keys.profile_key(user_id))
    return strip(item) if item else {}


def latest_metric(metrics: list[dict[str, Any]], metric_type: str) -> float | None:
    for row in metrics:
        if row.get("metricType") == metric_type:
            try:
                return float(row.get("value"))
            except (TypeError, ValueError):
                return None
    return None


def persist_readiness(user_id: str, sleep_records: list[dict[str, Any]], hrv: float | None) -> dict[str, Any]:
    computed = readiness_service.compute_readiness(sleep_records, hrv=hrv)
    computed["date"] = today_iso()
    computed["persisted"] = True
    dynamodb.put_item({**keys.readiness_key(user_id, today_iso()), **computed})
    return computed


def connected_device_ids(profile: dict[str, Any]) -> list[str]:
    raw = profile.get("connectedDevices") or []
    if not isinstance(raw, list):
        return []
    return [str(item) for item in raw if str(item).strip()]


def refresh_after_ingest(user_id: str) -> dict[str, Any]:
    """Recompute the day's ledger after HealthKit / sleep / workout writes."""
    sleep_records = load_sleep(user_id)
    workouts = load_workouts(user_id)
    metrics = load_metrics(user_id)
    profile = load_profile(user_id)
    hrv = latest_metric(metrics, "hrv")
    readiness = persist_readiness(user_id, sleep_records, hrv)

    for row in metrics[:20]:
        source_map.record_seen(
            user_id,
            str(row.get("source") or "apple-health"),
            metric_type=str(row.get("metricType") or ""),
            at=str(row.get("startedAt") or datetime.now(timezone.utc).isoformat()),
            value=row.get("value"),
        )
    for row in sleep_records[:5]:
        source_map.record_seen(
            user_id,
            str(row.get("source") or "apple-health"),
            metric_type="sleep-hours",
            at=str(row.get("date") or today_iso()),
            value=row.get("score") or row.get("totalHours"),
        )

    connected = connected_device_ids(profile)
    sources = source_map.snapshot(user_id, connected)
    recent = {
        "readiness": float(readiness.get("overall") or 0),
        "sleep_score": float((sleep_records[0] if sleep_records else {}).get("score") or 0),
        "hrv": float(hrv or 0),
        "workouts_7d": float(len(workouts[:7])),
    }
    rich = _context.build_rich_context(user_id, recent)
    if sources["lines"]:
        _context.add_insight(user_id, sources["lines"][0])

    dynamodb.put_item(
        {
            **keys.daily_metrics_key(user_id, today_iso()),
            "date": today_iso(),
            "readiness": readiness.get("overall"),
            "sleepScore": recent["sleep_score"],
            "hrv": hrv,
            "steps": latest_metric(metrics, "steps"),
            "water": latest_metric(metrics, "dietary-water"),
            "activeCalories": latest_metric(metrics, "active-calories"),
            "refreshedAt": datetime.now(timezone.utc).isoformat(),
        }
    )
    return {
        "date": today_iso(),
        "readiness": readiness,
        "sources": sources,
        "context": rich,
        "sleepNights": len(sleep_records),
        "workouts": len(workouts),
    }


def monday_of(day: date | None = None) -> str:
    stamp = day or date.today()
    return (stamp.fromordinal(stamp.toordinal() - stamp.weekday())).isoformat()
