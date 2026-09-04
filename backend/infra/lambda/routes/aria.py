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
from services import weekly_review

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
    insight_mode = str(body.get("mode") or "").strip().lower() == "insight"
    # Never trust body.user_id for context — stamp auth principal into payload.
    payload = dict(body)
    payload["user_id"] = uid
    context = aria_engine.ARIAContext.from_payload(payload)
    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))

    # Lifestyle cards: deterministic only. No Bedrock, no Dynamo relationship
    # bump, no weekly briefing. Opening a tab must not cost a chat turn.
    if insight_mode:
        response = aria_engine.generate_response(
            message, context, permissions=permissions, voice_mode=voice_mode
        )
        response.update(
            {
                "rich_card": None,
                "context_updates": {},
                "memory_reference": None,
                "missing_fields": aria_engine.apply_permissions(context, permissions)[0].missing_fields,
                "user_id": uid,
                "reasoning_source": "deterministic",
            }
        )
        return ok(response)

    weekly_note = weekly_review.briefing_for_chat(uid)
    if weekly_note:
        message = f"{weekly_note}\n\n{message}"
    roster = aria_engine.normalize_coach_agents(body.get("agents"), body.get("agent"))
    if aria_engine.bedrock_enabled():
        response = aria_engine.generate_response_live(
            message,
            context,
            permissions=permissions,
            voice_mode=voice_mode,
            agents=roster,
        )
    else:
        response = aria_engine.generate_response(
            message, context, permissions=permissions, voice_mode=voice_mode
        )
        response["agent"] = roster[0]
        response["agents"] = roster

    memory = _context.memory_reference(uid, message) if permissions.allows("lifestyle") else None
    # Phase 1: relationship only grows on non-clarification + >24h since last promotion
    # (prevents chat spam inflating trust). Uses dedicated last_promoted_at, not last_updated.
    response_type = str(response.get("response_type") or "")
    should_promote = response_type != "clarification"
    if should_promote:
        ctx_before = _context.get_or_create_context(uid)
        last_promoted = ctx_before.last_promoted_at
        if last_promoted is not None:
            from datetime import timezone
            import datetime as _dt
            now = _dt.datetime.now(timezone.utc)
            hours_since = (now - last_promoted).total_seconds() / 3600
            if hours_since < 24:
                should_promote = False
    rich = _context.build_rich_context(uid, {"readiness": context.readiness.recovery_score or 0})
    if should_promote:
        updated_level = min(10, int(rich.get("relationship_level", 1)) + 1)
        from datetime import timezone
        import datetime as _dt
        now = _dt.datetime.now(timezone.utc)
        _context.update_context(uid, {"relationship_level": updated_level, "last_promoted_at": now})
    else:
        updated_level = int(rich.get("relationship_level", 1))

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


def handle_post_ai_weekly_review(body: dict[str, Any], *, user_id: str) -> dict:
    """POST /ai/weekly-review — start or submit the weekly evaluation."""
    uid = _bind_user(body, user_id)
    phase = str(body.get("phase") or "start").strip().lower()
    if phase == "submit":
        answers = body.get("answers")
        if not isinstance(answers, dict):
            raise RouteError(400, "answers object is required.")
        return ok(weekly_review.submit(uid, answers))
    return ok(weekly_review.start(uid))


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
        from backend.ai.app.routes.archetype import create_archetype

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
