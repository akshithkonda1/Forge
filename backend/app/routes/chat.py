from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from core.responses import RouteError, ok
from core.runtime import allow_seed_fallback
from core.seed_policy import empty_workout_plan
from data.seed_data import default_chat_messages, default_sleep, default_workout, today_iso
from storage import dynamodb, keys


def _load_thread_messages(user_id: str, thread_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix(keys.user_pk(user_id), f"CHAT#{thread_id}#MSG#")
    if items:
        return [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in items]
    if allow_seed_fallback():
        return default_chat_messages()
    return []


def _persist_message(user_id: str, thread_id: str, msg: dict) -> None:
    created_at = msg["timestamp"]
    item = {**keys.chat_message_key(user_id, thread_id, created_at), **msg}
    dynamodb.put_item(item)


def _strip(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def _recent_sleep(user_id: str, *, limit: int = 7) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=limit)
    return [_strip(item) for item in items]


def _today_workout(user_id: str) -> dict[str, Any]:
    plan_item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    if plan_item:
        return _strip(plan_item)
    if allow_seed_fallback():
        return default_workout()
    return empty_workout_plan()


def _trainer_response(content: str, user_id: str) -> dict[str, Any]:
    lower = content.lower()
    now = datetime.now(timezone.utc).isoformat()
    msg_id = f"trainer-{int(datetime.now(timezone.utc).timestamp() * 1000)}"

    if "sleep" in lower:
        sleep_rows = _recent_sleep(user_id) if not allow_seed_fallback() else default_sleep()[:7]
        if sleep_rows:
            latest = sleep_rows[0]
            scores = [int(item.get("score", 0) or 0) for item in sleep_rows[:7]]
            return {
                "id": msg_id,
                "role": "trainer",
                "content": (
                    f"Last night you logged {latest.get('totalHours', 0)} hours with "
                    f"{latest.get('deepMinutes', 0)} minutes of deep sleep. Your recovery trend is "
                    "strong enough for planned training, but keep protecting the wind-down window."
                ),
                "timestamp": now,
                "richCard": {
                    "type": "data-chart",
                    "data": {
                        "title": "Sleep Quality (7-day)",
                        "values": list(reversed(scores)),
                        "insight": f"Average sleep score: {round(sum(scores) / len(scores))}.",
                        "color": "3B82F6",
                    },
                },
            }
        return {
            "id": msg_id,
            "role": "trainer",
            "content": (
                "I do not have sleep data logged yet. Connect a wearable or log a sleep session "
                "so I can coach recovery and training load from real trends."
            ),
            "timestamp": now,
        }

    if "progress" in lower or "pr" in lower:
        if allow_seed_fallback():
            return {
                "id": msg_id,
                "role": "trainer",
                "content": (
                    "Over the last month you completed 8 logged sessions and hit multiple PRs. "
                    "Strength is moving while readiness is holding steady, so the next step is "
                    "controlled progression instead of adding random volume."
                ),
                "timestamp": now,
                "richCard": {
                    "type": "progress-comparison",
                    "data": {
                        "title": "Bench Press",
                        "current": 225,
                        "previous": 205,
                        "unit": "lbs",
                        "insight": "Bench is up 20 lbs across the current block.",
                    },
                },
            }
        return {
            "id": msg_id,
            "role": "trainer",
            "content": (
                "Log workouts consistently and I can compare strength trends and highlight "
                "new personal records as they appear."
            ),
            "timestamp": now,
        }

    if "train" in lower or "workout" in lower or "plan" in lower:
        workout = _today_workout(user_id)
        if workout.get("name"):
            return {
                "id": msg_id,
                "role": "trainer",
                "content": (
                    f"Today's plan is {workout['name']}. Keep the heavy compounds crisp and "
                    "do not chase extra volume after the accessories."
                ),
                "timestamp": now,
                "richCard": {"type": "workout-plan", "data": workout},
            }
        return {
            "id": msg_id,
            "role": "trainer",
            "content": (
                "There is no workout plan saved for today yet. Tell me your goal and "
                "available time, or log a plan from the coach tab."
            ),
            "timestamp": now,
        }

    return {
        "id": msg_id,
        "role": "trainer",
        "content": (
            "Based on today's metrics, you are tracking well. Recovery is high enough to "
            "train, but the best next move depends on whether you want to focus on "
            "strength, sleep, or progress trends."
        ),
        "timestamp": now,
    }


def handle_get_chat_thread(user_id: str) -> dict:
    thread_id = "current"
    messages = _load_thread_messages(user_id, thread_id)
    return ok({"threadId": thread_id, "messages": messages})


def handle_post_chat_message(user_id: str, body: dict) -> dict:
    content = str(body.get("content") or "").strip()
    if not content:
        raise RouteError(400, "Request body must include non-empty 'content'.")

    thread_id = "current"
    now = datetime.now(timezone.utc).isoformat()
    user_msg: dict[str, Any] = {
        "id": f"user-{int(datetime.now(timezone.utc).timestamp() * 1000)}",
        "role": "user",
        "content": content,
        "timestamp": now,
    }
    trainer_msg = _trainer_response(content, user_id)

    _persist_message(user_id, thread_id, user_msg)
    _persist_message(user_id, thread_id, trainer_msg)

    return ok({"userMessage": user_msg, "trainerMessage": trainer_msg})
