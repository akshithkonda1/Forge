"""Persist and load encrypted DataConclusions."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from services import conclusions_engine, crypto
from services.conclusions_lifecycle import conclusions_ttl_epoch, iso_week_key, purge_expired
from storage import dynamodb, keys


def refresh_conclusions(user_id: str, *, date: str | None = None) -> dict[str, Any]:
    """Recompute conclusions and persist with TTL."""
    conclusions = conclusions_engine.build_data_conclusions(user_id, date=date)
    week_key = iso_week_key(conclusions.get("date"))
    envelope = crypto.encrypt_payload(conclusions)
    item = {
        **keys.aria_conclusions_key(user_id, week_key),
        "weekKey": week_key,
        "generatedAt": conclusions.get("generatedAt"),
        "coveragePct": conclusions.get("coveragePct"),
        "ttl": conclusions_ttl_epoch(),
        **envelope,
    }
    dynamodb.put_item(item)
    purge_expired(user_id)
    return conclusions


def load_conclusions(user_id: str, *, week_key: str | None = None) -> dict[str, Any] | None:
    """Load conclusions for the current or specified ISO week."""
    key = week_key or iso_week_key()
    item = dynamodb.get_item(**keys.aria_conclusions_key(user_id, key))
    if not item:
        return None
    return crypto.decrypt_payload(item)


def get_or_refresh_conclusions(user_id: str) -> dict[str, Any]:
    """Return stored conclusions or compute fresh ones."""
    stored = load_conclusions(user_id)
    if stored:
        return stored
    return refresh_conclusions(user_id)