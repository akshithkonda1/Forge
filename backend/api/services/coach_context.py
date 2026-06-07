from __future__ import annotations

import json
from typing import Any

from routes import lifestyle as lifestyle_routes
from seed_data import (
    default_personal_records,
    default_profile,
    default_sleep,
    default_workout,
    default_workout_history,
    today_iso,
)
from services import readiness, scoring
from storage import dynamodb, keys


def _strip_keys(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def gather_user_context(user_id: str) -> dict[str, Any]:
    """Build the bounded context package the coach routes feed to the AI router."""
    profile_item = dynamodb.get_item(**keys.profile_key(user_id))
    profile = _strip_keys(profile_item) if profile_item else default_profile()

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    recent_sleep = [_strip_keys(i) for i in sleep_items] if sleep_items else default_sleep()

    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=14)
    recent_workouts = (
        [_strip_keys(i) for i in workout_items] if workout_items else default_workout_history()
    )

    plan_item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    today_plan = _strip_keys(plan_item) if plan_item else default_workout()

    readiness_item = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    if readiness_item:
        current_readiness = _strip_keys(readiness_item)
    else:
        current_readiness = readiness.compute_readiness(recent_sleep)

    lifestyle_event = {"queryStringParameters": {"date": today_iso()}}
    lifestyle_resp = lifestyle_routes.handle_get_lifestyle_dashboard(user_id, lifestyle_event)
    lifestyle_snapshot = {}
    if lifestyle_resp.get("statusCode") == 200:
        lifestyle_snapshot = json.loads(lifestyle_resp.get("body", "{}"))

    return {
        "profile": profile,
        "readiness": current_readiness,
        "recentSleep": recent_sleep[:7],
        "recentWorkouts": recent_workouts[:7],
        "todayPlan": today_plan,
        "trainingLoad": scoring.training_load_trend(recent_workouts),
        "recoveryTrend": scoring.recovery_trend(recent_sleep),
        "personalRecords": default_personal_records(),
        "lifestyle": {
            "metrics": lifestyle_snapshot.get("metrics"),
            "nutrition": {
                "calories": (lifestyle_snapshot.get("nutrition") or {}).get("calories"),
                "protein": (lifestyle_snapshot.get("nutrition") or {}).get("protein"),
                "waterMl": (lifestyle_snapshot.get("nutrition") or {}).get("waterMl"),
            },
            "habitStreak": lifestyle_snapshot.get("habitStreak"),
            "habitsCompleted": sum(
                1 for h in (lifestyle_snapshot.get("habits") or []) if h.get("completed")
            ),
        },
    }


def context_to_prompt_block(context: dict[str, Any]) -> str:
    """Serialize the context package into a compact JSON block for AI prompts."""
    compact = {
        "profile": context.get("profile"),
        "readiness": context.get("readiness"),
        "trainingLoad": context.get("trainingLoad"),
        "recoveryTrend": context.get("recoveryTrend"),
        "lastSleepScore": (context.get("recentSleep") or [{}])[0].get("score"),
        "lastWorkoutType": (context.get("recentWorkouts") or [{}])[0].get("type"),
        "todayPlanName": (context.get("todayPlan") or {}).get("name"),
        "lifestyle": context.get("lifestyle"),
    }
    return json.dumps(compact, separators=(",", ":"))
