"""ARIA / Forge voice mouth — one interface, ordered fallbacks.

Preferred live mouth is Fish Audio S2.1-Pro. Ordered fallbacks:

1. ``fish`` — primary, gated by ``ARIA_FISH_VOICE_ENABLED`` (off by default).
2. ``polly`` — Amazon Polly, only after a Fish error or timeout.
3. ``on_device`` — Dummy, offline, over-quota, or privacy-unguaranteed text.

ElevenLabs is a reserved slot (``elevenlabs``) for a later evolution. It is
off by default (``ARIA_ELEVENLABS_VOICE_ENABLED``) and is not in the live
fallback chain. Dummy / offline never select a cloud mouth and never open
HTTP.

This module does not log TTS text. Callers must not either.
"""

from __future__ import annotations

from typing import Any

FISH = "fish"
POLLY = "polly"
ON_DEVICE = "on_device"
ELEVENLABS = "elevenlabs"

# Documented chain. ElevenLabs is registered but not automatic.
DEFAULT_CHAIN = (FISH, POLLY, ON_DEVICE)
REGISTERED = (FISH, POLLY, ON_DEVICE, ELEVENLABS)

ON_DEVICE_REASONS = frozenset(
    {"dummy", "offline", "quota", "privacy", "fallback", "disabled", "promo", "busy"}
)


def is_dummy_request(body: dict[str, Any] | None) -> bool:
    """True when the client marked this speak as Dummy / local / offline."""
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
    """Pick the mouth. Cloud providers lose to Dummy, offline, quota, privacy."""
    _ = elevenlabs_configured  # reserved slot; not consulted in the live chain
    _ = elevenlabs_enabled
    if dummy or offline:
        return ON_DEVICE
    if not privacy_ok:
        return ON_DEVICE
    if not quota_ok:
        return ON_DEVICE
    fish_blocked = fish_failed or fish_timeout or fish_busy or fish_promo_expired
    if fish_enabled and fish_configured and not fish_blocked:
        return FISH
    if fish_blocked and polly_enabled and polly_configured:
        return POLLY
    return ON_DEVICE


def on_device_payload(reason: str) -> dict[str, Any]:
    why = reason if reason in ON_DEVICE_REASONS else "fallback"
    return {
        "provider": ON_DEVICE,
        "code": "tts_on_device",
        "reason": why,
        "format": None,
        "model": None,
        "audio_base64": None,
        "voice_id": None,
    }
