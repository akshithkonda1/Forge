from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from responses import RouteError, ok
from security import demo_data_enabled
from seed_data import default_chat_messages, default_sleep, default_workout, today_iso
from services import scoring
from storage import dynamodb, keys


def _strip_keys(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def _load_thread_messages(user_id: str, thread_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix(keys.user_pk(user_id), f"CHAT#{thread_id}#MSG#")
    if items:
        return [_strip_keys(i) for i in items]
    return default_chat_messages() if demo_data_enabled() else []


def _persist_message(user_id: str, thread_id: str, msg: dict) -> None:
    created_at = msg["timestamp"]
    item = {**keys.chat_message_key(user_id, thread_id, created_at), **msg}
    dynamodb.put_item(item)


def _recent_sleep(user_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=14)
    if items:
        return [_strip_keys(i) for i in items]
    return default_sleep() if demo_data_enabled() else []


def _recent_workouts(user_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=30)
    return [_strip_keys(i) for i in items]


def _today_plan(user_id: str) -> dict[str, Any] | None:
    item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    if item:
        return _strip_keys(item)
    return default_workout() if demo_data_enabled() else None


def _today_readiness(user_id: str) -> dict[str, Any] | None:
    item = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    return _strip_keys(item) if item else None


def _sleep_reply(user_id: str, msg_id: str, now: str) -> dict[str, Any]:
    records = _recent_sleep(user_id)
    if not records:
        return {
            "id": msg_id,
            "role": "trainer",
            "content": (
                "I do not have any sleep logged for you yet, so I cannot read your "
                "recovery trend. Connect a sleep source or log a night and I will "
                "pick it up from there."
            ),
            "timestamp": now,
        }

    latest = records[0]
    scores = [
        float(r["score"])
        for r in records[:7]
        if isinstance(r.get("score"), (int, float)) and not isinstance(r.get("score"), bool)
    ]

    content = (
        f"Last night you logged {latest.get('totalHours', 'an unrecorded number of')} hours "
        f"with {latest.get('deepMinutes', 'an unrecorded number of')} minutes of deep sleep."
    )
    reply: dict[str, Any] = {
        "id": msg_id,
        "role": "trainer",
        "content": content,
        "timestamp": now,
    }
    if scores:
        reply["richCard"] = {
            "type": "data-chart",
            "data": {
                "title": "Sleep Quality (7-day)",
                "values": list(reversed(scores)),
                "insight": f"Average sleep score: {round(sum(scores) / len(scores))}.",
                "color": "3B82F6",
            },
        }
    return reply


def _progress_reply(user_id: str, msg_id: str, now: str) -> dict[str, Any]:
    workouts = _recent_workouts(user_id)
    prs = scoring.detect_personal_records(workouts)

    if not workouts:
        return {
            "id": msg_id,
            "role": "trainer",
            "content": (
                "You have no logged sessions yet, so there is no progress to compare "
                "against. Log a workout and I will start tracking the trend."
            ),
            "timestamp": now,
        }

    session_word = "session" if len(workouts) == 1 else "sessions"
    content = f"You have {len(workouts)} logged {session_word} on record."
    if prs:
        best = prs[0]
        content += (
            f" Your heaviest lift so far is {best['exercise']} at "
            f"{round(best['value'])} {best['unit']}."
        )
    else:
        content += " None of them recorded exercise weights, so I cannot read PRs from them yet."

    return {"id": msg_id, "role": "trainer", "content": content, "timestamp": now}


def _training_reply(user_id: str, msg_id: str, now: str) -> dict[str, Any]:
    readiness = _today_readiness(user_id)
    plan = _today_plan(user_id)

    overall = readiness.get("overall") if readiness else None
    if isinstance(overall, (int, float)) and not isinstance(overall, bool):
        content = (
            f"Your readiness is {round(overall)}/100 today. Keep the heavy compounds "
            "crisp and do not chase extra volume after the accessories."
        )
    else:
        content = (
            "I do not have a readiness score for you today, so I cannot tell you how "
            "hard to push. Log or sync last night's sleep and I will have something "
            "to work from."
        )

    reply: dict[str, Any] = {
        "id": msg_id,
        "role": "trainer",
        "content": content,
        "timestamp": now,
    }
    if plan is not None:
        reply["richCard"] = {"type": "workout-plan", "data": plan}
    return reply


def _trainer_response(user_id: str, content: str) -> dict[str, Any]:
    """A deterministic reply built only from what this account actually stored.

    These branches used to quote fixed biometrics -- 7.2 hours of sleep, 8
    sessions, readiness 82 with HRV at 52 ms -- to every user regardless of what
    was in storage. Stated as fact about someone's own body, that is the kind of
    wrong a fitness app does not get to be.
    """
    lower = content.lower()
    now = datetime.now(timezone.utc).isoformat()
    msg_id = f"trainer-{int(datetime.now(timezone.utc).timestamp() * 1000)}"

    if "sleep" in lower:
        return _sleep_reply(user_id, msg_id, now)

    if "progress" in lower or "pr" in lower:
        return _progress_reply(user_id, msg_id, now)

    if "train" in lower or "workout" in lower or "plan" in lower:
        return _training_reply(user_id, msg_id, now)

    return {
        "id": msg_id,
        "role": "trainer",
        "content": (
            "Happy to dig in. Tell me whether you want to look at strength, sleep, or "
            "progress trends and I will pull up what you have logged."
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
    trainer_msg = _trainer_response(user_id, content)

    _persist_message(user_id, thread_id, user_msg)
    _persist_message(user_id, thread_id, trainer_msg)

    return ok({"userMessage": user_msg, "trainerMessage": trainer_msg})
