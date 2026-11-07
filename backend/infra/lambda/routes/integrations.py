from __future__ import annotations

import uuid
from datetime import datetime, timezone

from responses import RouteError, ok
from storage import dynamodb, keys

_VALID_PROVIDERS = {"apple-health", "oura", "whoop", "garmin", "strava"}

# Full remote provider workers are out of scope for this API. Completing the
# job in-process (honest terminal state) is preferred over claiming "queued"
# when nothing will ever read lastJobId (BH-05).
_SYNC_NOT_IMPLEMENTED = (
    "Provider sync is not implemented in this API; the request was not queued."
)


def _process_sync_job(user_id: str, provider: str, job_id: str, requested_at: str) -> dict:
    """Minimal in-process processor: mark a clear terminal state immediately."""
    now = datetime.now(timezone.utc).isoformat()
    item = {
        **keys.connection_key(user_id, provider),
        "provider": provider,
        "status": "error",
        "lastSyncRequestedAt": requested_at,
        "lastSyncFinishedAt": now,
        "lastJobId": job_id,
        "lastSyncResult": "not_implemented",
        "errorMessage": _SYNC_NOT_IMPLEMENTED,
    }
    dynamodb.put_item(item)
    return {
        "provider": provider,
        "jobId": job_id,
        "status": "error",
        "finishedAt": now,
        "errorMessage": _SYNC_NOT_IMPLEMENTED,
    }


def handle_post_integration_sync(user_id: str, provider: str, _body: dict) -> dict:
    if provider not in _VALID_PROVIDERS:
        raise RouteError(400, f"Provider '{provider}' is not supported.")

    now = datetime.now(timezone.utc).isoformat()
    job_id = uuid.uuid4().hex[:16]
    return ok(_process_sync_job(user_id, provider, job_id, now))
