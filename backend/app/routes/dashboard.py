from __future__ import annotations

from core.responses import ok
from routes._connections import public_connection
from data.seed_data import (
    default_connections,
    default_personal_records,
    default_profile,
    default_readiness,
    default_sleep,
    default_workout,
    default_workout_history,
    today_iso,
)
from core.seed_policy import empty_profile, empty_readiness, empty_workout_plan, resolve
from services import readiness as readiness_service
from services.metrics_snapshot import load_daily_metrics
from services import scoring
from storage import dynamodb, keys


def handle_get_dashboard_today(user_id: str) -> dict:
    profile_item = dynamodb.get_item(**keys.profile_key(user_id))
    profile = (
        {k: v for k, v in profile_item.items() if k not in ("pk", "sk")}
        if profile_item
        else resolve(None, default_profile, empty_profile)
    )

    connections_items = dynamodb.query_prefix(keys.user_pk(user_id), "CONNECTION#")
    connections = (
        [public_connection(i) for i in connections_items]
        if connections_items
        else resolve(None, default_connections, list)
    )

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    has_persisted_sleep = bool(sleep_items)
    recent_sleep = (
        [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in sleep_items]
        if has_persisted_sleep
        else resolve(None, default_sleep, list)
    )

    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=30)
    recent_workouts = (
        [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in workout_items]
        if workout_items
        else resolve(None, default_workout_history, list)
    )

    plan_item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    today_workout = (
        {k: v for k, v in plan_item.items() if k not in ("pk", "sk")}
        if plan_item
        else resolve(None, default_workout, empty_workout_plan)
    )

    readiness_item = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    if readiness_item:
        readiness = {k: v for k, v in readiness_item.items() if k not in ("pk", "sk")}
    elif has_persisted_sleep:
        readiness = readiness_service.compute_readiness(recent_sleep)
    else:
        readiness = resolve(None, default_readiness, empty_readiness)

    personal_records = (
        scoring.detect_personal_records(recent_workouts)
        if recent_workouts
        else resolve(None, default_personal_records, list)
    )

    return ok({
        "profile": profile,
        "readiness": readiness,
        "dailyMetrics": load_daily_metrics(user_id),
        "todayWorkout": today_workout,
        "recentSleep": recent_sleep,
        "recentWorkouts": recent_workouts,
        "personalRecords": personal_records,
        "connections": connections,
    })