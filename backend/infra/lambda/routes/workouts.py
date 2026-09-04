from __future__ import annotations

from typing import Any

from responses import RouteError, ok
from security import demo_data_enabled
from seed_data import (
    default_personal_records,
    default_workout,
    default_workout_history,
    today_iso,
)
from services import scoring
from storage import dynamodb, keys


def _load_today_plan(user_id: str) -> dict[str, Any] | None:
    item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    if item:
        return {k: v for k, v in item.items() if k not in ("pk", "sk")}
    return default_workout() if demo_data_enabled() else None


def _load_history(user_id: str, days: int) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=days)
    if items:
        return [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in items]
    return default_workout_history() if demo_data_enabled() else []


def handle_get_workouts_today(user_id: str) -> dict:
    return ok({"workout": _load_today_plan(user_id)})


def handle_get_workouts_history(user_id: str, days: int) -> dict:
    workouts = _load_history(user_id, days)
    # Records come from the logs themselves; the fixture is a demo stand-in only.
    personal_records = scoring.detect_personal_records(workouts)
    if not personal_records and demo_data_enabled():
        personal_records = default_personal_records()

    return ok({
        "workouts": workouts,
        "personalRecords": personal_records,
    })


def handle_post_workout_log(user_id: str, body: dict) -> dict:
    log = body.get("workout")
    if not isinstance(log, dict):
        raise RouteError(400, "Request body must include a 'workout' object.")

    started_at = log.get("startedAt") or log.get("date", "")
    if not started_at:
        raise RouteError(400, "'workout.startedAt' is required.")

    # A malformed duration doesn't fail here — it fails later, in an
    # unrelated read (scoring.py's training_load_trend does
    # float(w.get("duration", 0))) once this log falls inside the trailing
    # window. Reject it here instead of persisting something every future
    # reader has to defend against.
    duration = log.get("duration")
    if duration is not None and (isinstance(duration, bool) or not isinstance(duration, (int, float))):
        raise RouteError(400, "'workout.duration' must be a number.")

    item = {**keys.workout_log_key(user_id, started_at), **log}
    dynamodb.put_item(item)
    return ok({"workout": log})
