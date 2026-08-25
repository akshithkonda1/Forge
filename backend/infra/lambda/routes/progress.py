from __future__ import annotations

from responses import ok
from security import demo_data_enabled
from seed_data import default_personal_records, default_sleep, default_workout_history
from services import scoring
from storage import dynamodb, keys


def _summary(
    workouts: list[dict],
    recent_sleep: list[dict],
    load: dict,
    recovery: dict,
) -> str:
    if not workouts and not recent_sleep:
        return "Nothing logged yet, so there is no trend to report."
    if not workouts:
        direction = "up" if recovery["delta"] > 0 else "down" if recovery["delta"] < 0 else "flat"
        return (
            f"No workouts logged this period. Recovery {direction} "
            f"{abs(recovery['delta'])} pts over the prior 7 nights."
        )
    if not recent_sleep:
        return (
            f"Training load is {load['trend']} ({load['current']} vs {load['previous']}). "
            "No sleep logged, so recovery is unmeasured."
        )

    direction = "up" if recovery["delta"] > 0 else "down" if recovery["delta"] < 0 else "flat"
    return (
        f"Training load is {load['trend']} ({load['current']} vs {load['previous']}), "
        f"recovery {direction} {abs(recovery['delta'])} pts over the prior 7 nights."
    )


def handle_get_progress_summary(user_id: str, days: int) -> dict:
    demo = demo_data_enabled()

    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=days)
    if workout_items:
        workouts = [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in workout_items]
    else:
        workouts = default_workout_history() if demo else []

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    if sleep_items:
        recent_sleep = [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in sleep_items]
    else:
        recent_sleep = default_sleep() if demo else []

    load = scoring.training_load_trend(workouts)
    recovery = scoring.recovery_trend(recent_sleep)
    detected_prs = scoring.detect_personal_records(workouts)
    if detected_prs:
        new_prs = detected_prs[:3]
    else:
        new_prs = default_personal_records()[:3] if demo else []

    return ok({
        "periodDays": days,
        "workoutsCompleted": len(workouts),
        "newPersonalRecords": new_prs,
        "trainingLoad": load,
        "recoveryTrend": recovery,
        "recoveryConsistencyDelta": recovery["delta"],
        "summary": _summary(workouts, recent_sleep, load, recovery),
    })
