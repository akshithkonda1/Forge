"""Watch companion snapshot — decision, rings, tracking, next action."""

from __future__ import annotations

from typing import Any

from services import anomalies, daily_decision, ledger, source_map
from services.source_map import COACH_NAME


def snapshot(user_id: str) -> dict[str, Any]:
    decision = daily_decision.ensure_today(user_id)
    metrics = ledger.load_metrics(user_id)
    nights = ledger.load_sleep(user_id, days=3)
    readiness_row = ledger.persist_readiness(
        user_id, nights, ledger.latest_metric(metrics, "hrv")
    ) if not ledger.load_sleep(user_id) else None
    from storage import dynamodb, keys
    from seed_data import today_iso

    stored = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    readiness = int((stored or readiness_row or {}).get("overall") or decision.get("readiness") or 0)
    sleep_score = int((nights[0] if nights else {}).get("score") or 0)
    steps = ledger.latest_metric(metrics, "steps") or 0
    calories = ledger.latest_metric(metrics, "active-calories") or 0
    water = ledger.latest_metric(metrics, "dietary-water") or 0
    next_title = {
        "train": "Train",
        "easy": "Easy session",
        "recover": "Recover",
    }.get(decision["call"], "Today")

    return {
        "coach": COACH_NAME,
        "decision": decision,
        "readiness": readiness,
        "rings": {
            "move": calories,
            "exercise": None,
            "stand": None,
        },
        "tracking": {
            "steps": steps,
            "activeCalories": calories,
            "water": water,
            "sleepScore": sleep_score,
        },
        "complications": {
            "readiness": {"value": readiness, "label": f"{readiness}"},
            "nextAction": {"title": next_title, "symbol": "figure.walk" if decision["call"] != "recover" else "moon.zzz"},
            "sleep": {"score": sleep_score, "label": f"Sleep {sleep_score}" if sleep_score else "Sleep"},
        },
        "sources": source_map.snapshot(user_id, ledger.connected_device_ids(ledger.load_profile(user_id))),
        "anomalies": anomalies.detect(user_id),
    }


def log_event(user_id: str, body: dict[str, Any]) -> dict[str, Any]:
    kind = str(body.get("type") or "").lower()
    from datetime import datetime, timezone
    from storage import dynamodb, keys

    started = datetime.now(timezone.utc).isoformat()
    if kind == "water":
        try:
            value = float(body.get("value") or 250)
        except (TypeError, ValueError):
            value = 250.0
        dynamodb.put_item(
            {
                **keys.metric_key(user_id, "dietary-water", started),
                "metricType": "dietary-water",
                "source": "apple-watch",
                "startedAt": started,
                "value": value,
                "unit": "ml",
            }
        )
        source_map.record_seen(user_id, "apple-watch", metric_type="dietary-water", at=started, value=value)
    elif kind == "skip":
        decision = daily_decision.ensure_today(user_id)
        decision["skipped"] = True
        dynamodb.put_item({**keys.daily_decision_key(user_id, decision["date"]), **decision})
    elif kind == "start":
        dynamodb.put_item(
            {
                **keys.workout_log_key(user_id, started),
                "startedAt": started,
                "source": "apple-watch",
                "name": str(body.get("name") or "Watch session"),
                "duration": float(body.get("duration") or 0),
            }
        )
        source_map.record_seen(user_id, "apple-watch", metric_type="workout-load", at=started)
    else:
        from responses import RouteError

        raise RouteError(400, "type must be water, skip, or start.")
    ledger.refresh_after_ingest(user_id)
    return snapshot(user_id)
