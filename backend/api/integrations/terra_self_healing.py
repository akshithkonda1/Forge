from __future__ import annotations

import os
from datetime import datetime, timedelta, timezone
from typing import Any

from integrations import terra_config
from integrations.terra_self_integration import bootstrap, expected_webhook_url, get_integration_state
from integrations.terra_sync import request_user_backfill
from storage import dynamodb, keys

_STALE_HOURS = int(os.getenv("TERRA_SELF_HEAL_STALE_HOURS", "24"))
_SYNCING_STUCK_MINUTES = int(os.getenv("TERRA_SELF_HEAL_SYNCING_STUCK_MINUTES", "90"))


def _parse_iso(value: str | None) -> datetime | None:
    if not value:
        return None
    try:
        return datetime.fromisoformat(value.replace("Z", "+00:00"))
    except ValueError:
        return None


def _emit_metrics(*, healthy: float, healed: int, stale: int) -> None:
    namespace = os.getenv("TERRA_METRIC_NAMESPACE", "Forge/Terra")
    if os.getenv("EMIT_TERRA_METRICS", "true").lower() not in {"1", "true", "yes"}:
        return
    try:
        import boto3  # type: ignore[import]

        cloudwatch = boto3.client("cloudwatch")
        cloudwatch.put_metric_data(
            Namespace=namespace,
            MetricData=[
                {
                    "MetricName": "IntegrationHealth",
                    "Value": healthy,
                    "Unit": "None",
                },
                {
                    "MetricName": "ConnectionsHealed",
                    "Value": float(healed),
                    "Unit": "Count",
                },
                {
                    "MetricName": "StaleConnections",
                    "Value": float(stale),
                    "Unit": "Count",
                },
            ],
        )
    except Exception:
        return


def assess_health() -> dict[str, Any]:
    terra_config.clear_cache()
    integration = bootstrap()
    now = datetime.now(timezone.utc)

    stale_connections: list[dict[str, Any]] = []
    stuck_syncing: list[dict[str, Any]] = []
    refs = dynamodb.scan_sk("TERRA#REF", limit=500)

    for ref in refs:
        user_id = ref.get("pk", "").removeprefix("USER#")
        if not user_id:
            continue
        provider = terra_normalizer_provider(ref.get("provider"))
        connection = dynamodb.get_item(**keys.connection_key(user_id, provider)) if provider else None
        if not connection:
            continue

        status = connection.get("status")
        last_synced = _parse_iso(connection.get("lastSyncedAt") or connection.get("lastSyncRequestedAt"))
        last_requested = _parse_iso(connection.get("lastSyncRequestedAt"))

        if status == "syncing" and last_requested and now - last_requested > timedelta(minutes=_SYNCING_STUCK_MINUTES):
            stuck_syncing.append({"userId": user_id, "provider": provider, "status": status})
        elif status in {"connected", "error", "syncing"}:
            if not last_synced or now - last_synced > timedelta(hours=_STALE_HOURS):
                stale_connections.append({"userId": user_id, "provider": provider, "status": status})

    healthy = 1.0 if integration.get("status") == "ready" else 0.0
    if integration.get("status") == "degraded":
        healthy = 0.5

    return {
        "healthy": healthy,
        "integration": integration,
        "webhookUrl": expected_webhook_url(),
        "staleConnections": len(stale_connections),
        "stuckSyncing": len(stuck_syncing),
        "candidates": {
            "stale": stale_connections[:25],
            "stuckSyncing": stuck_syncing[:25],
        },
        "checkedAt": now.isoformat(),
    }


def terra_normalizer_provider(provider: str | None) -> str | None:
    from integrations import terra_normalizer

    if not provider:
        return None
    return terra_normalizer.map_provider(provider)


def heal(*, max_repairs: int = 25) -> dict[str, Any]:
    terra_config.clear_cache()
    assessment = assess_health()
    repaired: list[dict[str, Any]] = []
    failures: list[dict[str, Any]] = []

    candidates = assessment["candidates"]["stale"] + assessment["candidates"]["stuckSyncing"]
    for candidate in candidates[:max_repairs]:
        user_id = candidate["userId"]
        provider = candidate.get("provider")
        try:
            result = request_user_backfill(user_id, provider=provider)
            entry = {"userId": user_id, "provider": provider, "result": result}
            if result.get("queued"):
                repaired.append(entry)
            else:
                failures.append(entry)
        except Exception as exc:  # noqa: BLE001 — heal loop should continue
            failures.append({"userId": user_id, "provider": provider, "error": str(exc)})

    now = datetime.now(timezone.utc).isoformat()
    summary = {
        "assessment": assessment,
        "repaired": repaired,
        "failures": failures,
        "repairedCount": len(repaired),
        "failureCount": len(failures),
        "healedAt": now,
    }
    dynamodb.put_item({**keys.terra_heal_run_key(now), **summary, "updatedAt": now})
    _emit_metrics(
        healthy=assessment["healthy"],
        healed=len(repaired),
        stale=assessment["staleConnections"],
    )
    return summary


def get_last_heal_run() -> dict[str, Any] | None:
    items = dynamodb.scan_pk_prefix("SYSTEM#TERRA", limit=10)
    heal_runs = [i for i in items if str(i.get("sk", "")).startswith("HEAL#")]
    if not heal_runs:
        return None
    heal_runs.sort(key=lambda item: item.get("sk", ""), reverse=True)
    latest = heal_runs[0]
    return {k: v for k, v in latest.items() if k not in ("pk", "sk")}