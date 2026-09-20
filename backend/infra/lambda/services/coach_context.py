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


def _sleep_rows_from_body_snapshot(user_id: str) -> list[dict[str, Any]]:
    """The single latest night, derived from the persisted body snapshot --
    the same METRIC#-derived reality /ai/chat and /ai/observe already read
    via fusion.fuse_turn/save_body_snapshot -- for when no SLEEP# session-log
    row exists yet. Without this, a user who has been getting real coaching
    from ARIA elsewhere could still be told "you have no sleep logged" here,
    purely because this route reads a different DynamoDB source than the one
    that actually has their data (see aria_user_model.py's module docstring).

    Deliberately has no "score" field: BodyModel doesn't compute the 0-100
    sleep score a logged session does, and a row silently defaulting that to
    0 would make recovery_trend() report a fabricated "steady, 0" trend
    instead of the honest "not enough history yet" gather_user_context
    preserves by keeping this out of the recoveryTrend computation (see
    below) -- this is display-only data, not trend input.
    """
    try:
        from aria_core import fusion
    except Exception:
        return []
    try:
        snapshot = fusion.load_body_snapshot(user_id)
    except Exception:
        return []
    if not snapshot:
        return []
    sleep = (snapshot.get("aria_context") or {}).get("sleep") or {}
    duration_minutes = sleep.get("duration_minutes")
    if not isinstance(duration_minutes, (int, float)) or isinstance(duration_minutes, bool):
        return []
    row: dict[str, Any] = {"totalHours": round(duration_minutes / 60.0, 2)}
    deep = sleep.get("deep_minutes")
    if isinstance(deep, (int, float)) and not isinstance(deep, bool):
        row["deepMinutes"] = deep
    rem = sleep.get("rem_minutes")
    if isinstance(rem, (int, float)) and not isinstance(rem, bool):
        row["remMinutes"] = rem
    return [row]


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

    # recovery_trend needs real, score-bearing session-log nights for its
    # 7-vs-7 comparison -- computed from recent_sleep (session logs only),
    # never the body-snapshot fallback below, so a user with no logged
    # nights still gets the honest {current:0, previous:0, delta:0} rather
    # than a trend derived from a single scoreless night.
    recovery_trend = scoring.recovery_trend(recent_sleep)
    has_logged_sleep = bool(recent_sleep)
    # recent_sleep is already demo fixture data here when demo mode is on
    # (set above), so this fallback is reached only when it's genuinely
    # empty -- a real, non-demo account with no logged nights.
    display_sleep = recent_sleep or _sleep_rows_from_body_snapshot(user_id)

    return {
        "profile": profile,
        "readiness": current_readiness,
        "recentSleep": display_sleep[:7],
        "recentWorkouts": recent_workouts[:7],
        "todayPlan": today_plan,
        "trainingLoad": scoring.training_load_trend(recent_workouts),
        "recoveryTrend": recovery_trend,
        "personalRecords": personal_records,
        # True only for real logged nights -- lets a caller tell "nothing
        # anywhere" apart from "synced data exists, just not enough of it
        # with a score to trend yet" (see _sleep_rows_from_body_snapshot).
        "hasLoggedSleep": has_logged_sleep,
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
