from __future__ import annotations

from typing import Any

from empty_state import empty_daily_metrics, empty_profile, empty_readiness
from responses import ok
from security import demo_data_enabled
from seed_data import (
    default_connections,
    default_daily_metrics,
    default_personal_records,
    default_profile,
    default_readiness,
    default_sleep,
    default_workout,
    default_workout_history,
    today_iso,
)
from services import daily_metrics as daily_metrics_service
from services import readiness as readiness_service
from services import scoring
from storage import dynamodb, keys


def _strip_keys(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def handle_get_dashboard_today(user_id: str) -> dict:
    """Today's home payload.

    Every field resolves in the same order: what the user actually stored, then
    what can be derived from it, and only then a demo fixture -- and the fixture
    step is skipped outside demo environments. See ``security.demo_data_enabled``
    for why that last gate is not merely cosmetic.
    """
    demo = demo_data_enabled()
    day = today_iso()

    profile_item = dynamodb.get_item(**keys.profile_key(user_id))
    if profile_item:
        profile = _strip_keys(profile_item)
    else:
        profile = default_profile() if demo else empty_profile()

    connections_items = dynamodb.query_prefix(keys.user_pk(user_id), "CONNECTION#")
    if connections_items:
        connections = [_strip_keys(i) for i in connections_items]
    else:
        connections = default_connections() if demo else []

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    has_persisted_sleep = bool(sleep_items)
    if has_persisted_sleep:
        recent_sleep = [_strip_keys(i) for i in sleep_items]
    else:
        recent_sleep = default_sleep() if demo else []

    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=30)
    if workout_items:
        recent_workouts = [_strip_keys(i) for i in workout_items]
    else:
        recent_workouts = default_workout_history() if demo else []

    plan_item = dynamodb.get_item(**keys.workout_plan_key(user_id, day))
    if plan_item:
        today_workout = _strip_keys(plan_item)
    else:
        today_workout = default_workout() if demo else None

    readiness_item = dynamodb.get_item(**keys.readiness_key(user_id, day))
    if readiness_item:
        readiness = _strip_keys(readiness_item)
    elif has_persisted_sleep:
        readiness = readiness_service.compute_readiness(recent_sleep)
    elif demo:
        readiness = default_readiness()
    else:
        readiness = empty_readiness()

    metrics = daily_metrics_service.load_daily_metrics(user_id, day)
    if metrics is not None:
        daily_metrics = daily_metrics_service.apply_sleep_minutes(metrics, recent_sleep)
    elif demo:
        daily_metrics = default_daily_metrics()
    else:
        daily_metrics = empty_daily_metrics(day)

    personal_records = scoring.detect_personal_records(recent_workouts)
    if not personal_records and demo:
        personal_records = default_personal_records()

    return ok({
        "profile": profile,
        "readiness": readiness,
        "dailyMetrics": daily_metrics,
        "todayWorkout": today_workout,
        "recentSleep": recent_sleep,
        "recentWorkouts": recent_workouts,
        "personalRecords": personal_records,
        "connections": connections,
    })
