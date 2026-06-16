from __future__ import annotations

from typing import Any

from responses import RouteError, ok
from services.aria_context import CoachContextEngine
from services.feedback import FeedbackEngine

_context = CoachContextEngine()
_feedback = FeedbackEngine(_context)


def _parse_metrics(raw: Any) -> dict[str, float]:
    if not isinstance(raw, dict):
        return {}
    metrics: dict[str, float] = {}
    for key, value in raw.items():
        try:
            metrics[str(key)] = float(value)
        except (TypeError, ValueError):
            continue
    return metrics


def handle_post_ai_chat(body: dict[str, Any]) -> dict:
    """Layer 4 — structured ARIA chat response."""
    user_id = str(body.get("user_id") or "").strip()
    message = str(body.get("message") or "").strip()
    if not user_id or not message:
        raise RouteError(400, "user_id and message are required.")

    recent_metrics = _parse_metrics(body.get("recent_metrics"))
    rich = _context.build_rich_context(user_id, recent_metrics)
    memory = _context.memory_reference(user_id, message)

    readiness = recent_metrics.get("readiness", 0)
    if readiness < 55:
        reply = (
            "Based on your recovery signals, I recommend prioritizing rest and mobility today. "
            "We can keep intensity low and focus on sleep quality tonight."
        )
        actions = ["Show recovery plan", "Adjust workout", "Review sleep"]
    elif readiness >= 85:
        reply = (
            "You're primed. This is a strong day to push performance — "
            "want me to line up a challenging session?"
        )
        actions = ["Build workout", "Review readiness", "Set a PR target"]
    else:
        reply = (
            "You're in a solid training band. Let's match today's session to your readiness "
            "and keep progressive overload controlled."
        )
        actions = ["Today's workout", "Tune nutrition", "Check sleep trend"]

    if memory:
        reply = f"{memory}\n\n{reply}"

    updated_level = min(10, int(rich.get("relationship_level", 1)) + 1)
    _context.update_context(user_id, {"relationship_level": updated_level})

    return ok(
        {
            "message": reply,
            "rich_card": None,
            "suggested_actions": actions,
            "context_updates": {"relationship_level": updated_level},
            "confidence": 0.88 if memory else 0.82,
            "memory_reference": memory,
        }
    )


def handle_post_feedback_reaction(body: dict[str, Any]) -> dict:
    user_id = str(body.get("user_id") or "").strip()
    message_id = str(body.get("message_id") or "").strip()
    reaction = str(body.get("reaction") or "")
    if not user_id or not message_id:
        raise RouteError(400, "user_id and message_id are required.")
    return ok(_feedback.process_reaction(user_id, message_id, reaction))


def handle_post_feedback_plan_outcome(body: dict[str, Any]) -> dict:
    user_id = str(body.get("user_id") or "").strip()
    plan_id = str(body.get("plan_id") or "").strip()
    if not user_id or not plan_id:
        raise RouteError(400, "user_id and plan_id are required.")
    completed = bool(body.get("completed"))
    feedback = body.get("feedback")
    feedback_text = str(feedback) if feedback is not None else None
    return ok(_feedback.process_plan_outcome(user_id, plan_id, completed, feedback_text))