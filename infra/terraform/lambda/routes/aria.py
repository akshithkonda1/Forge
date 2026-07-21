from __future__ import annotations

from typing import Any

from responses import RouteError, ok
from services import aria_engine
from services.aria_context import CoachContextEngine
from services.feedback import FeedbackEngine

_context = CoachContextEngine()
_feedback = FeedbackEngine(_context)


def _voice_mode(body: dict[str, Any]) -> bool:
    if bool(body.get("voice_mode")):
        return True
    return str(body.get("mode") or "").strip().lower() == "voice"


def handle_post_ai_chat(body: dict[str, Any]) -> dict:
    """Layer 4 — structured ARIA chat response.

    Reasoning lives in ``services.aria_engine`` (a deterministic, fully tested
    function over the HealthKit context). This route owns only the stateful
    concerns: relationship level, memory references, and the persisted context.
    """
    user_id = str(body.get("user_id") or "").strip()
    message = str(body.get("message") or "").strip()
    if not user_id or not message:
        raise RouteError(400, "user_id and message are required.")

    voice_mode = _voice_mode(body)
    context = aria_engine.ARIAContext.from_payload(body)
    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))
    reason = aria_engine.generate_response_live if aria_engine.bedrock_enabled() else aria_engine.generate_response
    response = reason(message, context, permissions=permissions, voice_mode=voice_mode)

    # Stateful layer: persist the relationship and surface any relevant memory.
    # Memory draws on the lifestyle domain, so it is gated by that permission.
    memory = _context.memory_reference(user_id, message) if permissions.allows("lifestyle") else None
    legacy_metrics = {
        "readiness": context.readiness.recovery_score or 0,
    }
    rich = _context.build_rich_context(user_id, legacy_metrics)
    updated_level = min(10, int(rich.get("relationship_level", 1)) + 1)
    _context.update_context(user_id, {"relationship_level": updated_level})

    # Memory is a chat-surface flourish only — it must not bloat the voice prose.
    if memory and not voice_mode:
        response["message"] = f"{memory}\n\n{response['message']}"

    response.update(
        {
            "rich_card": None,
            "context_updates": {"relationship_level": updated_level},
            "memory_reference": memory,
            "missing_fields": aria_engine.apply_permissions(context, permissions)[0].missing_fields,
        }
    )
    return ok(response)


def handle_post_ai_archetype(body: dict[str, Any]) -> dict:
    """POST /ai/archetype — invent a relational coaching archetype.

    Uses a deterministic local forge so mobile clients always get a usable
    archetype offline; optional Bedrock enrichment can layer on later.
    """
    description = str(body.get("description") or "").strip()
    preferred = body.get("preferred_name")
    preferred_name = str(preferred).strip() if preferred else None
    if not description:
        raise RouteError(400, "description is required.")

    # Prefer backend studio if importable (monorepo local), else inline forge.
    try:
        import asyncio
        from backend.app.ai.routes.archetype import create_archetype

        result = asyncio.get_event_loop().run_until_complete(
            create_archetype(
                {
                    "description": description,
                    "preferred_name": preferred_name,
                    "user_id": body.get("user_id"),
                }
            )
        )
        result.pop("status", None)
        return ok(result)
    except Exception:
        pass

    d = description.lower()
    name = preferred_name or "Living Pattern"
    related = None
    speech = "Listen for their tempo. Reflect their words. Ask before advising."
    avoid = ["generic advice", "one-size-fits-all scripts"]
    formality, humor, expressiveness, length = "neutral", "none", "balanced", "medium"
    example = "I'm here. What would help right now?"
    if any(k in d for k in ("logic", "analyst", "data", "facts")):
        name = preferred_name or "Clear Signal"
        related = "analyst"
        speech = "Use clean structure: situation → need → ask."
        humor, expressiveness = "dry", "reserved"
    elif any(k in d for k in ("teen", "daughter", "sensitive")):
        name = preferred_name or "Private Flame"
        related = "sensitiveTeen"
        speech = "Very short. Validate first. No audience."
        formality, length = "casual", "terse"
        avoid = ["lectures", "public call-outs", "calm down"]
        example = "I'm not mad. Want space or a snack?"
    elif any(k in d for k in ("independent", "autonomy", "control")):
        name = preferred_name or "Open Gate"
        related = "sovereign"
        speech = "Ask permission. Offer choices. Never corner."
        avoid = ["orders", "you should"]

    archetype = {
        "id": f"arch_{abs(hash(description)) % 10_000_000}",
        "name": name,
        "slug": name.lower().replace(" ", "_"),
        "tagline": description[:160],
        "speechGuidance": speech,
        "avoid": avoid,
        "supportStance": "See them as a full person; adapt to what you know.",
        "formality": formality,
        "humor": humor,
        "expressiveness": expressiveness,
        "lengthBias": length,
        "exampleScript": example,
        "source": "backend",
        "inspiredByDescription": description,
        "relatedBuiltin": related,
    }
    return ok({"archetype": archetype, "model": "local-forge"})


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