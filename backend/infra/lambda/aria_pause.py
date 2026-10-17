"""ARIA-only kill switch backed by a Standard-tier SSM String parameter.

Cached in-process for 60 seconds so a pause or resume is felt on the next
warm invoke after that window, not on every request. Unset
``ARIA_PAUSED_PARAMETER_NAME`` always fails open (ARIA stays up). SSM errors
fail paused unless ``ARIA_PAUSE_FAIL_MODE`` is ``open``. Voice and /health
never consult this module.
"""

from __future__ import annotations

import logging
import os
import time

LOGGER = logging.getLogger("forge.aria_pause")

_CACHE_TTL_SECONDS = 60.0
_cached_at: float = 0.0
_cached_value: bool = False
_have_cache = False

_PAUSED_VALUES = frozenset({"true", "1", "yes"})


def reset_cache() -> None:
    """Drop the in-process cache. Tests call this between cases."""
    global _cached_at, _cached_value, _have_cache
    _cached_at = 0.0
    _cached_value = False
    _have_cache = False


def is_aria_paused() -> bool:
    """Return True when ARIA chat/router/coach routes should return 503."""
    global _cached_at, _cached_value, _have_cache
    now = time.monotonic()
    if _have_cache and (now - _cached_at) < _CACHE_TTL_SECONDS:
        return _cached_value
    value = _read_paused()
    _cached_value = value
    _cached_at = now
    _have_cache = True
    return value


def _fail_mode_paused() -> bool:
    return (os.getenv("ARIA_PAUSE_FAIL_MODE") or "paused").strip().lower() == "paused"


def _ssm_client():
    import boto3

    from aws_clients import client_config

    return boto3.client("ssm", config=client_config())


def _read_paused() -> bool:
    name = (os.getenv("ARIA_PAUSED_PARAMETER_NAME") or "").strip()
    if not name:
        LOGGER.warning(
            "ARIA_PAUSED_PARAMETER_NAME is unset; ARIA pause check fails open"
        )
        return False
    try:
        response = _ssm_client().get_parameter(Name=name)
        raw = str((response.get("Parameter") or {}).get("Value") or "")
        return raw.strip().lower() in _PAUSED_VALUES
    except Exception as exc:  # noqa: BLE001 - kill switch must not take the process down
        paused = _fail_mode_paused()
        LOGGER.warning(
            "Failed to read ARIA_PAUSED parameter %s (%s); fail mode=%s",
            name,
            exc,
            "paused" if paused else "open",
        )
        return paused
