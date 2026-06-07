from __future__ import annotations

import os
from datetime import datetime, timezone
from typing import Any

from integrations import terra_client, terra_config
from integrations.terra_client import TerraAPIError, TerraConfigError
from integrations.terra_sync import request_user_backfill
from storage import dynamodb, keys


def expected_webhook_url() -> str | None:
    explicit = os.getenv("TERRA_WEBHOOK_URL")
    if explicit:
        return explicit.rstrip("/")
    api_base = os.getenv("FORGE_API_BASE_URL") or os.getenv("API_BASE_URL")
    if api_base:
        return f"{api_base.rstrip('/')}/integrations/terra/webhook"
    return None


def bootstrap() -> dict[str, Any]:
    """Validate Terra credentials and persist integration metadata for ops/health."""
    now = datetime.now(timezone.utc).isoformat()
    webhook_url = expected_webhook_url()

    if not terra_config.is_configured():
        record = {
            **keys.terra_system_key(),
            "status": "disabled",
            "configured": False,
            "webhookConfigured": terra_config.is_webhook_configured(),
            "webhookUrl": webhook_url,
            "updatedAt": now,
            "lastBootstrapAt": now,
            "apiReachable": False,
            "message": "Terra credentials are not configured.",
        }
        dynamodb.put_item(record)
        return {k: v for k, v in record.items() if k not in ("pk", "sk")}

    api_reachable = False
    api_message = "not_checked"
    try:
        ping = terra_client.ping_api()
        api_reachable = ping.get("ok", False)
        api_message = ping.get("message", "ok")
    except (TerraConfigError, TerraAPIError) as exc:
        api_message = str(exc)

    status = "ready" if api_reachable and terra_config.is_webhook_configured() else "degraded"
    if not api_reachable:
        status = "error"

    record = {
        **keys.terra_system_key(),
        "status": status,
        "configured": True,
        "webhookConfigured": terra_config.is_webhook_configured(),
        "webhookUrl": webhook_url,
        "updatedAt": now,
        "lastBootstrapAt": now,
        "apiReachable": api_reachable,
        "apiMessage": api_message,
        "message": "Terra integration bootstrapped.",
    }
    dynamodb.put_item(record)
    return {k: v for k, v in record.items() if k not in ("pk", "sk")}


def get_integration_state() -> dict[str, Any]:
    item = dynamodb.get_item(**keys.terra_system_key())
    if item:
        return {k: v for k, v in item.items() if k not in ("pk", "sk")}
    return {
        "status": "unknown",
        "configured": terra_config.is_configured(),
        "webhookConfigured": terra_config.is_webhook_configured(),
        "webhookUrl": expected_webhook_url(),
    }


def on_user_authenticated(user_id: str, provider: str) -> dict[str, Any]:
    """Self-integrate a newly linked Terra user by queueing a historical backfill."""
    result = request_user_backfill(user_id, provider=provider)
    now = datetime.now(timezone.utc).isoformat()
    dynamodb.put_item(
        {
            **keys.terra_user_heal_key(user_id),
            "lastAuthBackfillAt": now,
            "lastResult": result,
            "updatedAt": now,
        }
    )
    return result