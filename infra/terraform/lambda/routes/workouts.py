from __future__ import annotations

from typing import Any

from responses import RouteError, ok
from seed_data import default_personal_records, default_workout, default_workout_history
from storage import dynamodb, keys


def _load_today_plan(user_id: str) -> dict[str, Any] | None:
    from seed_data import today_iso
    item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    if item:
        return {k: v for k, v in item.items() if k not in ("pk", "sk")}
    return default_workout()


def _load_history(user_id: str, days: int) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=days)
    if items:
        return [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in items]
    return default_workout_history()


def handle_get_workouts_today(user_id: str) -> dict:
    return ok({"workout": _load_today_plan(user_id)})


def handle_get_workouts_history(user_id: str, days: int) -> dict:
    return ok({
        "workouts": _load_history(user_id, days),
        "personalRecords": default_personal_records(),
    })


def handle_post_workout_log(user_id: str, body: dict) -> dict:
    log = body.get("workout")
    if not isinstance(log, dict):
        raise RouteError(400, "Request body must include a 'workout' object.")

    started_at = log.get("startedAt") or log.get("date", "")
    if not started_at:
        raise RouteError(400, "'workout.startedAt' is required.")

    item = {**keys.workout_log_key(user_id, started_at), **log}
    dynamodb.put_item(item)
    return ok({"workout": log})
