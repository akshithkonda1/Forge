"""Cached loader for ElevenLabs credentials.

Production reads Parameter Store SecureString names from
``ELEVENLABS_*_PARAMETER_NAME``. Tests and a local Lambda can overlay
process env or the legacy ``AI_PROVIDER_SECRET_ARN`` JSON secret.
Empty overlay values do not wipe a key that came from SSM / Secrets Manager.
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

_PARAMETER_ENV = {
    "ELEVENLABS_API_KEY": "ELEVENLABS_API_KEY_PARAMETER_NAME",
    "ELEVENLABS_ARIA_VOICE_ID": "ELEVENLABS_ARIA_VOICE_ID_PARAMETER_NAME",
    "ELEVENLABS_ARIA_AGENT_ID": "ELEVENLABS_ARIA_AGENT_ID_PARAMETER_NAME",
}


def reset_cache() -> None:
    global _SECRET_CACHE
    _SECRET_CACHE = None


def load_ai_provider_secret(
    *,
    get_secret_value: Callable[[str], str] | None = None,
) -> dict[str, str]:
    """Return provider credentials as a string map.

    Lookup order per key: non-empty process env, then Parameter Store /
    Secrets Manager. Missing / unreadable stores yield an empty map rather
    than raising — callers decide whether that is a 503 or a dummy-only product.
    """
    global _SECRET_CACHE
    if _SECRET_CACHE is None:
        _SECRET_CACHE = _read_store(get_secret_value=get_secret_value)

    merged: dict[str, str] = {}
    for key in _KEYS:
        env = (os.getenv(key) or "").strip()
        if env:
            merged[key] = env
            continue
        raw = _SECRET_CACHE.get(key)
        if isinstance(raw, str) and raw.strip() and raw.strip() != "UNSET":
            merged[key] = raw.strip()
    return merged


def _read_store(
    *,
    get_secret_value: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    from_ssm = _read_ssm_parameters()
    if from_ssm:
        return from_ssm
    return _read_secret(get_secret_value=get_secret_value)


def _parameter_names() -> dict[str, str]:
    names: dict[str, str] = {}
    for key, env_name in _PARAMETER_ENV.items():
        name = (os.getenv(env_name) or "").strip()
        if name:
            names[key] = name
    return names


def _read_ssm_parameters() -> dict[str, Any]:
    names = _parameter_names()
    if not names:
        return {}
    try:
        import boto3  # lazy: tests never need this

        client = boto3.client("ssm")
        out: dict[str, Any] = {}
        for key, name in names.items():
            response = client.get_parameter(Name=name, WithDecryption=True)
            value = str((response.get("Parameter") or {}).get("Value") or "")
            if value.strip() and value.strip() != "UNSET":
                out[key] = value.strip()
        return out
    except Exception:  # noqa: BLE001 - unconfigured parameter must not take down chat
        return {}


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
