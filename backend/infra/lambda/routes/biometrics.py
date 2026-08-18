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
from services.biometrics import BodyModel, classify_batch
from services.biometrics.body_model import redact_snapshot
from storage import dynamodb, keys


def _load_stored_metrics(user_id: str) -> list[dict[str, Any]]:
    """Metrics already written to the app (via /health/batch) for this user."""
    return dynamodb.query_prefix(keys.user_pk(user_id), "METRIC#")


def _age(body: dict[str, Any]) -> float | None:
    raw = body.get("age_years", body.get("age"))
    try:
        return float(raw) if raw is not None else None
    except (TypeError, ValueError):
        return None


def _context_payload(ctx: aria_engine.ARIAContext) -> dict[str, Any]:
    payload = asdict(ctx)
    payload["missing_fields"] = ctx.missing_fields
    return payload


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
    if body.get("include_stored", True):
        raw.extend(_load_stored_metrics(uid))

    result = classify_batch(raw)
    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))
    model = BodyModel.from_observations(result.observations, age_years=_age(body))
    snapshot = model.snapshot()
    context = model.to_aria_context(permissions)

    payload: dict[str, Any] = {
        "user_id": uid,
        "classification": {
            **result.counts,
            "rejects": [r.to_dict() for r in result.rejects][:25],
        },
        "snapshot": redact_snapshot(snapshot.to_dict(), permissions),
        "aria_context": _context_payload(context),
        "restricted_domains": permissions.restricted(),
    }

    message = sanitize_user_text(str(body.get("message") or ""), max_chars=MAX_CHAT_MESSAGE_CHARS)
    if message:
        voice = bool(body.get("voice_mode"))
        payload["aria_response"] = aria_engine.generate_response(
            message, context, permissions=permissions, voice_mode=voice
        )

    return ok(payload)
