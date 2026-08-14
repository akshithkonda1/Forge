from __future__ import annotations

import re

from responses import RouteError, ok
from services import ledger, normalization, source_map
from storage import dynamodb, keys

_VALID_METRIC_TYPES = {
    "steps",
    "active-calories",
    "hrv",
    "resting-heart-rate",
    "heart-rate",
    "sleep-stage",
    "sleep-hours",
    "body-weight",
    "distance",
    "dietary-water",
    "blood-glucose",
    "mindful-minutes",
    "workout-load",
}

_SOURCE_RE = re.compile(r"^[a-z0-9][a-z0-9-]{0,40}$")


def handle_post_health_batch(user_id: str, body: dict) -> dict:
    metrics = body.get("metrics")
    if not isinstance(metrics, list):
        raise RouteError(400, "Request body must include a 'metrics' array.")

    accepted = 0
    rejected = 0
    errors = []

    for i, metric in enumerate(metrics):
        if not isinstance(metric, dict):
            rejected += 1
            errors.append({"message": f"metrics[{i}] must be an object."})
            continue

        metric_type = metric.get("metricType", "")
        source = metric.get("source", "")
        started_at = metric.get("startedAt", "")
        value = metric.get("value")

        if metric_type not in _VALID_METRIC_TYPES:
            rejected += 1
            errors.append({"message": f"metrics[{i}].metricType '{metric_type}' is not supported."})
            continue

        if not _SOURCE_RE.match(str(source).lower()):
            rejected += 1
            errors.append({"message": f"metrics[{i}].source '{source}' is not supported."})
            continue
        source = str(source).lower()

        if not started_at:
            rejected += 1
            errors.append({"message": f"metrics[{i}].startedAt is required."})
            continue

        if value is None:
            rejected += 1
            errors.append({"message": f"metrics[{i}].value is required."})
            continue

        normalized = normalization.normalize_metric(metric)
        item = {**keys.metric_key(user_id, metric_type, started_at), **normalized}
        dynamodb.put_item(item)
        source_map.record_seen(
            user_id,
            source,
            metric_type=metric_type,
            at=started_at,
            value=value,
        )
        accepted += 1

    ledger.refresh_after_ingest(user_id)
    return ok({"accepted": accepted, "rejected": rejected, "errors": errors})
