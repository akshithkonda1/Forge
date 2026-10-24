"""POST /ai/observe — health samples are not accepted or stored.

HealthKit ingest, Health Scout completeness, BodyModel, and daily story
run on-device. This route may still carry a coaching message (voice) so
ARIA can answer without a health warehouse. ``samples`` / ``vitals`` are
stripped; nothing is written to METRIC# or ARIA#BODY_SNAPSHOT.
"""

from __future__ import annotations

from dataclasses import asdict
from typing import Any

from responses import RouteError, ok
from aria_core import aria_engine
from services import daily_story as daily_story_mod
from services import emergency
from aria_core import fusion as fusion_mod
from services.aria_context import CoachContextEngine
from storage import dynamodb, keys

_context = CoachContextEngine()


def _context_payload(ctx: aria_engine.ARIAContext) -> dict[str, Any]:
    payload = asdict(ctx)
    payload["missing_fields"] = ctx.missing_fields
    return payload


def _apply_vitals_monitor(body: dict[str, Any], uid: str, payload: dict[str, Any]) -> None:
    """Assess a ``vitals`` window for a life-threatening pattern and, when found,
    fire + record an emergency escalation intent for the client to act on."""
    vitals_raw = body.get("vitals")
    if vitals_raw is None:
        return
    raw_list = vitals_raw if isinstance(vitals_raw, list) else [vitals_raw]
    window = [
        emergency.VitalsSample.from_dict(s) for s in raw_list[:50] if isinstance(s, dict)
    ]
    if not window:
        return

    session_active = bool(body.get("session_active", True))
    assessment = emergency.assess_vitals(window, session_active=session_active)
    payload["emergency"] = assessment.to_dict()

    if not assessment.escalate:
        payload["escalation"] = {"triggered": False}
        return

    intent = emergency.maybe_escalate(assessment, user_id=uid)
    # Audit trail: an escalation decision must be recoverable after the fact.
    if intent is not None:
        key = keys.emergency_event_key(uid, intent.at.isoformat())
        dynamodb.put_item({"pk": key["pk"], "sk": key["sk"], "intent": intent.to_dict()})
        payload["escalation"] = {
            "triggered": True,
            "action": intent.action,
            "client_action": intent.client_action,
            "channels": intent.channels,
            "reasons": intent.reasons,
            "severity": intent.severity,
        }


def handle_post_observe(body: dict[str, Any], *, user_id: str | None = None) -> dict:
    from security import (
        MAX_CHAT_MESSAGE_CHARS,
        assert_body_user_matches_auth,
        sanitize_user_text,
    )

    # Prefer JWT-bound principal; reject spoofed body user_id.
    auth_uid = (user_id or "").strip()
    if auth_uid:
        try:
            uid = assert_body_user_matches_auth(body, auth_uid)
        except PermissionError as exc:
            raise RouteError(403, str(exc)) from exc
    else:
        uid = str(body.get("user_id") or "").strip()
        if not uid:
            raise RouteError(400, "user_id is required.")

    incoming = body.get("samples")
    raw: list[Any] = list(incoming) if isinstance(incoming, list) else []
    # Cap sample batch size to bound CPU / memory on abuse.
    if len(raw) > 500:
        raise RouteError(400, "samples batch too large (max 500).")

    # Health payloads are not accepted or persisted. BodyModel lives on-device.
    health_rejected = len(raw)
    if body.get("vitals") is not None:
        health_rejected += 1
    body = {
        k: v
        for k, v in body.items()
        if k not in ("samples", "vitals", "include_stored")
    }
    body["include_stored"] = False

    message = sanitize_user_text(str(body.get("message") or ""), max_chars=MAX_CHAT_MESSAGE_CHARS)

    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))
    fused = fusion_mod.fuse_turn(
        uid,
        body,
        permissions,
        include_stored=False,
        persist=False,
        load_learner=True,
    )
    context = fused.context

    payload: dict[str, Any] = {
        "user_id": uid,
        "classification": {
            "accepted": 0,
            "rejected": health_rejected,
            "rejects": (
                [{"reason": "health_stays_on_device"}] * health_rejected
                if health_rejected
                else []
            ),
        },
        "snapshot": {},
        "aria_context": _context_payload(context),
        "restricted_domains": fused.restricted or permissions.restricted(),
        "fusion": {**fused.fusion_sidecar(), "health_persisted": False},
        "daily_story": None,
        "notice": "Health data always stays on device, never goes to a server.",
    }

    # Vitals are health data. Do not persist an emergency audit of them.

    from aria_core import contextual_learner

    persona = fused.persona
    if fused.persona_status != "load_failed" and persona is not None:
        try:
            if message:
                contextual_learner.observe_turn(
                    persona,
                    message=message,
                    tags=list(context.lifestyle.tags or []),
                    ctx=context,
                )
            else:
                from aria_core import context_plan

                context_plan.evaluate_and_store(persona, "", context)
                contextual_learner.save(uid, persona)
        except fusion_mod.PERSONA_IO_ERRORS as exc:
            fused.persona_error = f"observe_turn:{exc.__class__.__name__}: {exc}"
        if isinstance(getattr(persona, "last_plan", None), dict):
            payload["supervision_plan"] = dict(persona.last_plan)

    if message:
        # /ai/chat stamps companion memory (last_insights/current_goals/
        # constraints) onto context before generating a response
        # (routes/aria.py) so user_model_block() and _companion_callback()
        # can speak from it. This path also calls generate_response with a
        # message (voice mode in particular) and was missing the same stamp.
        from services import editable_memory

        mem_settings = editable_memory.get_settings(uid)
        if permissions.allows("lifestyle") and editable_memory.auto_ingest_allowed(mem_settings):
            living = _context.get_or_create_context(uid)
            contextual_learner.stamp_living_context(context, living)

        voice = bool(body.get("voice_mode"))
        from aria_core import prompt_guard

        response = prompt_guard.checked(
            lambda: aria_engine.generate_response(
                message,
                context,
                permissions=permissions,
                voice_mode=voice,
                persona=persona,
                baselines=fused.baselines,
            )
        )
        payload["fusion"] = {**fused.fusion_sidecar(), **(response.get("fusion") or {})}
        if fused.persona_status != "load_failed" and persona is not None:
            try:
                brief = response.get("contextualization") if isinstance(response.get("contextualization"), dict) else {}
                stance = str((response.get("fusion") or {}).get("stance") or brief.get("stance") or "")
                contextual_learner.commit_action(
                    persona,
                    str(brief.get("bucket") or ""),
                    stance,
                    brief.get("specialists") or [],
                    event_bucket_key=brief.get("event_bucket"),
                    priority=brief.get("prioritize"),
                    stance_p=float((brief.get("stance_probs") or {}).get(stance, 0.0) or 0.0),
                    sources=brief.get("sources") or (),
                )
                contextual_learner.save(uid, persona)
            except fusion_mod.PERSONA_IO_ERRORS as exc:
                payload["fusion"]["persona_error"] = f"commit:{exc.__class__.__name__}: {exc}"
        payload["aria_response"] = response

    return ok(payload)
