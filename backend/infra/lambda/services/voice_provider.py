"""ARIA / Forge voice mouth — Kokoro only.

There is no fallback chain. Fish, Polly, and ElevenLabs are not registered
and are never selected. Dummy, offline, over-quota, and live all use the
same on-device Kokoro mouth. Hex does not synthesize speech.

This module does not log TTS text. Callers must not either.
"""

from __future__ import annotations

from typing import Any

KOKORO = "kokoro"

# Single mouth. Cloud vendors are not in the registry.
DEFAULT_CHAIN = (KOKORO,)
REGISTERED = (KOKORO,)

FAIL_REASONS = frozenset({"load", "missing_model", "disabled"})


def is_dummy_request(body: dict[str, Any] | None) -> bool:
    """True when the client marked this as Dummy / local / offline."""
    payload = body or {}
    if payload.get("dummy") is True:
        return True
    transport = str(payload.get("transport") or payload.get("mode") or "").strip().lower()
    return transport in {"dummy", "local", "localtesting", "offline", "dummy-offline"}


def resolve_mouth(
    *,
    dummy: bool = False,
    offline: bool = False,
    privacy_ok: bool = True,
    quota_ok: bool = True,
    fish_enabled: bool = False,
    fish_configured: bool = False,
    fish_failed: bool = False,
    fish_timeout: bool = False,
    fish_busy: bool = False,
    fish_promo_expired: bool = False,
    polly_enabled: bool = False,
    polly_configured: bool = False,
    elevenlabs_enabled: bool = False,
    elevenlabs_configured: bool = False,
) -> str:
    """Always Kokoro. Cloud flags are accepted and ignored so old callers compile."""
    _ = (
        dummy,
        offline,
        privacy_ok,
        quota_ok,
        fish_enabled,
        fish_configured,
        fish_failed,
        fish_timeout,
        fish_busy,
        fish_promo_expired,
        polly_enabled,
        polly_configured,
        elevenlabs_enabled,
        elevenlabs_configured,
    )
    return KOKORO


def unavailable_payload(reason: str = "load") -> dict[str, Any]:
    why = reason if reason in FAIL_REASONS else "load"
    return {
        "provider": KOKORO,
        "code": "tts_kokoro_unavailable",
        "reason": why,
        "format": None,
        "model": "kokoro-82m",
        "audio_base64": None,
        "voice_id": None,
    }
