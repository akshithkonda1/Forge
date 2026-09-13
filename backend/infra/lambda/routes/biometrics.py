"""POST /ai/observe — ingest raw health samples (incoming) plus the user's
stored metrics (already in the app), classify and fuse them into a body-model
snapshot, and project that onto the ARIA coaching context.

This is the seam where data from one source interacts with another: the request
carries fresh samples from any device/app, ``query_prefix`` pulls what's already
been written via /health/batch, and both are classified onto the same canonical
types before the body model reasons over the union.
"""

from __future__ import annotations

from dataclasses import asdict
from typing import Any

from responses import RouteError, ok
from services import aria_engine
from services import emergency
from services import fusion as fusion_mod
from storage import dynamodb, keys


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

    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))
    fused = fusion_mod.fuse_turn(
        uid,
        body,
        permissions,
        include_stored=bool(body.get("include_stored", True)),
        persist=True,
        load_learner=True,
    )
    context = fused.context

    payload: dict[str, Any] = {
        "user_id": uid,
        "classification": fused.classification
        or {"accepted": 0, "rejected": 0, "rejects": []},
        "snapshot": fused.snapshot or {},
        "aria_context": _context_payload(context),
        "restricted_domains": fused.restricted or permissions.restricted(),
        "fusion": fused.fusion_sidecar(),
    }

    # Real-time vitals safety monitor. During an active session, a sustained,
    # plausibly-real life-threatening pattern raises an escalation intent that the
    # client turns into an actual emergency call (Emergency SOS). The backend
    # decides and records; it never dials 911 itself.
    _apply_vitals_monitor(body, uid, payload)

    message = sanitize_user_text(str(body.get("message") or ""), max_chars=MAX_CHAT_MESSAGE_CHARS)
    if message:
        voice = bool(body.get("voice_mode"))
        from services import contextual_learner

        persona = fused.persona
        if fused.persona_status != "load_failed" and persona is not None:
            try:
                contextual_learner.observe_turn(
                    persona,
                    message=message,
                    tags=list(context.lifestyle.tags or []),
                    ctx=context,
                )
            except Exception as exc:  # noqa: BLE001 — named, not a silent cold-start
                fused.persona_error = f"observe_turn:{exc.__class__.__name__}: {exc}"
        response = aria_engine.generate_response(
            message,
            context,
            permissions=permissions,
            voice_mode=voice,
            persona=persona,
            baselines=fused.baselines,
        )
        payload["fusion"] = {**fused.fusion_sidecar(), **(response.get("fusion") or {})}
        if fused.persona_status != "load_failed" and persona is not None:
            try:
                brief = response.get("contextualization") if isinstance(response.get("contextualization"), dict) else {}
                plan = (response.get("fusion") or {}).get("plan") if isinstance(response.get("fusion"), dict) else None
                stance = str((plan or {}).get("stance") or brief.get("stance") or "")
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
            except Exception as exc:  # noqa: BLE001
                payload["fusion"]["persona_error"] = f"commit:{exc.__class__.__name__}: {exc}"
        payload["aria_response"] = response

    return ok(payload)
