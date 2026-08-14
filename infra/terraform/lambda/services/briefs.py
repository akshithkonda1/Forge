"""6 AM / 6 PM briefs — morning is the decision, evening is the review."""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from seed_data import today_iso
from services import daily_decision, ledger, weekly_review
from services.source_map import COACH_NAME
from storage import dynamodb, keys

MORNING_HOUR = 6
EVENING_HOUR = 18

_EVENING_QUESTIONS = (
    {"id": "follow-through", "prompt": "Did you follow ARIA's call, or did the day go another way?"},
    {"id": "energy", "prompt": "How did your energy actually feel by evening?"},
    {"id": "remember", "prompt": "Anything ARIA should remember before tomorrow's call?"},
)


def _profile_hours(profile: dict[str, Any]) -> tuple[int, int, int, int]:
    morning = int(profile.get("briefMorningHour") or MORNING_HOUR)
    evening = int(profile.get("briefEveningHour") or EVENING_HOUR)
    morning_min = int(profile.get("briefMorningMinute") or 0)
    evening_min = int(profile.get("briefEveningMinute") or 0)
    return morning, morning_min, evening, evening_min


def morning(user_id: str) -> dict[str, Any]:
    decision = daily_decision.ensure_today(user_id)
    payload = {
        "slot": "morning",
        "date": today_iso(),
        "coach": COACH_NAME,
        "title": f"{COACH_NAME} · morning",
        "call": decision["call"],
        "why": decision["why"],
        "body": f"{decision['call'].capitalize()} today. {decision['why']}",
        "destination": "forge://today/morning",
        "hour": MORNING_HOUR,
        "minute": 0,
    }
    dynamodb.put_item({**keys.brief_key(user_id, today_iso(), "morning"), **payload})
    return payload


def evening(user_id: str) -> dict[str, Any]:
    decision = daily_decision.ensure_today(user_id)
    workouts = ledger.load_workouts(user_id, days=3)
    today = today_iso()
    trained = any(str(w.get("date") or w.get("startedAt") or "").startswith(today) for w in workouts)
    if decision["call"] == "train" and trained:
        happened = "You trained, matching the call."
    elif decision["call"] == "recover" and not trained:
        happened = "You kept it light, matching the call."
    elif decision["call"] == "train" and not trained:
        happened = "The call was train. The day went another way — that's data, not a failure."
    else:
        happened = "The day landed differently than the morning call. ARIA will use that tomorrow."

    day_index = datetime.now(timezone.utc).timetuple().tm_yday % len(_EVENING_QUESTIONS)
    question = _EVENING_QUESTIONS[day_index]
    payload = {
        "slot": "evening",
        "date": today,
        "coach": COACH_NAME,
        "title": f"{COACH_NAME} · evening",
        "call": decision["call"],
        "happened": happened,
        "question": question,
        "body": f"{happened} {question['prompt']}",
        "destination": "forge://today/evening",
        "hour": EVENING_HOUR,
        "minute": 0,
    }
    dynamodb.put_item({**keys.brief_key(user_id, today, "evening"), **payload})
    return payload


def answer_evening(user_id: str, text: str) -> dict[str, Any]:
    note = str(text or "").strip()[:500]
    payload = evening(user_id)
    payload["answer"] = note
    payload["answeredAt"] = datetime.now(timezone.utc).isoformat()
    dynamodb.put_item({**keys.brief_key(user_id, today_iso(), "evening"), **payload})
    if note:
        weekly_review.append_note(user_id, note)
    return payload


def notifications_due(user_id: str) -> dict[str, Any]:
    profile = ledger.load_profile(user_id)
    morning_hour, morning_min, evening_hour, evening_min = _profile_hours(profile)
    am = morning(user_id)
    pm = evening(user_id)
    am["hour"], am["minute"] = morning_hour, morning_min
    pm["hour"], pm["minute"] = evening_hour, evening_min
    return {
        "coach": COACH_NAME,
        "notifications": [
            {
                "id": "forge.notification.brief.morning",
                "slot": "morning",
                "hour": morning_hour,
                "minute": morning_min,
                "title": am["title"],
                "body": am["body"][:180],
                "destination": am["destination"],
            },
            {
                "id": "forge.notification.brief.evening",
                "slot": "evening",
                "hour": evening_hour,
                "minute": evening_min,
                "title": pm["title"],
                "body": pm["body"][:180],
                "destination": pm["destination"],
            },
        ],
    }
