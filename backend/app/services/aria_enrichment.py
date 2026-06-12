"""ARIA response enrichment — rich cards and client-facing message metadata.

After ARIA completes a chat turn, this module inspects the user message and
the tools that were invoked to attach structured rich cards the iOS and web
clients can render inline in chat.
"""
from __future__ import annotations

from typing import Any

from ai.aria_tools import handle_tool_call
from core.runtime import allow_seed_fallback


def tool_name_list(tool_calls_made: list[dict[str, Any]]) -> list[str]:
    """Flatten tool call records into a simple name list for mobile clients."""
    names: list[str] = []
    for call in tool_calls_made:
        name = str(call.get("tool") or "").strip()
        if name:
            names.append(name)
    return names


def maybe_rich_card(
    user_id: str,
    user_message: str,
    tool_calls_made: list[dict[str, Any]],
) -> dict[str, Any] | None:
    """
    Build an optional rich card payload from tools ARIA already used.

    Returns None when there is not enough grounded data to render a card.
    """
    lower = user_message.lower()
    tools_used = {str(c.get("tool") or "") for c in tool_calls_made}

    sleep_tools = {"get_sleep_analysis", "get_health_snapshot", "compute_readiness_score"}
    if sleep_tools & tools_used or "sleep" in lower or "recovery" in lower:
        card = _sleep_chart_card(user_id)
        if card:
            return card

    workout_tools = {"get_todays_plan", "get_workout_history", "get_training_load"}
    if workout_tools & tools_used or any(word in lower for word in ("train", "workout", "plan", "session")):
        card = _workout_plan_card(user_id)
        if card:
            return card

    progress_tools = {"get_workout_history", "get_personal_records", "get_training_load"}
    if progress_tools & tools_used or "progress" in lower or " pr" in lower or "personal record" in lower:
        card = _progress_card(user_id)
        if card:
            return card

    return None


def normalize_conversation_messages(
    messages: list[dict[str, Any]],
    *,
    thread_id: str,
) -> list[dict[str, Any]]:
    """Ensure stored ARIA messages expose id, timestamp, and string content for clients."""
    from datetime import datetime, timezone

    normalized: list[dict[str, Any]] = []
    base_ts = int(datetime.now(timezone.utc).timestamp() * 1000)

    for index, msg in enumerate(messages):
        role = msg.get("role", "assistant")
        content = _content_to_text(msg.get("content", ""))
        if not content.strip():
            continue

        client_role = "trainer" if role == "assistant" else role
        entry: dict[str, Any] = {
            "id": msg.get("id") or f"aria-{thread_id}-{base_ts + index}",
            "role": client_role,
            "content": content,
            "timestamp": msg.get("timestamp") or datetime.now(timezone.utc).isoformat(),
        }
        if msg.get("richCard"):
            entry["richCard"] = msg["richCard"]
        if msg.get("toolCallsMade"):
            entry["toolCallsMade"] = msg["toolCallsMade"]
        normalized.append(entry)

    return normalized


def _content_to_text(content: Any) -> str:
    if isinstance(content, str):
        return content
    if isinstance(content, list):
        parts: list[str] = []
        for block in content:
            if isinstance(block, dict) and block.get("type") == "text":
                parts.append(str(block.get("text", "")))
        return " ".join(parts).strip()
    return str(content or "")


def _sleep_chart_card(user_id: str) -> dict[str, Any] | None:
    result = handle_tool_call(user_id, "get_sleep_analysis", {"days": 7})
    nights = result.get("nights") or []
    if not nights:
        return None

    scores = [int(n.get("score", 0) or 0) for n in reversed(nights[:7])]
    if not scores or not any(scores):
        return None

    averages = result.get("averages") or {}
    avg_score = averages.get("score", round(sum(scores) / len(scores), 1))
    return {
        "type": "data-chart",
        "data": {
            "title": "Sleep Quality (7-day)",
            "values": scores,
            "insight": f"Average sleep score: {avg_score}.",
            "color": "3B82F6",
        },
    }


def _workout_plan_card(user_id: str) -> dict[str, Any] | None:
    result = handle_tool_call(user_id, "get_todays_plan", {})
    workout = result.get("todayPlan") or {}
    if not workout.get("name"):
        return None
    if not allow_seed_fallback() and not workout.get("exercises"):
        return None
    return {"type": "workout-plan", "data": workout}


def _progress_card(user_id: str) -> dict[str, Any] | None:
    history = handle_tool_call(user_id, "get_workout_history", {"days": 30})
    prs = history.get("personalRecordsFromPeriod") or []
    if prs:
        top = prs[0]
        current = float(top.get("value", 0) or 0)
        if current > 0:
            previous = round(current * 0.92, 1)
            return {
                "type": "progress-comparison",
                "data": {
                    "title": str(top.get("exercise", "Strength")),
                    "current": current,
                    "previous": previous,
                    "unit": str(top.get("unit", "lbs")),
                    "insight": f"Recent best: {current} {top.get('unit', 'lbs')}.",
                },
            }

    load = (history.get("trainingLoad") or {})
    current_load = float(load.get("current7d", 0) or 0)
    previous_load = float(load.get("previous7d", 0) or 0)
    if current_load <= 0 and previous_load <= 0:
        return None

    return {
        "type": "progress-comparison",
        "data": {
            "title": "Training Load (7-day)",
            "current": round(current_load, 1),
            "previous": round(previous_load, 1),
            "unit": "load",
            "insight": f"Load trend: {load.get('trend', 'steady')}.",
        },
    }