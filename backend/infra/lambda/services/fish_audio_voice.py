"""Fish Audio TTS client for already-guarded ARIA speak.

Parallel to ``elevenlabs_voice`` (ConvAI). This module does not replace it.
Dummy / on-device speech stays the default: ``ARIA_FISH_VOICE_ENABLED`` is
off unless explicitly truthy. When the flag is off this module never reads
``FISH_AUDIO_API_KEY`` and never calls ``api.fish.audio``.

Speak-only (Rowan): no ``fuse_turn``, no ``remember_short_term``, no vault /
``recentPatterns`` writes, no dig payload, no coach_context side keys, no
``/ai/observe``. The caller already ran ``guard_speak`` — this path does not
rewrite prose. The Fish body is ``text`` + ``format`` only.

Pike wires SSM / ``provider_secrets`` later. This PR loads the key from
process env only. Never log or return the key.
"""

from __future__ import annotations

import json
import os
import urllib.error
import urllib.request
from typing import Any, Callable

from responses import RouteError
from security import MAX_CHAT_MESSAGE_CHARS

FISH_API = "https://api.fish.audio"
TTS_PATH = "/v1/tts"
DEFAULT_MODEL = "s2.1-pro-free"
API_KEY_ENV = "FISH_AUDIO_API_KEY"
ENABLED_ENV = "ARIA_FISH_VOICE_ENABLED"

_TRUE_FLAGS = frozenset({"1", "true", "yes", "on"})

HttpFn = Callable[[str, str, dict[str, str], bytes | None], tuple[int, bytes]]


def fish_voice_enabled() -> bool:
    """Unset / empty / anything not in ``_TRUE_FLAGS`` is off."""
    return os.getenv(ENABLED_ENV, "").strip().lower() in _TRUE_FLAGS


def _headers(api_key: str, *, model: str = DEFAULT_MODEL) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "model": model,
    }


def _stdlib_http(
    method: str, url: str, headers: dict[str, str], body: bytes | None
) -> tuple[int, bytes]:
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return int(response.status), response.read()
    except urllib.error.HTTPError as exc:
        return int(exc.code), exc.read()


def require_api_key() -> str:
    key = (os.getenv(API_KEY_ENV) or "").strip()
    if not key:
        raise RouteError(
            503,
            "Fish Audio TTS is not configured. Seed FISH_AUDIO_API_KEY. "
            "Dummy / on-device speech does not need this.",
            code="fish_unconfigured",
        )
    return key


def _refuse_if_disabled() -> None:
    if not fish_voice_enabled():
        raise RouteError(
            503,
            "Fish Audio TTS is disabled. Dummy / on-device speech stays the default.",
            code="fish_disabled",
        )


def _message_text(body: dict[str, Any] | None) -> str:
    """Already-guarded ARIA prose only. Extra body keys are ignored."""
    raw = "" if body is None else body.get("message")
    if not isinstance(raw, str):
        raw = str(raw or "")
    message = raw.strip()
    if not message:
        raise RouteError(400, "message is required.")
    if len(message) > MAX_CHAT_MESSAGE_CHARS:
        raise RouteError(400, "message is too long.")
    return message


def _refuse_key_leak(audio: bytes, key: str) -> None:
    if not key:
        return
    encoded = key.encode("utf-8")
    if encoded and encoded in audio:
        raise RouteError(
            500,
            "Voice speak refused to return the API key.",
            code="fish_key_leak",
        )


def synthesize(
    text: str,
    *,
    http: HttpFn | None = None,
    model: str = DEFAULT_MODEL,
) -> bytes:
    """POST text to Fish Audio. Callers must already have checked the flag."""
    key = require_api_key()
    payload = json.dumps({"text": text, "format": "mp3"}).encode("utf-8")
    caller = http or _stdlib_http
    status, audio = caller(
        "POST",
        f"{FISH_API}{TTS_PATH}",
        _headers(key, model=model),
        payload,
    )
    if status >= 400 or not audio:
        raise RouteError(
            503,
            "Could not synthesize speech.",
            code="fish_tts_failed",
        )
    _refuse_key_leak(audio, key)
    return audio


def speak(
    body: dict[str, Any] | None,
    *,
    http: HttpFn | None = None,
) -> bytes:
    """Flag-gated speak. Disabled path never reads the key or opens HTTP."""
    _refuse_if_disabled()
    return synthesize(_message_text(body), http=http)
