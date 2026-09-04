from __future__ import annotations

import json
from typing import Any

from empty_state import empty_profile, empty_readiness
from security import demo_data_enabled
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
    """Build the bounded context package the coach routes feed to the AI router.

    This is the block ``AI_SECURITY_DIRECTIVE`` clause 3 points at when it tells
    the model to use only the ground truth it is given and never to invent a
    user's data. Filling it with fixtures made the directive self-defeating: the
    model obediently reasoned over a stranger's sleep and lifts and reported them
    back as the reader's own. Outside a demo environment every field here is
    either something the account stored or empty.
    """
    demo = demo_data_enabled()

    profile_item = dynamodb.get_item(**keys.profile_key(user_id))
    if profile_item:
        profile = _strip_keys(profile_item)
    else:
        profile = default_profile() if demo else empty_profile()

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    if sleep_items:
        recent_sleep = [_strip_keys(i) for i in sleep_items]
    else:
        recent_sleep = default_sleep() if demo else []

    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=14)
    if workout_items:
        recent_workouts = [_strip_keys(i) for i in workout_items]
    else:
        recent_workouts = default_workout_history() if demo else []

    plan_item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    if plan_item:
        today_plan = _strip_keys(plan_item)
    else:
        today_plan = default_workout() if demo else None

    readiness_item = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    if readiness_item:
        current_readiness = _strip_keys(readiness_item)
    elif recent_sleep:
        current_readiness = readiness.compute_readiness(recent_sleep)
    else:
        current_readiness = empty_readiness()

    personal_records = scoring.detect_personal_records(recent_workouts)
    if not personal_records and demo:
        personal_records = default_personal_records()

    return {
        "profile": profile,
        "readiness": current_readiness,
        "recentSleep": recent_sleep[:7],
        "recentWorkouts": recent_workouts[:7],
        "todayPlan": today_plan,
        "trainingLoad": scoring.training_load_trend(recent_workouts),
        "recoveryTrend": scoring.recovery_trend(recent_sleep),
        "personalRecords": personal_records,
    }


def readiness_overall(context: dict[str, Any]) -> int | None:
    """The readiness score if one was actually measured, else ``None``."""
    value = (context.get("readiness") or {}).get("overall")
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return int(round(value))


def context_to_prompt_block(context: dict[str, Any]) -> str:
    """Serialize the context package into a compact JSON block for AI prompts."""
    has_data = bool(
        context.get("recentSleep")
        or context.get("recentWorkouts")
        or readiness_overall(context) is not None
    )
    compact = {
        # Stated outright rather than left for the model to infer from a wall of
        # nulls, so it can say "you have not logged anything yet" instead of
        # hedging around missing numbers.
        "hasLoggedData": has_data,
        "profile": context.get("profile"),
        "readiness": context.get("readiness"),
        "trainingLoad": context.get("trainingLoad"),
        "recoveryTrend": context.get("recoveryTrend"),
        "lastSleepScore": (context.get("recentSleep") or [{}])[0].get("score"),
        "lastWorkoutType": (context.get("recentWorkouts") or [{}])[0].get("type"),
        "todayPlanName": (context.get("todayPlan") or {}).get("name"),
    }
    return json.dumps(compact, separators=(",", ":"))
