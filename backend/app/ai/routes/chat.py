from __future__ import annotations

from typing import Any

from backend.app.ai.models.context import AriaChatRequest, AriaResponse
from backend.app.ai.services.coach_context import CoachContextEngine
from backend.app.ai.services.feedback import FeedbackEngine

_context = CoachContextEngine()
_feedback = FeedbackEngine(_context)


async def chat_with_aria(payload: dict[str, Any]) -> dict[str, Any]:
    """Layer 4 — structured ARIA chat response."""
    request = AriaChatRequest.from_payload(payload)
    if not request.user_id or not request.message:
        return {"error": "user_id and message are required", "status": 400}

    rich = await _context.build_rich_context(request.user_id, request.recent_metrics)
    memory = await _context.memory_reference(request.user_id, request.message)

    readiness = request.recent_metrics.get("readiness", 0)
    if readiness < 55:
        message = (
            "Based on your recovery signals, I recommend prioritizing rest and mobility today. "
            "We can keep intensity low and focus on sleep quality tonight."
        )
        actions = ["Show recovery plan", "Adjust workout", "Review sleep"]
    elif readiness >= 85:
        message = (
            "You're primed. This is a strong day to push performance — "
            "want me to line up a challenging session?"
        )
        actions = ["Build workout", "Review readiness", "Set a PR target"]
    else:
        message = (
            "You're in a solid training band. Let's match today's session to your readiness "
            "and keep progressive overload controlled."
        )
        actions = ["Today's workout", "Tune nutrition", "Check sleep trend"]

    if memory:
        message = f"{memory}\n\n{message}"

    updated_level = min(10, rich.get("relationship_level", 1) + 1)
    await _context.update_context(request.user_id, {"relationship_level": updated_level})

    response = AriaResponse(
        message=message,
        rich_card=None,
        suggested_actions=actions,
        context_updates={"relationship_level": updated_level},
        confidence=0.88 if memory else 0.82,
        memory_reference=memory,
    )
    return response.to_dict()


async def handle_feedback_reaction(payload: dict[str, Any]) -> dict[str, Any]:
    user_id = str(payload.get("user_id") or "")
    message_id = str(payload.get("message_id") or "")
    reaction = str(payload.get("reaction") or "")
    if not user_id or not message_id:
        return {"error": "user_id and message_id required", "status": 400}
    return await _feedback.process_reaction(user_id, message_id, reaction)


async def handle_feedback_plan_outcome(payload: dict[str, Any]) -> dict[str, Any]:
    user_id = str(payload.get("user_id") or "")
    plan_id = str(payload.get("plan_id") or "")
    if not user_id or not plan_id:
        return {"error": "user_id and plan_id required", "status": 400}
    completed = bool(payload.get("completed"))
    feedback = payload.get("feedback")
    return await _feedback.process_plan_outcome(user_id, plan_id, completed, feedback)