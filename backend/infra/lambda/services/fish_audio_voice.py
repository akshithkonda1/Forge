"""Fish Audio TTS — Hex pattern: the key stays on Lambda.

POST ``https://api.fish.audio/v1/tts``
Authorization: Bearer <FISH_AUDIO_API_KEY>
``model`` header: ``s2.1-pro-free`` (idle / free-first) or ``s2.1-pro``.

Process env wins, then Parameter Store / the existing AI provider secret.
The phone never receives the key. Dummy-offline does not call this route.
"""

from __future__ import annotations

import json
import urllib.error
import urllib.request
from typing import Any, Callable

from responses import RouteError
from services.provider_secrets import load_ai_provider_secret

FISH_TTS_URL = "https://api.fish.audio/v1/tts"
DEFAULT_MODEL = "s2.1-pro-free"
PAID_MODEL = "s2.1-pro"
ALLOWED_MODELS = frozenset(
    {"s1", "s2-pro", "s2.1-pro", "s2.1-pro-free", "drama-3-preview"}
)

HttpFn = Callable[[str, str, dict[str, str], bytes | None], tuple[int, bytes]]


def credentials(*, get_secret_value=None) -> dict[str, str]:
    return load_ai_provider_secret(get_secret_value=get_secret_value)


def sanitize_model(raw: str | None) -> str:
    trimmed = (raw or "").strip()
    if trimmed in ALLOWED_MODELS:
        return trimmed
    return DEFAULT_MODEL


def require_api_key(*, get_secret_value=None) -> str:
    key = (credentials(get_secret_value=get_secret_value).get("FISH_AUDIO_API_KEY") or "").strip()
    if not key or key.upper() == "UNSET":
        raise RouteError(
            503,
            "Fish Audio is not configured. Set FISH_AUDIO_API_KEY in env or the AI provider secret.",
            code="fish_audio_unconfigured",
        )
    return key


def build_headers(api_key: str, model: str) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {api_key}",
        "model": sanitize_model(model),
        "Content-Type": "application/json",
    }


def build_body(text: str, *, reference_id: str | None = None) -> bytes:
    payload: dict[str, Any] = {
        "text": text.strip(),
        "format": "mp3",
        "mp3_bitrate": 128,
        "normalize": True,
        "latency": "normal",
    }
    if reference_id:
        payload["reference_id"] = reference_id
    return json.dumps(payload).encode("utf-8")


def synthesize(
    text: str,
    *,
    http: HttpFn | None = None,
    get_secret_value=None,
) -> bytes:
    line = (text or "").strip()
    if not line:
        raise RouteError(400, "text is required.", code="fish_audio_empty_text")
    creds = credentials(get_secret_value=get_secret_value)
    key = require_api_key(get_secret_value=get_secret_value)
    model = sanitize_model(creds.get("FISH_AUDIO_MODEL"))
    caller = http or _stdlib_http
    status, audio = caller("POST", FISH_TTS_URL, build_headers(key, model), build_body(line))
    if status >= 400 or not audio:
        raise RouteError(
            503,
            "Could not synthesize speech.",
            code="fish_audio_failed",
        )
    return audio


def _stdlib_http(method: str, url: str, headers: dict[str, str], body: bytes | None) -> tuple[int, bytes]:
    request = urllib.request.Request(url, data=body, headers=headers, method=method)
    try:
        with urllib.request.urlopen(request, timeout=20) as response:
            return int(response.status), response.read()
    except urllib.error.HTTPError as exc:
        return int(exc.code), exc.read() if exc.fp else b""
    except (urllib.error.URLError, TimeoutError, OSError):
        return 503, b""
