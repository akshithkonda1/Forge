"""ElevenLabs voice slot — next evolution, off by default.

PR #480 removed ConvAI as the production mouth. This file is not that live
path. It exists so Fish / Polly / on-device / ElevenLabs share one provider
interface and a later evolution can turn the slot on without inventing a
new contract.

``ARIA_ELEVENLABS_VOICE_ENABLED`` is off unless explicitly truthy. Even when
someone flips it, ``synthesize`` refuses — this PR does not enable live
ElevenLabs calls and does not restore ``/ai/voice/bootstrap`` or
``/ai/voice/tool``. Dummy never imports this module.
"""

from __future__ import annotations

import os

from responses import RouteError

ENABLED_ENV = "ARIA_ELEVENLABS_VOICE_ENABLED"
API_KEY_ENV = "ELEVENLABS_API_KEY"
VOICE_ID_ENV = "ELEVENLABS_ARIA_VOICE_ID"
AGENT_ID_ENV = "ELEVENLABS_ARIA_AGENT_ID"

_TRUE_FLAGS = frozenset({"1", "true", "yes", "on"})


def voice_enabled() -> bool:
    """Unset / empty / anything not in ``_TRUE_FLAGS`` is off."""
    return os.getenv(ENABLED_ENV, "").strip().lower() in _TRUE_FLAGS


def synthesize(text: str, **_kwargs: object) -> bytes:
    """Reserved slot. Never opens an ElevenLabs HTTP session."""
    _ = text
    raise RouteError(
        503,
        "ElevenLabs is a reserved voice slot, not the live mouth.",
        code="elevenlabs_disabled",
    )
