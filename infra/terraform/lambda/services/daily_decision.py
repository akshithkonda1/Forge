"""One day, one decision — train / easy / recover.

ARIA makes a single call from last night, load, and the source map.
Hard work is never prescribed when readiness is low.
"""

from __future__ import annotations

from typing import Any

from seed_data import today_iso
from services import ledger, source_map
from services.source_map import COACH_NAME
from storage import dynamodb, keys

TRAIN = "train"
EASY = "easy"
RECOVER = "recover"


def _sleep_score(nights: list[dict[str, Any]]) -> float:
    if not nights:
        return 0.0
    try:
        return float(nights[0].get("score") or 0)
    except (TypeError, ValueError):
        return 0.0


def _call(readiness: int, sleep_score: float, load_delta: float, silent: int) -> str:
    if readiness < 55 or sleep_score and sleep_score < 60:
        return RECOVER
    if readiness < 70 or load_delta > 20 or silent >= 2:
        return EASY
    return TRAIN


def _why(call: str, readiness: int, sleep_score: float, lines: list[str]) -> str:
    cited = lines[0] if lines else "The ledger is thin, so ARIA stays conservative."
    if call == RECOVER:
        first = f"Recover. Readiness is {readiness} and last night scored {int(sleep_score) or 'low'}."
        second = f"{cited} Pushing today would be stubborn, not strong."
    elif call == EASY:
        first = f"Easy day. Readiness is {readiness} — enough to move, not enough to chase a PR."
        second = f"{cited} Keep the session short and leave something in the tank."
    else:
        first = f"Train. Readiness is {readiness} and last night held."
        second = f"{cited} Use it, then stop while it still looks like a good decision."
    return f"{first} {second}"


def compute(user_id: str) -> dict[str, Any]:
    nights = ledger.load_sleep(user_id)
    workouts = ledger.load_workouts(user_id)
    metrics = ledger.load_metrics(user_id)
    profile = ledger.load_profile(user_id)
    hrv = ledger.latest_metric(metrics, "hrv")
    readiness_row = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    if readiness_row:
        readiness = int(readiness_row.get("overall") or 0)
    else:
        readiness = int(ledger.persist_readiness(user_id, nights, hrv).get("overall") or 0)

    sleep_score = _sleep_score(nights)
    current = sum(float(w.get("duration") or 0) for w in workouts[:7])
    previous = sum(float(w.get("duration") or 0) for w in workouts[7:14])
    load_delta = current - previous
    connected = ledger.connected_device_ids(profile)
    lines = source_map.aria_lines(user_id, connected)
    silent = len(source_map.silent_sources(user_id, connected))
    call = _call(readiness, sleep_score, load_delta, silent)
    why = _why(call, readiness, sleep_score, lines)
    payload = {
        "date": today_iso(),
        "coach": COACH_NAME,
        "call": call,
        "why": why,
        "readiness": readiness,
        "sleepScore": sleep_score,
        "sources": lines,
        "tap": "today-plan" if call != RECOVER else "recover",
    }
    dynamodb.put_item({**keys.daily_decision_key(user_id, today_iso()), **payload})
    return payload


def ensure_today(user_id: str) -> dict[str, Any]:
    existing = dynamodb.get_item(**keys.daily_decision_key(user_id, today_iso()))
    if existing and existing.get("call"):
        return ledger.strip(existing)
    return compute(user_id)


def load_today(user_id: str) -> dict[str, Any]:
    return ensure_today(user_id)
