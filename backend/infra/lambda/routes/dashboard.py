from __future__ import annotations

from responses import ok
from seed_data import (
    default_connections,
    default_personal_records,
    default_profile,
    default_readiness,
    default_sleep,
    default_workout,
    default_workout_history,
    default_daily_metrics,
    today_iso,
)
from services import readiness as readiness_service
from storage import dynamodb, keys


def handle_get_dashboard_today(user_id: str) -> dict:
    profile_item = dynamodb.get_item(**keys.profile_key(user_id))
    profile = (
        {k: v for k, v in profile_item.items() if k not in ("pk", "sk")}
        if profile_item
        else default_profile()
    )

    connections_items = dynamodb.query_prefix(keys.user_pk(user_id), "CONNECTION#")
    connections = (
        [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in connections_items]
        if connections_items
        else default_connections()
    )

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    has_persisted_sleep = bool(sleep_items)
    recent_sleep = (
        [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in sleep_items]
        if has_persisted_sleep
        else default_sleep()
    )

    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=30)
    recent_workouts = (
        [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in workout_items]
        if workout_items
        else default_workout_history()
    )

    plan_item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    today_workout = (
        {k: v for k, v in plan_item.items() if k not in ("pk", "sk")}
        if plan_item
        else default_workout()
    )

    readiness_item = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    if readiness_item:
        readiness = {k: v for k, v in readiness_item.items() if k not in ("pk", "sk")}
    elif has_persisted_sleep:
        readiness = readiness_service.compute_readiness(recent_sleep)
    else:
        readiness = default_readiness()

    return ok({
        "profile": profile,
        "readiness": readiness,
        "dailyMetrics": default_daily_metrics(),
        "todayWorkout": today_workout,
        "recentSleep": recent_sleep,
        "recentWorkouts": recent_workouts,
        "personalRecords": default_personal_records(),
        "connections": connections,
    })
