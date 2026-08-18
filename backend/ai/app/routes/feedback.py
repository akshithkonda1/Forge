from __future__ import annotations

from typing import Any

from backend.app.ai.services.coach_context import CoachContextEngine
from backend.app.ai.services.feedback import FeedbackEngine

_context = CoachContextEngine()
_feedback = FeedbackEngine(_context)


async def handle_feedback_reaction(payload: dict[str, Any]) -> dict[str, Any]:
    """Layer 3 — reaction on a message updates relationship level."""
    user_id = str(payload.get("user_id") or "")
    message_id = str(payload.get("message_id") or "")
    reaction = str(payload.get("reaction") or "")
    if not user_id or not message_id:
        return {"error": "user_id and message_id required", "status": 400}
    return await _feedback.process_reaction(user_id, message_id, reaction)


async def handle_feedback_plan_outcome(payload: dict[str, Any]) -> dict[str, Any]:
    """Layer 3 — plan completion/skip is recorded as an insight."""
    user_id = str(payload.get("user_id") or "")
    plan_id = str(payload.get("plan_id") or "")
    if not user_id or not plan_id:
        return {"error": "user_id and plan_id required", "status": 400}
    completed = bool(payload.get("completed"))
    feedback = payload.get("feedback")
    return await _feedback.process_plan_outcome(user_id, plan_id, completed, feedback)
