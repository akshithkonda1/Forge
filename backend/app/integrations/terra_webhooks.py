from __future__ import annotations

import hashlib
import hmac
import json
import time
from datetime import datetime, timezone
from typing import Any

from integrations import terra_config, terra_normalizer
from integrations.terra_self_integration import on_user_authenticated
from storage import dynamodb, keys

_SIGNATURE_TOLERANCE_SECONDS = 300


class WebhookVerificationError(ValueError):
    pass


def verify_signature(*, raw_body: str, signature_header: str, signing_secret: str) -> None:
    if not signature_header or not signing_secret:
        raise WebhookVerificationError("Missing Terra webhook signature or signing secret.")

    parts: dict[str, list[str]] = {}
    for piece in signature_header.split(","):
        if "=" not in piece:
            continue
        key, value = piece.split("=", 1)
        parts.setdefault(key.strip(), []).append(value.strip())

    timestamp = (parts.get("t") or [None])[0]
    signatures = parts.get("v1") or []
    if not timestamp or not signatures:
        raise WebhookVerificationError("Malformed terra-signature header.")

    age = abs(int(time.time()) - int(timestamp))
    if age > _SIGNATURE_TOLERANCE_SECONDS:
        raise WebhookVerificationError("Terra webhook timestamp is outside the tolerance window.")

    signed_payload = f"{timestamp}.{raw_body}"
    expected = hmac.new(
        signing_secret.encode("utf-8"),
        signed_payload.encode("utf-8"),
        hashlib.sha256,
    ).hexdigest()

    if not any(hmac.compare_digest(expected, candidate) for candidate in signatures):
        raise WebhookVerificationError("Terra webhook signature mismatch.")


def _resolve_user_id(payload: dict[str, Any]) -> str | None:
    user = payload.get("user") or {}
    reference_id = user.get("reference_id")
    if reference_id:
        ref_item = dynamodb.get_item(pk=f"REF#{reference_id}", sk="USER")
        if ref_item:
            return ref_item.get("userId")

    terra_user_id = user.get("user_id") or payload.get("user_id")
    if terra_user_id:
        mapping = dynamodb.get_item(**keys.terra_user_key(str(terra_user_id)))
        if mapping:
            return mapping.get("userId")
    return None


def _upsert_connection(user_id: str, provider: str, *, status: str, terra_user_id: str | None = None) -> None:
    forge_provider = terra_normalizer.map_provider(provider)
    now = datetime.now(timezone.utc).isoformat()
    item = {
        **keys.connection_key(user_id, forge_provider),
        "provider": forge_provider,
        "displayName": terra_normalizer.display_name(provider),
        "status": status,
        "middleware": "terra",
        "updatedAt": now,
    }
    if status == "connected":
        item["lastSyncedAt"] = now
    if terra_user_id:
        item["terraUserId"] = terra_user_id
    dynamodb.put_item(item)


def _store_terra_mapping(user_id: str, terra_user_id: str, provider: str, reference_id: str | None) -> None:
    now = datetime.now(timezone.utc).isoformat()
    dynamodb.put_item(
        {
            **keys.terra_user_key(terra_user_id),
            "userId": user_id,
            "provider": provider,
            "referenceId": reference_id,
            "updatedAt": now,
        }
    )
    dynamodb.put_item(
        {
            **keys.terra_ref_key(user_id),
            "terraUserId": terra_user_id,
            "provider": provider,
            "referenceId": reference_id or user_id,
            "updatedAt": now,
        }
    )
    if reference_id:
        dynamodb.put_item({"pk": f"REF#{reference_id}", "sk": "USER", "userId": user_id, "updatedAt": now})


def handle_webhook_event(raw_body: str) -> dict[str, Any]:
    payload = json.loads(raw_body or "{}")
    event_type = str(payload.get("type", "")).lower()
    user_id = _resolve_user_id(payload)

    if event_type in {"auth", "user_reauth"}:
        if not user_id:
            return {"handled": False, "reason": "unknown_user", "type": event_type}
        user = payload.get("user") or {}
        terra_user_id = str(user.get("user_id", ""))
        provider = str(user.get("provider", "UNKNOWN"))
        reference_id = user.get("reference_id")
        if terra_user_id:
            _store_terra_mapping(user_id, terra_user_id, provider, reference_id)
        _upsert_connection(user_id, provider, status="connected", terra_user_id=terra_user_id or None)
        backfill = on_user_authenticated(user_id, provider)
        return {
            "handled": True,
            "type": event_type,
            "userId": user_id,
            "provider": provider,
            "backfill": backfill,
        }

    if event_type == "deauth":
        if not user_id:
            return {"handled": False, "reason": "unknown_user", "type": event_type}
        user = payload.get("user") or {}
        provider = str(user.get("provider", "UNKNOWN"))
        _upsert_connection(user_id, provider, status="needs-auth")
        return {"handled": True, "type": event_type, "userId": user_id, "provider": provider}

    if not user_id:
        return {"handled": False, "reason": "unknown_user", "type": event_type}

    if event_type == "sleep":
        session = terra_normalizer.normalize_sleep(payload)
        if session:
            dynamodb.put_item({**keys.sleep_key(user_id, session["date"], session["source"]), **session})
        return {"handled": True, "type": event_type, "userId": user_id}

    if event_type == "daily":
        metrics = terra_normalizer.normalize_daily(payload)
        accepted = 0
        for metric in metrics:
            metric_type = metric.get("metricType", "")
            started_at = metric.get("startedAt", "")
            if not metric_type or not started_at:
                continue
            dynamodb.put_item({**keys.metric_key(user_id, metric_type, started_at), **metric})
            accepted += 1
        return {"handled": True, "type": event_type, "userId": user_id, "accepted": accepted}

    if event_type == "activity":
        workout = terra_normalizer.normalize_activity(payload)
        if workout:
            started_at = workout.get("startedAt") or workout.get("date")
            if started_at:
                dynamodb.put_item({**keys.workout_log_key(user_id, started_at), **workout})
        return {"handled": True, "type": event_type, "userId": user_id}

    return {"handled": True, "type": event_type or "unknown", "userId": user_id, "note": "ignored"}