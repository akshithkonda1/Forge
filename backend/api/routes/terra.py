from __future__ import annotations

from typing import Any

from integrations import terra_client, terra_config, terra_webhooks
from integrations.terra_client import TerraAPIError, TerraConfigError
from integrations.terra_self_healing import assess_health, get_last_heal_run, heal
from integrations.terra_self_integration import bootstrap, get_integration_state
from integrations.terra_webhooks import WebhookVerificationError
from ops_auth import require_ops_token
from responses import RouteError, ok
from storage import dynamodb, keys


def _header(headers: dict[str, str], name: str) -> str:
    lowered = {k.lower(): v for k, v in headers.items()}
    return lowered.get(name.lower(), "")


def handle_post_webhook(raw_body: str, headers: dict[str, str]) -> dict:
    signing_secret = terra_config.webhook_secret()
    if not signing_secret:
        raise RouteError(503, "Terra webhook signing secret is not configured.", code="terra_not_configured")

    signature = _header(headers, "terra-signature")
    try:
        terra_webhooks.verify_signature(
            raw_body=raw_body,
            signature_header=signature,
            signing_secret=signing_secret,
        )
    except WebhookVerificationError as exc:
        raise RouteError(401, str(exc), code="terra_signature_invalid") from exc

    result = terra_webhooks.handle_webhook_event(raw_body)
    return ok(result)


def handle_post_widget(user_id: str, body: dict[str, Any]) -> dict:
    if not terra_client.is_configured():
        raise RouteError(503, "Terra API credentials are not configured.", code="terra_not_configured")

    success_url = body.get("successRedirectUrl")
    failure_url = body.get("failureRedirectUrl")
    if not success_url or not failure_url:
        raise RouteError(
            400,
            "Request body must include successRedirectUrl and failureRedirectUrl.",
            code="invalid_request",
        )

    try:
        session = terra_client.generate_widget_session(
            reference_id=user_id,
            success_redirect_url=str(success_url),
            failure_redirect_url=str(failure_url),
            language=str(body.get("language", "en")),
        )
    except TerraConfigError as exc:
        raise RouteError(503, str(exc), code="terra_not_configured") from exc
    except TerraAPIError as exc:
        raise RouteError(exc.status, f"Terra widget session failed: {exc}", code="terra_api_error") from exc

    return ok(
        {
            "referenceId": user_id,
            "sessionId": session.get("session_id") or session.get("id"),
            "url": session.get("url") or session.get("auth_url"),
            "expiresAt": session.get("expires_at"),
            "status": session.get("status", "created"),
        }
    )


def handle_get_status(user_id: str) -> dict:
    ref = dynamodb.get_item(**keys.terra_ref_key(user_id))
    return ok(
        {
            "configured": terra_client.is_configured(),
            "connected": bool(ref and ref.get("terraUserId")),
            "provider": ref.get("provider") if ref else None,
            "lastUpdatedAt": ref.get("updatedAt") if ref else None,
        }
    )


def handle_get_integration_health() -> dict:
    assessment = assess_health()
    last_heal = get_last_heal_run()
    return ok(
        {
            "healthy": assessment["healthy"],
            "integration": assessment["integration"],
            "webhookUrl": assessment["webhookUrl"],
            "staleConnections": assessment["staleConnections"],
            "stuckSyncing": assessment["stuckSyncing"],
            "lastHeal": last_heal,
            "checkedAt": assessment["checkedAt"],
        }
    )


def handle_post_self_integrate() -> dict:
    result = bootstrap()
    return ok(result)


def handle_post_self_heal() -> dict:
    summary = heal()
    return ok(
        {
            "healthy": summary["assessment"]["healthy"],
            "repairedCount": summary["repairedCount"],
            "failureCount": summary["failureCount"],
            "staleConnections": summary["assessment"]["staleConnections"],
            "healedAt": summary["healedAt"],
            "repaired": summary["repaired"],
            "failures": summary["failures"],
        }
    )


def handle_scheduled_self_heal() -> dict:
    summary = heal()
    return ok(
        {
            "source": "scheduled",
            "healthy": summary["assessment"]["healthy"],
            "repairedCount": summary["repairedCount"],
            "failureCount": summary["failureCount"],
            "healedAt": summary["healedAt"],
        }
    )