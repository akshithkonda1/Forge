from __future__ import annotations

from typing import Any

from responses import RouteError, ok
from security import (
    MAX_ARCHETYPE_DESCRIPTION_CHARS,
    MAX_CHAT_MESSAGE_CHARS,
    assert_body_user_matches_auth,
    sanitize_user_text,
)
from services import aria_engine
from services.aria_context import CoachContextEngine
from services.feedback import FeedbackEngine

_context = CoachContextEngine()
_feedback = FeedbackEngine(_context)


def _voice_mode(body: dict[str, Any]) -> bool:
    if bool(body.get("voice_mode")):
        return True
    return str(body.get("mode") or "").strip().lower() == "voice"


def _bind_user(body: dict[str, Any], user_id: str) -> str:
    """Authoritative principal wins; reject spoofed body user_id."""
    try:
        return assert_body_user_matches_auth(body, user_id)
    except PermissionError as exc:
        raise RouteError(403, str(exc)) from exc


def handle_post_ai_chat(body: dict[str, Any], *, user_id: str) -> dict:
    """Layer 4 — structured ARIA chat response.

    Reasoning lives in ``services.aria_engine`` (deterministic core + optional
    Bedrock). This route owns auth binding, sanitization, and relationship state.
    """
    uid = _bind_user(body, user_id)
    message = sanitize_user_text(
        str(body.get("message") or ""),
        max_chars=MAX_CHAT_MESSAGE_CHARS,
    )
    if not message:
        raise RouteError(400, "message is required.")

    voice_mode = _voice_mode(body)
    # Never trust body.user_id for context — stamp auth principal into payload.
    payload = dict(body)
    payload["user_id"] = uid
    context = aria_engine.ARIAContext.from_payload(payload)
    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))
    reason = (
        aria_engine.generate_response_live
        if aria_engine.bedrock_enabled()
        else aria_engine.generate_response
    )
    response = reason(message, context, permissions=permissions, voice_mode=voice_mode)

    memory = _context.memory_reference(uid, message) if permissions.allows("lifestyle") else None
    legacy_metrics = {
        "readiness": context.readiness.recovery_score or 0,
    }
    rich = _context.build_rich_context(uid, legacy_metrics)
    updated_level = min(10, int(rich.get("relationship_level", 1)) + 1)
    _context.update_context(uid, {"relationship_level": updated_level})

    if memory and not voice_mode:
        response["message"] = f"{memory}\n\n{response['message']}"

    response.update(
        {
            "rich_card": None,
            "context_updates": {"relationship_level": updated_level},
            "memory_reference": memory,
            "missing_fields": aria_engine.apply_permissions(context, permissions)[0].missing_fields,
            "user_id": uid,
        }
    )
    return ok(response)


def handle_post_ai_archetype(body: dict[str, Any], *, user_id: str) -> dict:
    """POST /ai/archetype — invent a relational coaching archetype."""
    uid = _bind_user(body, user_id)
    description = sanitize_user_text(
        str(body.get("description") or ""),
        max_chars=MAX_ARCHETYPE_DESCRIPTION_CHARS,
    )
    preferred = body.get("preferred_name")
    preferred_name = sanitize_user_text(str(preferred), max_chars=80) if preferred else None
    if not description:
        raise RouteError(400, "description is required.")

    try:
        import asyncio
        from backend.app.ai.routes.archetype import create_archetype

        result = asyncio.get_event_loop().run_until_complete(
            create_archetype(
                {
                    "description": description,
                    "preferred_name": preferred_name,
                    "user_id": uid,
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
    return ok({"archetype": archetype, "model": "local-forge", "user_id": uid})


def handle_post_feedback_reaction(body: dict[str, Any], *, user_id: str) -> dict:
    uid = _bind_user(body, user_id)
    message_id = sanitize_user_text(str(body.get("message_id") or ""), max_chars=128)
    reaction = sanitize_user_text(str(body.get("reaction") or ""), max_chars=64)
    if not message_id:
        raise RouteError(400, "message_id is required.")
    return ok(_feedback.process_reaction(uid, message_id, reaction))


def handle_post_feedback_plan_outcome(body: dict[str, Any], *, user_id: str) -> dict:
    uid = _bind_user(body, user_id)
    plan_id = sanitize_user_text(str(body.get("plan_id") or ""), max_chars=128)
    if not plan_id:
        raise RouteError(400, "plan_id is required.")
    completed = bool(body.get("completed", body.get("outcome") == "completed"))
    feedback = body.get("feedback")
    feedback_s = (
        sanitize_user_text(str(feedback), max_chars=500) if feedback is not None else None
    )
    return ok(_feedback.process_plan_outcome(uid, plan_id, completed, feedback_s))
