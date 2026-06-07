from __future__ import annotations

import json
import os
from functools import lru_cache
from typing import Any

_SECRET_ARN = os.getenv("TERRA_SECRET_ARN")


@lru_cache(maxsize=1)
def _load_secret() -> dict[str, Any]:
    if not _SECRET_ARN:
        return {}

    import boto3  # type: ignore[import]

    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=_SECRET_ARN)
    raw = response.get("SecretString") or ""
    if not raw:
        return {}
    try:
        payload = json.loads(raw)
    except json.JSONDecodeError:
        return {}
    return payload if isinstance(payload, dict) else {}


def dev_id() -> str | None:
    secret = _load_secret()
    return secret.get("dev_id") or secret.get("TERRA_DEV_ID") or os.getenv("TERRA_DEV_ID")


def api_key() -> str | None:
    secret = _load_secret()
    return secret.get("api_key") or secret.get("TERRA_API_KEY") or os.getenv("TERRA_API_KEY")


def webhook_secret() -> str | None:
    secret = _load_secret()
    return (
        secret.get("webhook_secret")
        or secret.get("TERRA_WEBHOOK_SECRET")
        or os.getenv("TERRA_WEBHOOK_SECRET")
    )


def is_configured() -> bool:
    return bool(dev_id() and api_key())


def is_webhook_configured() -> bool:
    return bool(webhook_secret())


def clear_cache() -> None:
    _load_secret.cache_clear()