from __future__ import annotations

from core.responses import RouteError, ok
from services import conclusions_store, normalization
from storage import dynamodb, keys

_VALID_METRIC_TYPES = {
    "steps",
    "active-calories",
    "hrv",
    "resting-heart-rate",
    "heart-rate",
    "sleep-stage",
    "body-weight",
    "distance",
    "dietary-calories",
    "dietary-protein",
    "dietary-carbs",
    "dietary-fat",
    "dietary-water",
    "oxygen-saturation",
}

_VALID_SOURCES = {
    "apple-health",
    "health-connect",
    "oura",
    "whoop",
    "garmin",
    "strava",
    "manual",
}


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

        if source not in _VALID_SOURCES:
            rejected += 1
            errors.append({"message": f"metrics[{i}].source '{source}' is not supported."})
            continue

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
        accepted += 1

    if accepted:
        try:
            conclusions_store.refresh_conclusions(user_id)
        except Exception:
            pass

    return ok({"accepted": accepted, "rejected": rejected, "errors": errors})


def handle_post_health_cycle(user_id: str, body: dict) -> dict:
    events = body.get("events")
    if not isinstance(events, list):
        raise RouteError(400, "Request body must include an 'events' array.")

    accepted = 0
    rejected = 0
    errors = []

    for i, event in enumerate(events):
        if not isinstance(event, dict):
            rejected += 1
            errors.append({"message": f"events[{i}] must be an object."})
            continue

        started_at = str(event.get("startedAt") or "").strip()
        flow = str(event.get("flow") or "").strip()
        source = str(event.get("source") or "apple-health")

        if not started_at:
            rejected += 1
            errors.append({"message": f"events[{i}].startedAt is required."})
            continue
        if not flow:
            rejected += 1
            errors.append({"message": f"events[{i}].flow is required."})
            continue
        if source not in _VALID_SOURCES:
            rejected += 1
            errors.append({"message": f"events[{i}].source '{source}' is not supported."})
            continue

        item = {
            **keys.cycle_event_key(user_id, started_at),
            "startedAt": started_at,
            "flow": flow,
            "source": source,
            "value": flow,
            "date": started_at[:10],
        }
        dynamodb.put_item(item)
        accepted += 1

    if accepted:
        try:
            conclusions_store.refresh_conclusions(user_id)
        except Exception:
            pass

    return ok({"accepted": accepted, "rejected": rejected, "errors": errors})