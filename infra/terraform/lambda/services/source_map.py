"""ARIA's source map — who wrote what, and who went silent.

Device-aware coaching names the writer. After a connect, the last 24 hours
show what landed in Health. A connected source silent for three days is called
out.
"""

from __future__ import annotations

from datetime import datetime, timedelta, timezone
from typing import Any

from storage import dynamodb, keys

COACH_NAME = "ARIA"
SILENCE_DAYS = 3

SOURCE_LABELS = {
    "apple-health": "Health",
    "apple-watch": "Apple Watch",
    "oura": "Oura",
    "whoop": "WHOOP",
    "garmin": "Garmin",
    "strava": "Strava",
    "larq": "LARQ",
    "hidratespark": "HidrateSpark",
    "eight-sleep": "Eight Sleep",
    "withings": "Withings",
    "polar": "Polar",
    "fitbit": "Fitbit",
    "coros": "COROS",
    "dexcom": "Dexcom",
    "ultrahuman": "Ultrahuman",
    "peloton": "Peloton",
    "nike": "Nike",
    "amazfit": "Amazfit",
    "manual": "You",
}

METRIC_LABELS = {
    "steps": "steps",
    "active-calories": "active calories",
    "hrv": "HRV",
    "resting-heart-rate": "resting heart rate",
    "heart-rate": "heart rate",
    "sleep-stage": "sleep",
    "sleep-hours": "sleep",
    "body-weight": "weight",
    "distance": "distance",
    "dietary-water": "water",
    "blood-glucose": "glucose",
    "mindful-minutes": "mindful minutes",
    "workout-load": "training",
}


def _now() -> datetime:
    return datetime.now(timezone.utc)


def _parse(stamp: str) -> datetime | None:
    raw = str(stamp or "").strip()
    if not raw:
        return None
    try:
        parsed = datetime.fromisoformat(raw.replace("Z", "+00:00"))
    except ValueError:
        return None
    if parsed.tzinfo is None:
        parsed = parsed.replace(tzinfo=timezone.utc)
    return parsed


def label_for(source: str) -> str:
    key = str(source or "").strip().lower()
    if key in SOURCE_LABELS:
        return SOURCE_LABELS[key]
    if key.startswith("discovered-"):
        return key.replace("discovered-", "").replace("-", " ").title()
    return key.replace("-", " ").title() or "Unknown"


def record_seen(
    user_id: str,
    source: str,
    *,
    metric_type: str,
    at: str,
    value: Any = None,
) -> None:
    slug = str(source or "").strip().lower()
    if not slug:
        return
    key = keys.source_seen_key(user_id, slug)
    existing = dynamodb.get_item(key["pk"], key["sk"]) or {}
    types = list(existing.get("metricTypes") or [])
    if metric_type and metric_type not in types:
        types.append(str(metric_type))
    dynamodb.put_item(
        {
            **key,
            "source": slug,
            "label": label_for(slug),
            "lastSeenAt": at,
            "lastMetricType": metric_type,
            "lastValue": value,
            "metricTypes": types[:16],
        }
    )


def all_sources(user_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix(keys.user_pk(user_id), "SOURCE#")
    rows = [{k: v for k, v in item.items() if k not in ("pk", "sk")} for item in items]
    rows.sort(key=lambda row: str(row.get("lastSeenAt") or ""), reverse=True)
    return rows


def landed_last_24h(user_id: str, *, now: datetime | None = None) -> list[dict[str, Any]]:
    cutoff = (now or _now()) - timedelta(hours=24)
    landed = []
    for row in all_sources(user_id):
        seen = _parse(str(row.get("lastSeenAt") or ""))
        if seen and seen >= cutoff:
            metric = METRIC_LABELS.get(str(row.get("lastMetricType") or ""), "data")
            landed.append(
                {
                    **row,
                    "line": f"{row.get('label') or label_for(row.get('source'))} wrote {metric}.",
                }
            )
    return landed


def silent_sources(
    user_id: str,
    connected: list[str],
    *,
    now: datetime | None = None,
    days: int = SILENCE_DAYS,
) -> list[dict[str, Any]]:
    cutoff = (now or _now()) - timedelta(days=days)
    known = {str(row.get("source")): row for row in all_sources(user_id)}
    silent = []
    for raw in connected:
        slug = str(raw or "").strip().lower().replace(" ", "-")
        if not slug:
            continue
        row = known.get(slug)
        if row is None:
            # Also match by label ("Oura Ring" → oura).
            row = next(
                (item for item in known.values() if slug in str(item.get("source")) or slug in str(item.get("label", "")).lower().replace(" ", "-")),
                None,
            )
        seen = _parse(str((row or {}).get("lastSeenAt") or ""))
        if row is None or seen is None or seen < cutoff:
            silent.append(
                {
                    "source": slug,
                    "label": (row or {}).get("label") or label_for(slug),
                    "lastSeenAt": (row or {}).get("lastSeenAt"),
                    "line": f"{(row or {}).get('label') or label_for(slug)} has been silent for {days} days.",
                }
            )
    return silent


def aria_lines(
    user_id: str,
    connected: list[str] | None = None,
    *,
    now: datetime | None = None,
) -> list[str]:
    lines = [row["line"] for row in landed_last_24h(user_id, now=now)]
    if connected:
        lines.extend(row["line"] for row in silent_sources(user_id, connected, now=now))
    return lines[:8]


def briefing_for_chat(user_id: str, connected: list[str] | None = None) -> str | None:
    lines = aria_lines(user_id, connected)
    if not lines:
        return None
    return f"{COACH_NAME} source map: " + " | ".join(lines)


def snapshot(user_id: str, connected: list[str] | None = None) -> dict[str, Any]:
    return {
        "coach": COACH_NAME,
        "landed24h": landed_last_24h(user_id),
        "silent": silent_sources(user_id, connected or []),
        "lines": aria_lines(user_id, connected),
        "sources": all_sources(user_id),
    }
