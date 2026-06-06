from __future__ import annotations

import uuid
from datetime import datetime, timezone

from responses import RouteError, ok
from storage import dynamodb, keys

_VALID_PROVIDERS = {"apple-health", "oura", "whoop", "garmin", "strava"}


def handle_post_integration_sync(user_id: str, provider: str, _body: dict) -> dict:
    if provider not in _VALID_PROVIDERS:
        raise RouteError(400, f"Provider '{provider}' is not supported.")

    now = datetime.now(timezone.utc).isoformat()
    job_id = uuid.uuid4().hex[:16]

    item = {
        **keys.connection_key(user_id, provider),
        "provider": provider,
        "status": "syncing",
        "lastSyncRequestedAt": now,
        "lastJobId": job_id,
    }
    dynamodb.put_item(item)

    return ok({
        "provider": provider,
        "jobId": job_id,
        "status": "queued",
        "queuedAt": now,
    })
