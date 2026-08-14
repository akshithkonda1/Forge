"""Adaptive week — a 7-day skeleton that rewrites when the body does."""

from __future__ import annotations

from datetime import date, datetime, timedelta, timezone
from typing import Any

from services import daily_decision, ledger
from services.source_map import COACH_NAME
from storage import dynamodb, keys

_FOCUSES = ("strength", "zone-2", "skills", "mobility", "easy-walk", "rest", "long")


def _monday(day: date | None = None) -> date:
    stamp = day or date.today()
    return stamp - timedelta(days=stamp.weekday())


def _intent_for(index: int, readiness: int, cycle_phase: str | None) -> str:
    if readiness < 55:
        return "recover" if index in (0, 3, 6) else "easy"
    if cycle_phase in {"bleeding", "luteal", "period"}:
        return "recover" if index in (6,) else ("easy" if index in (0, 3) else "train")
    # Default week: train / easy / train / easy / train / easy / recover
    pattern = ("train", "easy", "train", "easy", "train", "easy", "recover")
    return pattern[index]


def _focus(intent: str, index: int) -> str:
    if intent == "recover":
        return "rest"
    if intent == "easy":
        return "zone-2" if index % 2 == 0 else "mobility"
    return _FOCUSES[index % 4]


def build(user_id: str, *, reason: str = "baseline") -> dict[str, Any]:
    nights = ledger.load_sleep(user_id)
    readiness_row = dynamodb.get_item(**keys.readiness_key(user_id, date.today().isoformat()))
    readiness = int((readiness_row or {}).get("overall") or 70)
    profile = ledger.load_profile(user_id)
    cycle_phase = str(profile.get("cyclePhase") or "").lower() or None
    last_sleep = float((nights[0] if nights else {}).get("score") or 0)
    if last_sleep and last_sleep < 60:
        readiness = min(readiness, 54)

    start = _monday()
    days = []
    for index in range(7):
        day = start + timedelta(days=index)
        intent = _intent_for(index, readiness, cycle_phase)
        days.append(
            {
                "date": day.isoformat(),
                "intent": intent,
                "focus": _focus(intent, index),
                "reason": reason,
            }
        )

    payload = {
        "coach": COACH_NAME,
        "weekStart": start.isoformat(),
        "readiness": readiness,
        "days": days,
        "rewrittenAt": datetime.now(timezone.utc).isoformat(),
        "reason": reason,
    }
    dynamodb.put_item({**keys.week_plan_key(user_id, start.isoformat()), **payload})
    return payload


def load(user_id: str) -> dict[str, Any]:
    start = _monday().isoformat()
    existing = dynamodb.get_item(**keys.week_plan_key(user_id, start))
    if existing and existing.get("days"):
        return ledger.strip(existing)
    return build(user_id)


def maybe_rewrite(user_id: str) -> dict[str, Any]:
    plan = load(user_id)
    nights = ledger.load_sleep(user_id)
    last_sleep = float((nights[0] if nights else {}).get("score") or 100)
    decision = daily_decision.ensure_today(user_id)
    workouts = ledger.load_workouts(user_id, days=2)
    today = date.today().isoformat()
    trained_today = any(str(w.get("date") or w.get("startedAt") or "").startswith(today) for w in workouts)

    reasons = []
    if last_sleep < 60:
        reasons.append("bad-night")
    if decision["call"] == "recover":
        reasons.append("low-readiness")
    yesterday = (date.today() - timedelta(days=1)).isoformat()
    planned_yesterday = next((d for d in plan.get("days") or [] if d.get("date") == yesterday), None)
    trained_yesterday = any(str(w.get("date") or w.get("startedAt") or "").startswith(yesterday) for w in workouts)
    if planned_yesterday and planned_yesterday.get("intent") == "train" and not trained_yesterday:
        reasons.append("missed-session")

    if not reasons:
        return plan
    return build(user_id, reason=",".join(reasons))


def today_from_plan(plan: dict[str, Any]) -> dict[str, Any] | None:
    today = date.today().isoformat()
    return next((day for day in plan.get("days") or [] if day.get("date") == today), None)
