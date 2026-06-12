"""Menstrual cycle context from HealthKit-synced cycle events."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from storage import dynamodb, keys


_PHASE_ORDER = ("menstruation", "follicular", "ovulation", "luteal")


def _parse_day(value: str) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        try:
            return datetime.strptime(value[:10], "%Y-%m-%d").replace(tzinfo=timezone.utc)
        except ValueError:
            return None


def infer_cycle_phase(events: list[dict[str, Any]]) -> dict[str, Any]:
    """Infer current cycle phase from most recent menstrual-flow events."""
    if not events:
        return {
            "phase": "unknown",
            "dayInCycle": None,
            "recommendRecovery": False,
            "coachingNote": None,
            "hasData": False,
        }

    sorted_events = sorted(
        events,
        key=lambda e: str(e.get("startedAt") or e.get("date") or ""),
        reverse=True,
    )
    latest = sorted_events[0]
    flow = str(latest.get("flow") or latest.get("value") or "").lower()
    started = _parse_day(str(latest.get("startedAt") or latest.get("date") or ""))
    day_in_cycle = None
    if started:
        day_in_cycle = max(1, (datetime.now(timezone.utc) - started).days + 1)

    if "heavy" in flow or "medium" in flow or flow in ("1", "2", "menstrual"):
        phase = "menstruation"
        recommend_recovery = True
        note = "Menstruation phase — prioritize recovery and technique over max effort."
    elif "light" in flow or flow == "3":
        phase = "follicular"
        recommend_recovery = False
        note = "Early cycle — energy often rises; good window for progressive training."
    elif "ovulation" in flow or "ovulatory" in flow:
        phase = "ovulation"
        recommend_recovery = False
        note = "Ovulation window — peak power potential; monitor hydration and sleep."
    elif day_in_cycle and day_in_cycle > 21:
        phase = "luteal"
        recommend_recovery = day_in_cycle > 24
        note = "Luteal phase — consider moderating intensity if recovery markers dip."
    else:
        phase = "follicular"
        recommend_recovery = False
        note = None

    return {
        "phase": phase,
        "dayInCycle": day_in_cycle,
        "recommendRecovery": recommend_recovery,
        "coachingNote": note,
        "hasData": True,
        "lastEventAt": latest.get("startedAt") or latest.get("date"),
    }


def load_cycle_events(user_id: str, *, limit: int = 30) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "CYCLE#", limit=limit)
    return [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in items]


def cycle_training_modifier(user_id: str) -> dict[str, Any]:
    events = load_cycle_events(user_id)
    return infer_cycle_phase(events)