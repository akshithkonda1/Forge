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
from services import elevenlabs_voice
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


def _lifestyle_tags(context: Any, living: Any, permissions: Any) -> list[str]:
    tags: list[str] = []
    if not permissions.allows("lifestyle"):
        return tags
    tags = list(context.lifestyle.tags or [])
    for tag in getattr(living, "lifestyle_tags", None) or []:
        if tag not in tags:
            tags.append(tag)
    return tags


def _merge_fusion(response: dict[str, Any], fused: Any) -> None:
    sidecar = fused.fusion_sidecar(None)
    existing = response.get("fusion") if isinstance(response.get("fusion"), dict) else {}
    response["fusion"] = {**sidecar, **existing}


def handle_post_ai_chat(body: dict[str, Any], *, user_id: str) -> dict:
    """Layer 4 — structured ARIA chat response.

    Reasoning lives in ``services.aria_engine`` (deterministic core + optional
    Bedrock). This route owns auth binding, sanitization, and relationship state.
    Body truth comes from the same ``fusion.fuse_turn`` path ``/ai/observe`` uses.
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
    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))

    from services import contextual_learner
    from services import fusion as fusion_mod

    fused = fusion_mod.fuse_turn(uid, payload, permissions, persist=True, load_learner=True)
    context = fused.context
    persona = fused.persona
    living = _context.get_or_create_context(uid)
    tags = _lifestyle_tags(context, living, permissions)
    if permissions.allows("lifestyle"):
        contextual_learner.stamp_living_context(context, living)

    # Lifestyle cards: deterministic only. No Bedrock, no Dynamo relationship
    # bump, no weekly briefing, no learner write-back. Opening a tab must not
    # cost a chat turn — but it still consumes the fused snapshot + current
    # stance so the card is not a second picture of the body.
    if insight_mode:
        response = aria_engine.generate_response(
            message,
            context,
            permissions=permissions,
            voice_mode=voice_mode,
            persona=persona,
            baselines=fused.baselines,
        )
        _merge_fusion(response, fused)
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

    if fused.persona_status != "load_failed" and persona is not None:
        try:
            contextual_learner.observe_turn(
                persona,
                message=message,
                tags=tags,
                relationship_level=living.relationship_level,
                ctx=context,
            )
        except Exception as exc:  # noqa: BLE001 — named on the envelope, not a silent cold-start
            fused.persona_error = f"observe_turn:{exc.__class__.__name__}: {exc}"

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
            persona=persona,
            baselines=fused.baselines,
        )
    else:
        response = aria_engine.generate_response(
            message,
            context,
            permissions=permissions,
            voice_mode=voice_mode,
            persona=persona,
            baselines=fused.baselines,
        )
        response["agent"] = roster[0]
        response["agents"] = roster
    _merge_fusion(response, fused)

    # Companion memory (lifestyle-gated): ingest calendar, run ARIA's daily
    # self-evaluation once per day, and offer a daily check-in. All deterministic
    # and side-effect-scoped to the user's own memory.
    memory_block = ""
    checkin_payload: dict[str, Any] | None = None
    calendar_ingested: list[dict[str, Any]] = []
    if permissions.allows("lifestyle"):
        events = body.get("calendar_events")
        if isinstance(events, list):
            calendar_ingested = [m.to_dict() for m in _context.ingest_calendar_events(uid, events)]
        if _context.needs_daily_evaluation(uid):
            _context.evaluate_memory(uid)
        checkin = _context.daily_checkin(uid)
        checkin_payload = checkin.to_dict() if checkin else None
        memory_block = _context.memory_prompt_block(uid)

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

    brief = response.get("contextualization") if isinstance(response.get("contextualization"), dict) else {}
    plan = (response.get("fusion") or {}).get("plan") if isinstance(response.get("fusion"), dict) else None
    shipped_stance = ""
    if isinstance(plan, dict):
        shipped_stance = str(plan.get("stance") or "")
    if not shipped_stance:
        shipped_stance = str(brief.get("stance") or "")
    if persona is not None and fused.persona_status != "load_failed":
        try:
            probs = brief.get("stance_probs") or {}
            stance = shipped_stance or str(brief.get("stance") or "")
            stance_p = 0.0
            if isinstance(probs, dict) and stance:
                try:
                    stance_p = float(probs.get(stance, 0.0) or 0.0)
                except (TypeError, ValueError):
                    stance_p = 0.0
            sources = brief.get("sources") or ()
            contextual_learner.commit_action(
                persona,
                str(brief.get("bucket") or ""),
                stance,
                brief.get("specialists") or [],
                event_bucket_key=brief.get("event_bucket"),
                priority=brief.get("prioritize"),
                stance_p=stance_p,
                sources=sources,
            )
            contextual_learner.observe_relationship(persona, updated_level)
            contextual_learner.save(uid, persona)
        except Exception as exc:  # noqa: BLE001 — surface; do not pretend this was a cold start
            response.setdefault("fusion", {})
            if isinstance(response["fusion"], dict):
                response["fusion"]["persona_error"] = f"commit:{exc.__class__.__name__}: {exc}"
                response["fusion"]["persona_status"] = fused.persona_status

    if memory and not voice_mode:
        response["message"] = f"{memory}\n\n{response['message']}"

    response.update(
        {
            "rich_card": None,
            "context_updates": {"relationship_level": updated_level},
            "memory_reference": memory,
            "memory": memory_block or None,
            "checkin": checkin_payload,
            "calendar_ingested": calendar_ingested,
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

        payload = {
            "description": description,
            "preferred_name": preferred_name,
            "user_id": uid,
        }
        try:
            result = asyncio.run(create_archetype(payload))
        except RuntimeError:
            result = asyncio.get_event_loop().run_until_complete(create_archetype(payload))
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


def handle_get_ai_voice_bootstrap(body: dict[str, Any] | None, *, user_id: str) -> dict:
    """GET /ai/voice/bootstrap — mint a short-lived ConvAI signed URL.

    Dummy / Device Hub never calls this; the app short-circuits locally.
    The response is a WebSocket URL, never ``ELEVENLABS_API_KEY``.
    """
    payload = elevenlabs_voice.mint_signed_url(user_id=user_id, body=body or {})
    return ok(payload)


def handle_post_ai_voice_tool(body: dict[str, Any], *, user_id: str) -> dict:
    """POST /ai/voice/tool — ConvAI client tools into ``aria_engine``."""
    uid = _bind_user(body, user_id)
    return ok(elevenlabs_voice.run_tool(body, user_id=uid))


def handle_post_ai_voice_design(body: dict[str, Any], *, user_id: str) -> dict:
    """POST /ai/voice/design — ops Voice Design. Persist the returned ids."""
    _bind_user(body, user_id)
    preview_index = int(body.get("preview_index") or 0)
    return ok(elevenlabs_voice.design_aria(preview_index=preview_index))
