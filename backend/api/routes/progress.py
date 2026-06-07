from __future__ import annotations

from responses import ok
from seed_data import default_personal_records, default_sleep, default_workout_history
from seed_policy import resolve
from services import scoring
from storage import dynamodb, keys


def handle_get_progress_summary(user_id: str, days: int) -> dict:
    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=days)
    if workout_items:
        workouts = [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in workout_items]
    else:
        workouts = resolve(None, default_workout_history, list)

    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    if sleep_items:
        recent_sleep = [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in sleep_items]
    else:
        recent_sleep = resolve(None, default_sleep, list)

    load = scoring.training_load_trend(workouts)
    recovery = scoring.recovery_trend(recent_sleep)
    detected_prs = scoring.detect_personal_records(workouts)
    if detected_prs:
        new_prs = detected_prs[:3]
    else:
        new_prs = resolve(None, lambda: default_personal_records()[:3], list)

    return ok({
        "periodDays": days,
        "workoutsCompleted": len(workouts),
        "newPersonalRecords": new_prs,
        "trainingLoad": load,
        "recoveryTrend": recovery,
        "recoveryConsistencyDelta": recovery["delta"],
        "summary": (
            f"Training load is {load['trend']} ({load['current']} vs {load['previous']}), "
            f"recovery {('up' if recovery['delta'] > 0 else 'down' if recovery['delta'] < 0 else 'flat')} "
            f"{abs(recovery['delta'])} pts over the prior 7 nights."
        ),
    })