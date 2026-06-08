"""Forge infrastructure healer — AWS-native recovery without Kubernetes.

On a schedule (or when triggered by a CloudWatch alarm), this Lambda:
1. Probes the public /health endpoint.
2. If unhealthy or production readiness is degraded, redeploys from S3 artifact.
3. Re-checks health and emits custom CloudWatch metrics for dashboards/alarms.
"""

from __future__ import annotations

import json
import os
import time
import urllib.error
import urllib.request

import boto3

cloudwatch = boto3.client("cloudwatch")
lambda_client = boto3.client("lambda")


def _check_health(url: str, timeout: int) -> tuple[bool, str, dict]:
    try:
        with urllib.request.urlopen(url, timeout=timeout) as response:
            body = response.read().decode("utf-8")
            payload = json.loads(body or "{}")
            status = payload.get("status")
            readiness = payload.get("readiness") or {}
            if response.status != 200:
                return False, f"status={response.status} body={body[:200]}", payload
            if status not in {"ok", "degraded"}:
                return False, f"unexpected status={status}", payload
            if status == "degraded":
                return False, "health status degraded", payload
            if readiness.get("productionReady") is False and os.environ.get(
                "REQUIRE_PRODUCTION_READY", "false"
            ).lower() in {"1", "true", "yes"}:
                return False, "production readiness checks failed", payload
            return True, "ok", payload
    except (urllib.error.URLError, TimeoutError, json.JSONDecodeError) as exc:
        return False, str(exc), {}


def _put_metric(healthy: bool, recovered: bool) -> None:
    namespace = os.environ.get("METRIC_NAMESPACE", "Forge/SelfHealing")
    function_name = os.environ.get("TARGET_FUNCTION_NAME", "unknown")
    cloudwatch.put_metric_data(
        Namespace=namespace,
        MetricData=[
            {
                "MetricName": "ApiHealthStatus",
                "Dimensions": [{"Name": "FunctionName", "Value": function_name}],
                "Value": 1.0 if healthy else 0.0,
                "Unit": "None",
            },
            {
                "MetricName": "RecoveryAttempts",
                "Dimensions": [{"Name": "FunctionName", "Value": function_name}],
                "Value": 1.0 if recovered else 0.0,
                "Unit": "Count",
            },
        ],
    )


def _redeploy(function_name: str, bucket: str, key: str) -> None:
    lambda_client.update_function_code(
        FunctionName=function_name,
        S3Bucket=bucket,
        S3Key=key,
        Publish=True,
    )
    waiter = lambda_client.get_waiter("function_updated")
    waiter.wait(FunctionName=function_name)
    time.sleep(2)


def handler(event, _context):
    health_url = os.environ["HEALTH_CHECK_URL"]
    function_name = os.environ["TARGET_FUNCTION_NAME"]
    artifacts_bucket = os.environ["ARTIFACTS_BUCKET"]
    artifacts_key = os.environ["ARTIFACTS_KEY"]
    timeout = int(os.environ.get("HEALTH_CHECK_TIMEOUT_SECONDS", "10"))
    force_recover = bool(event.get("forceRecover"))

    healthy, detail, payload = _check_health(health_url, timeout)
    recovered = False

    if healthy and not force_recover:
        _put_metric(True, False)
        return {"status": "healthy", "detail": detail, "readiness": payload.get("readiness")}

    if not healthy or force_recover:
        _redeploy(function_name, artifacts_bucket, artifacts_key)
        recovered = True
        healthy, detail, payload = _check_health(health_url, timeout)

    _put_metric(healthy, recovered)
    status = "recovered" if healthy else "unhealthy"
    return {
        "status": status,
        "recovered": recovered,
        "healthy": healthy,
        "detail": detail,
        "readiness": payload.get("readiness"),
        "event": event.get("source", "scheduled"),
    }