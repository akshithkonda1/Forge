from __future__ import annotations

from typing import Any

from backend.app.ai.models.context import AriaChatRequest, AriaResponse
from backend.app.ai.services.coach_context import CoachContextEngine

_context = CoachContextEngine()


async def chat_with_aria(payload: dict[str, Any]) -> dict[str, Any]:
    """DEPRECATED — Phase 1: legacy recent_metrics path.

    Kept for backward compat only; all new clients use
    backend.infra.lambda.services.aria_engine + ARIAContext (structured domains).
    This now delegates to the canonical engine and logs a deprecation warning.
    Do not add new logic here.
    """
    import warnings

    warnings.warn(
        "backend.ai.app.routes.chat.chat_with_aria is deprecated — use backend.infra.lambda.services.aria_engine.generate_response",
        DeprecationWarning,
        stacklevel=2,
    )

    # If payload already carries structured ARIAContext, delegate directly
    if any(k in payload for k in ("sleep", "readiness", "lifestyle", "nutrition", "activity")):
        try:
            from backend.infra.lambda.services import aria_engine as _canonical

            ctx = _canonical.ARIAContext.from_payload(payload)
            perms = _canonical.DataPermissions.from_payload(payload.get("permissions"))
            resp = _canonical.generate_response(
                str(payload.get("message") or ""),
                ctx,
                permissions=perms,
                voice_mode=str(payload.get("mode") or "").strip().lower() == "voice",
            )
            # Map canonical envelope to legacy shape
            return {
                "message": resp.get("prose_summary") or resp.get("message") or "",
                "suggested_actions": resp.get("suggested_actions") or [],
                "context_updates": resp.get("context_updates") or {},
                "confidence": resp.get("confidence") or 0.82,
                "reasoning_source": resp.get("reasoning_source") or "deterministic",
                "deprecation": "recent_metrics path is deprecated",
            }
        except Exception:
            pass
    request = AriaChatRequest.from_payload(payload)
    if not request.user_id or not request.message:
        return {"error": "user_id and message are required", "status": 400}

    insight_mode = str(payload.get("mode") or "").strip().lower() == "insight"
    if insight_mode:
        readiness = request.recent_metrics.get("readiness")
        if readiness is not None and readiness < 55:
            message = "Recovery looks low. Keep today light — water, a walk, earlier sleep."
        elif readiness is not None and readiness >= 85:
            message = "You're primed. One focused session is enough — don't stack extras."
        else:
            message = "Solid day. Pick one small change and let it compound."
        return {
            "message": message,
            "suggested_actions": [],
            "context_updates": {},
            "confidence": 0.8,
            "reasoning_source": "deterministic",
        }

    rich = await _context.build_rich_context(request.user_id, request.recent_metrics)
    memory = await _context.memory_reference(request.user_id, request.message)

    readiness = request.recent_metrics.get("readiness")
    if readiness is not None and readiness < 55:
        message = (
            "Based on your recovery signals, I recommend prioritizing rest and mobility today. "
            "We can keep intensity low and focus on sleep quality tonight."
        )
        actions = ["Show recovery plan", "Adjust workout", "Review sleep"]
    elif readiness is not None and readiness >= 85:
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


