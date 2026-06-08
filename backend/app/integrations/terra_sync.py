from __future__ import annotations

import uuid
from datetime import datetime, timedelta, timezone
from typing import Any

from integrations import terra_client, terra_normalizer
from integrations.terra_client import TerraAPIError, TerraConfigError
from storage import dynamodb, keys

_TERRA_DATA_TYPES = ("sleep", "daily", "activity")
_DEFAULT_LOOKBACK_DAYS = 30


def request_user_backfill(
    user_id: str,
    *,
    provider: str | None = None,
    lookback_days: int = _DEFAULT_LOOKBACK_DAYS,
) -> dict[str, Any]:
    if not terra_client.is_configured():
        return {"queued": False, "reason": "not_configured"}

    ref = dynamodb.get_item(**keys.terra_ref_key(user_id))
    terra_user_id = ref.get("terraUserId") if ref else None
    if not terra_user_id:
        return {"queued": False, "reason": "no_terra_user"}

    resolved_provider = provider or ref.get("provider")
    forge_provider = terra_normalizer.map_provider(resolved_provider)
    now = datetime.now(timezone.utc).isoformat()
    start_date = (datetime.now(timezone.utc) - timedelta(days=lookback_days)).date().isoformat()
    requested: list[str] = []
    errors: list[str] = []

    for data_type in _TERRA_DATA_TYPES:
        try:
            terra_client.request_historical_data(
                data_type=data_type,
                terra_user_id=terra_user_id,
                start_date=start_date,
                to_webhook=True,
            )
            requested.append(data_type)
        except (TerraConfigError, TerraAPIError) as exc:
            errors.append(f"{data_type}: {exc}")

    item = {
        **keys.connection_key(user_id, forge_provider),
        "provider": forge_provider,
        "displayName": terra_normalizer.display_name(resolved_provider),
        "status": "syncing" if requested else "error",
        "middleware": "terra",
        "lastSyncRequestedAt": now,
        "lastJobId": uuid.uuid4().hex[:16],
        "terraUserId": terra_user_id,
    }
    if requested:
        item["lastSyncedAt"] = now
    if errors:
        item["errorMessage"] = "; ".join(errors)
    dynamodb.put_item(item)

    return {
        "queued": bool(requested),
        "userId": user_id,
        "terraUserId": terra_user_id,
        "provider": forge_provider,
        "requested": requested,
        "errors": errors,
    }