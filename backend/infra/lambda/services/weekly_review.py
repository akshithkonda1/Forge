"""Weekly ARIA evaluation — gather standing context, then coach against it.

A free chat will skip the questions that matter. This module is a structured
interview: five fields, extracted into durable facts, stored on the user so
``/ai/chat`` can remember them next week.
"""

from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from security import sanitize_user_text
from storage import dynamodb, keys

MAX_ANSWER_CHARS = 500

QUESTIONS = (
    {
        "id": "energy",
        "prompt": "How has your energy been this week?",
        "hint": "Low, mixed, or high — and what changed it.",
    },
    {
        "id": "sleep",
        "prompt": "How did you actually sleep?",
        "hint": "Hours are optional. Quality and schedule matter more.",
    },
    {
        "id": "body",
        "prompt": "Anything hurting, lingering, or off?",
        "hint": "Injuries, illness, cycle, stress. Empty is a valid answer.",
    },
    {
        "id": "focus",
        "prompt": "What should next week be about?",
        "hint": "Strength, recovery, consistency, a race, or just showing up.",
    },
    {
        "id": "remember",
        "prompt": "What should Forge remember about you?",
        "hint": "A preference, a constraint, a goal. One sentence is enough.",
    },
)

_INTERVAL_SECONDS = 6 * 24 * 3600  # due again after six days


def _now() -> datetime:
    return datetime.now(timezone.utc)


def load(user_id: str) -> dict[str, Any]:
    item = dynamodb.get_item(**keys.weekly_review_key(user_id)) or {}
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def is_due(record: dict[str, Any], *, now: datetime | None = None) -> bool:
    last = str(record.get("completed_at") or "").strip()
    if not last:
        return True
    try:
        completed = datetime.fromisoformat(last.replace("Z", "+00:00"))
    except ValueError:
        return True
    stamp = now or _now()
    if completed.tzinfo is None:
        completed = completed.replace(tzinfo=timezone.utc)
    return (stamp - completed).total_seconds() >= _INTERVAL_SECONDS


def start(user_id: str) -> dict[str, Any]:
    record = load(user_id)
    return {
        "due": is_due(record),
        "questions": list(QUESTIONS),
        "last_completed_at": record.get("completed_at"),
        "last_summary": record.get("summary"),
        "facts": list(record.get("facts") or []),
    }


def _extract_facts(answers: dict[str, str]) -> list[str]:
    facts: list[str] = []
    energy = answers.get("energy", "").strip()
    if energy:
        facts.append(f"Weekly energy: {energy}")
    sleep = answers.get("sleep", "").strip()
    if sleep:
        facts.append(f"Weekly sleep: {sleep}")
    body = answers.get("body", "").strip()
    if body:
        facts.append(f"Body note: {body}")
    focus = answers.get("focus", "").strip()
    if focus:
        facts.append(f"Next-week focus: {focus}")
    remember = answers.get("remember", "").strip()
    if remember:
        facts.append(remember)
    return facts[:8]


def _summary(answers: dict[str, str], facts: list[str]) -> str:
    if not facts:
        return "Weekly check-in logged. Nothing new to remember this time."
    bits = []
    if answers.get("energy"):
        bits.append(f"energy {answers['energy']}")
    if answers.get("focus"):
        bits.append(f"next week: {answers['focus']}")
    if answers.get("body"):
        bits.append("body note recorded")
    lead = "; ".join(bits) if bits else "check-in complete"
    return f"Weekly evaluation — {lead}."


def submit(user_id: str, answers: dict[str, Any]) -> dict[str, Any]:
    cleaned = {
        key: sanitize_user_text(str(answers.get(key) or ""), max_chars=MAX_ANSWER_CHARS)
        for key in ("energy", "sleep", "body", "focus", "remember")
    }
    facts = _extract_facts(cleaned)
    summary = _summary(cleaned, facts)
    previous = load(user_id)
    history = list(previous.get("history") or [])
    stamp = _now().isoformat()
    history.insert(0, {"completed_at": stamp, "summary": summary, "facts": facts})
    history = history[:12]
    record = {
        "completed_at": stamp,
        "answers": cleaned,
        "facts": facts,
        "summary": summary,
        "history": history,
    }
    dynamodb.put_item({**keys.weekly_review_key(user_id), **record})
    return {
        "due": False,
        "completed_at": stamp,
        "summary": summary,
        "facts": facts,
        "opening_message": (
            f"{summary} I have that on file. What do you want to go deeper on?"
        ),
    }


def briefing_for_chat(user_id: str) -> str | None:
    facts = load(user_id).get("facts") or []
    if not facts:
        return None
    return "Standing weekly context: " + " | ".join(str(f) for f in facts[:6])
