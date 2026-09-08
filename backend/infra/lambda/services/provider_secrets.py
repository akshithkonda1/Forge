"""Cached loader for ``aws_secretsmanager_secret.ai_provider``.

The secret is the only place the ElevenLabs API key is allowed to live.
Environment variables overlay it so tests and a local Lambda can run without
boto3. Empty overlay values do not wipe a key that came from the secret.
"""

from __future__ import annotations

import json
import os
from typing import Any, Callable

_SECRET_CACHE: dict[str, Any] | None = None

_KEYS = (
    "ELEVENLABS_API_KEY",
    "ELEVENLABS_ARIA_VOICE_ID",
    "ELEVENLABS_ARIA_AGENT_ID",
)


def reset_cache() -> None:
    global _SECRET_CACHE
    _SECRET_CACHE = None


def load_ai_provider_secret(
    *,
    get_secret_value: Callable[[str], str] | None = None,
) -> dict[str, str]:
    """Return provider credentials as a string map.

    Lookup order per key: non-empty process env, then Secrets Manager JSON.
    Missing / unreadable secrets yield an empty map rather than raising — callers
    decide whether that is a 503 or a dummy-only product.
    """
    global _SECRET_CACHE
    if _SECRET_CACHE is None:
        _SECRET_CACHE = _read_secret(get_secret_value=get_secret_value)

    merged: dict[str, str] = {}
    for key in _KEYS:
        env = (os.getenv(key) or "").strip()
        if env:
            merged[key] = env
            continue
        raw = _SECRET_CACHE.get(key)
        if isinstance(raw, str) and raw.strip():
            merged[key] = raw.strip()
    return merged


def _read_secret(
    *,
    get_secret_value: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    arn = (os.getenv("AI_PROVIDER_SECRET_ARN") or "").strip()
    if not arn:
        return {}
    try:
        if get_secret_value is not None:
            payload = get_secret_value(arn)
        else:
            payload = _boto_get_secret(arn)
    except Exception:  # noqa: BLE001 - unconfigured secret must not take down chat
        return {}
    if not payload:
        return {}
    try:
        data = json.loads(payload)
    except json.JSONDecodeError:
        return {}
    return data if isinstance(data, dict) else {}


def _boto_get_secret(arn: str) -> str:
    import boto3  # lazy: tests never need this

    client = boto3.client("secretsmanager")
    response = client.get_secret_value(SecretId=arn)
    return str(response.get("SecretString") or "")
