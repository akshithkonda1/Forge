"""TTL and purge helpers for encrypted conclusions rows."""
from __future__ import annotations

from datetime import datetime, timedelta, timezone

from storage import dynamodb, keys

_RETENTION_DAYS = 7


def iso_week_key(date_str: str | None = None) -> str:
    """Return ISO week key like 2026-W24."""
    if date_str:
        anchor = datetime.strptime(date_str[:10], "%Y-%m-%d").date()
    else:
        anchor = datetime.now(timezone.utc).date()
    year, week, _ = anchor.isocalendar()
    return f"{year}-W{week:02d}"


def conclusions_ttl_epoch(*, now: datetime | None = None) -> int:
    """DynamoDB TTL epoch — retain conclusions for seven days."""
    anchor = now or datetime.now(timezone.utc)
    expires = anchor + timedelta(days=_RETENTION_DAYS)
    return int(expires.timestamp())


def purge_expired(user_id: str) -> int:
    """Delete conclusions rows older than retention window."""
    cutoff = datetime.now(timezone.utc) - timedelta(days=_RETENTION_DAYS)
    removed = 0
    items = dynamodb.query_prefix(keys.user_pk(user_id), "ARIA#CONCLUSIONS#")
    for item in items:
        generated_at = item.get("generatedAt")
        if not generated_at:
            continue
        try:
            created = datetime.fromisoformat(str(generated_at).replace("Z", "+00:00"))
        except ValueError:
            continue
        if created < cutoff:
            dynamodb.delete_item(item["pk"], item["sk"])
            removed += 1
    return removed