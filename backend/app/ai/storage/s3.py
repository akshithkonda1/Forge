from __future__ import annotations

import json
import os
from typing import Any

_BUCKET = os.getenv("ARIA_CONTEXT_BUCKET", os.getenv("APP_ASSETS_BUCKET"))


def _client():
    import boto3  # type: ignore[import]

    return boto3.client("s3")


def put_json(key: str, payload: dict[str, Any]) -> str | None:
    if not _BUCKET:
        return None
    body = json.dumps(payload, separators=(",", ":")).encode("utf-8")
    _client().put_object(Bucket=_BUCKET, Key=key, Body=body, ContentType="application/json")
    return f"s3://{_BUCKET}/{key}"


def get_json(key: str) -> dict[str, Any] | None:
    if not _BUCKET:
        return None
    try:
        obj = _client().get_object(Bucket=_BUCKET, Key=key)
        return json.loads(obj["Body"].read().decode("utf-8"))
    except Exception:
        return None


def head_object_size(key: str) -> int | None:
    if not _BUCKET:
        return None
    try:
        meta = _client().head_object(Bucket=_BUCKET, Key=key)
        return int(meta.get("ContentLength") or 0)
    except Exception:
        return None