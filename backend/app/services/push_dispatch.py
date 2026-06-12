"""APNs remote push via AWS SNS (graceful no-op when not configured)."""
from __future__ import annotations

import hashlib
import json
import os
from datetime import datetime, timezone
from typing import Any

from storage import dynamodb, keys


def _token_hash(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()[:32]


def _sns_client():
    import boto3  # type: ignore[import]

    return boto3.client("sns")


def register_device(user_id: str, *, token: str, platform: str = "ios", bundle_id: str | None = None) -> dict:
    cleaned = (token or "").strip()
    if not cleaned:
        raise ValueError("token is required")

    platform_key = (platform or "ios").lower()
    if platform_key != "ios":
        raise ValueError("Only ios push tokens are supported today.")

    digest = _token_hash(cleaned)
    endpoint_arn = None
    platform_arn = os.getenv("SNS_IOS_PLATFORM_APPLICATION_ARN", "").strip()
    if platform_arn:
        try:
            response = _sns_client().create_platform_endpoint(
                PlatformApplicationArn=platform_arn,
                Token=cleaned,
                CustomUserData=user_id,
            )
            endpoint_arn = response.get("EndpointArn")
        except Exception:
            endpoint_arn = None

    now = datetime.now(timezone.utc).isoformat()
    item = {
        **keys.push_device_key(user_id, digest),
        "token": cleaned,
        "platform": platform_key,
        "bundleId": bundle_id or "",
        "snsEndpointArn": endpoint_arn or "",
        "updatedAt": now,
        "createdAt": now,
    }
    dynamodb.put_item(item)
    return {"registered": True, "platform": platform_key, "hasRemoteEndpoint": bool(endpoint_arn)}


def unregister_device(user_id: str, *, token: str | None = None) -> dict:
    if token:
        digest = _token_hash(token.strip())
        existing = dynamodb.get_item(**keys.push_device_key(user_id, digest))
        if existing and existing.get("snsEndpointArn"):
            try:
                _sns_client().delete_endpoint(EndpointArn=existing["snsEndpointArn"])
            except Exception:
                pass
        dynamodb.delete_item(**keys.push_device_key(user_id, digest))
        return {"removed": 1}

    items = dynamodb.query_prefix(keys.user_pk(user_id), "PUSH#IOS#")
    for item in items:
        if item.get("snsEndpointArn"):
            try:
                _sns_client().delete_endpoint(EndpointArn=item["snsEndpointArn"])
            except Exception:
                pass
        dynamodb.delete_item(pk=item["pk"], sk=item["sk"])
    return {"removed": len(items)}


def list_devices(user_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix(keys.user_pk(user_id), "PUSH#IOS#")
    return [
        {
            "platform": item.get("platform", "ios"),
            "bundleId": item.get("bundleId", ""),
            "updatedAt": item.get("updatedAt"),
            "hasRemoteEndpoint": bool(item.get("snsEndpointArn")),
        }
        for item in items
    ]


def send_push_to_user(
    user_id: str,
    *,
    title: str,
    body: str,
    data: dict[str, Any] | None = None,
) -> dict[str, Any]:
    devices = dynamodb.query_prefix(keys.user_pk(user_id), "PUSH#IOS#")
    if not devices:
        return {"sent": 0, "failed": 0, "reason": "no_devices"}

    platform_arn = os.getenv("SNS_IOS_PLATFORM_APPLICATION_ARN", "").strip()
    if not platform_arn:
        return {"sent": 0, "failed": 0, "reason": "sns_not_configured"}

    apns_payload = {
        "aps": {
            "alert": {"title": title, "body": body},
            "sound": "default",
        },
        **(data or {}),
    }
    message = json.dumps({"APNS": json.dumps(apns_payload), "default": body})
    client = _sns_client()
    sent = 0
    failed = 0

    for device in devices:
        endpoint_arn = device.get("snsEndpointArn")
        token = device.get("token")
        if not endpoint_arn and token:
            try:
                response = client.create_platform_endpoint(
                    PlatformApplicationArn=platform_arn,
                    Token=token,
                    CustomUserData=user_id,
                )
                endpoint_arn = response.get("EndpointArn")
                if endpoint_arn:
                    dynamodb.put_item({**device, "snsEndpointArn": endpoint_arn})
            except Exception:
                failed += 1
                continue

        if not endpoint_arn:
            failed += 1
            continue

        try:
            client.publish(
                TargetArn=endpoint_arn,
                Message=message,
                MessageStructure="json",
            )
            sent += 1
        except Exception:
            failed += 1

    return {"sent": sent, "failed": failed}