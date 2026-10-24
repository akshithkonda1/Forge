"""Amazon Polly — documented Fish fallback, off by default.

Ordered mouth: Fish → Polly → on-device. Polly runs only when
``ARIA_POLLY_VOICE_FALLBACK`` is truthy *and* Fish already failed with an
error or timeout. Dummy, offline, over-quota, and privacy-unguaranteed
lines never reach this module.

No AWS resources are created by this PR. IAM for ``polly:SynthesizeSpeech``
is an operator follow-up. Voice id is config (``POLLY_VOICE_ID``, default
``Joanna``). This module never logs TTS text.
"""

from __future__ import annotations

import os
from typing import Any, Callable

from responses import RouteError

ENABLED_ENV = "ARIA_POLLY_VOICE_FALLBACK"
VOICE_ENV = "POLLY_VOICE_ID"
ENGINE_ENV = "POLLY_ENGINE"
DEFAULT_VOICE = "Joanna"
DEFAULT_ENGINE = "neural"

_TRUE_FLAGS = frozenset({"1", "true", "yes", "on"})

PollyFn = Callable[[str, str, str], bytes]


def fallback_enabled() -> bool:
    return os.getenv(ENABLED_ENV, "").strip().lower() in _TRUE_FLAGS


def resolve_voice(raw: str | None = None) -> str:
    trimmed = (raw if raw is not None else os.getenv(VOICE_ENV) or "").strip()
    return trimmed or DEFAULT_VOICE


def resolve_engine(raw: str | None = None) -> str:
    trimmed = (raw if raw is not None else os.getenv(ENGINE_ENV) or "").strip().lower()
    if trimmed in {"neural", "standard"}:
        return trimmed
    return DEFAULT_ENGINE


def synthesize(
    text: str,
    *,
    client: PollyFn | None = None,
    voice_id: str | None = None,
    engine: str | None = None,
) -> bytes:
    """Speak already-sanitized text. Callers must have run the privacy gate."""
    if not fallback_enabled():
        raise RouteError(
            503,
            "Polly voice fallback is disabled.",
            code="polly_disabled",
        )
    line = (text or "").strip()
    if not line:
        raise RouteError(400, "message is required.", code="polly_empty_text")
    chosen_voice = resolve_voice(voice_id)
    chosen_engine = resolve_engine(engine)
    caller = client or _boto_synthesize
    audio = caller(line, chosen_voice, chosen_engine)
    if not audio:
        raise RouteError(503, "Could not synthesize speech.", code="polly_tts_failed")
    return audio


def _boto_synthesize(text: str, voice_id: str, engine: str) -> bytes:
    try:
        import boto3  # lazy: tests inject a client
    except ImportError as exc:
        raise RouteError(503, "Could not synthesize speech.", code="polly_tts_failed") from exc
    try:
        polly = boto3.client("polly")
        response: dict[str, Any] = polly.synthesize_speech(
            Text=text,
            OutputFormat="mp3",
            VoiceId=voice_id,
            Engine=engine,
        )
        stream = response.get("AudioStream")
        if stream is None:
            return b""
        return stream.read() if hasattr(stream, "read") else bytes(stream)
    except Exception as exc:  # noqa: BLE001 - missing IAM must not take down chat
        raise RouteError(503, "Could not synthesize speech.", code="polly_tts_failed") from exc
