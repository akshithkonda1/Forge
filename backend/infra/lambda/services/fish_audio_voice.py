"""Fish Audio TTS — ARIA's only voice module.

One provider (Fish Audio), one speak path. Dummy / on-device speech stays
the default: ``ARIA_FISH_VOICE_ENABLED`` is off unless explicitly truthy.
When the flag is off this module never reads ``FISH_AUDIO_API_KEY`` and
never calls ``api.fish.audio``.

TTS model ids (docs.fish.audio pricing + models overview):

* ``s2.1-pro-free`` — $0 default (Starter / development).
* ``s2.1-pro`` — $15 / M UTF-8 bytes. Off until ``FISH_AUDIO_USE_PAID`` is
  truthy (or ``FISH_AUDIO_MODEL=s2.1-pro``).
* ``s1`` retires 2026-12-31. Never selected.

Speak-only: no ``fuse_turn``, no ``remember_short_term``, no vault /
``recentPatterns`` writes, no dig payload, no coach_context side keys, no
``/ai/observe``. The caller already ran ``guard_speak`` — this path does
not rewrite prose. Personality (Coach / Friend / Drill Sergeant) is never
read or written here.

The Fish key stays server-side (process env). Never log or return it.
"""

from __future__ import annotations

import base64
import json
import os
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from typing import Any, Callable

from responses import RouteError
from security import MAX_CHAT_MESSAGE_CHARS

FISH_API = "https://api.fish.audio"
TTS_PATH = "/v1/tts"
LIST_PATH = "/model"
FISH_TTS_URL = f"{FISH_API}{TTS_PATH}"
FISH_LIST_URL = f"{FISH_API}{LIST_PATH}"

DEFAULT_MODEL = "s2.1-pro-free"
PAID_MODEL = "s2.1-pro"
API_KEY_ENV = "FISH_AUDIO_API_KEY"
ENABLED_ENV = "ARIA_FISH_VOICE_ENABLED"
MODEL_ENV = "FISH_AUDIO_MODEL"
PAID_ENV = "FISH_AUDIO_USE_PAID"
# S2.1-Pro family only. ``s1`` is rejected even if an env overlay asks for it.
ALLOWED_MODELS = frozenset({DEFAULT_MODEL, PAID_MODEL})

CACHE_TTL_SECONDS = 15 * 60
LIST_PAGE_SIZE = 50
LIST_MAX_PAGES = 4
CLIENT_PAGE_SIZE_MAX = 50
# Starter: 5 concurrent, 429 with no Retry-After. Three backoff sleeps.
BACKOFF_SECONDS = (0.25, 0.5, 1.0)

VOICE_BUSY_MESSAGE = "Voice is busy. The text reply is shown."
PREVIEW_TEXT = (
    "I'm ARIA. Let's look at how you actually slept and what that means for "
    "training today. One next move, not a new identity."
)

# Featured are original trait recipes. Voice ids come from the live Fish list.
# Names must not use trademarked characters or real actors (Toph is inspiration
# only, in docs/aria-voice.md — never in UI).
FEATURED_RECIPES: tuple[dict[str, Any], ...] = (
    {
        "id": "warm",
        "label": "Warm",
        "description": "Close, unhurried, a woman in the room.",
        "keywords": ("warm", "soft", "gentle", "female", "woman", "feminine"),
        "speed": 1.0,
    },
    {
        "id": "calm",
        "label": "Calm",
        "description": "Even, low, a man who is not in a hurry.",
        "keywords": ("calm", "deep", "male", "man", "masculine", "low"),
        "speed": 0.95,
    },
    {
        "id": "neutral",
        "label": "Neutral",
        "description": "Clear and even. Not styled as a man or a woman.",
        "keywords": ("neutral", "narrator", "androgynous", "clear", "balanced"),
        "speed": 1.0,
    },
    {
        "id": "spark",
        "label": "Spark",
        "description": "Brighter and a little faster. Still a coach, not a bit.",
        "keywords": ("energetic", "upbeat", "bright", "lively", "young"),
        "speed": 1.08,
    },
    {
        "id": "ember",
        "label": "Ember",
        "description": (
            "Blunt, gruff, confident. A young tomboy coach — original voice, "
            "not a character impression."
        ),
        "keywords": ("tomboy", "gruff", "blunt", "confident", "raspy", "young"),
        "speed": 1.05,
    },
)

# Never pin a featured profile to a cloned character or named actor.
_FEATURED_DENY = (
    "toph",
    "aang",
    "katara",
    "zuko",
    "sokka",
    "azula",
    "iroh",
    "korra",
    "avatar",
    "spongebob",
    "mickey",
    "disney",
    "celebrity",
    "impersonat",
    "as heard on",
)

_TRUE_FLAGS = frozenset({"1", "true", "yes", "on"})

HttpFn = Callable[[str, str, dict[str, str], bytes | None], tuple[int, bytes]]
SleepFn = Callable[[float], None]

_cache_lock = threading.Lock()
_voice_cache: list[dict[str, Any]] | None = None
_voice_cache_at = 0.0
_voice_cache_error = False


def reset_cache() -> None:
    """Tests only — drop the in-process Fish list cache."""
    global _voice_cache, _voice_cache_at, _voice_cache_error
    with _cache_lock:
        _voice_cache = None
        _voice_cache_at = 0.0
        _voice_cache_error = False


def fish_voice_enabled() -> bool:
    """Unset / empty / anything not in ``_TRUE_FLAGS`` is off."""
    return os.getenv(ENABLED_ENV, "").strip().lower() in _TRUE_FLAGS


def paid_model_enabled() -> bool:
    """Single server-side switch. Off by default → ``s2.1-pro-free``."""
    return os.getenv(PAID_ENV, "").strip().lower() in _TRUE_FLAGS


def sanitize_model(raw: str | None) -> str:
    trimmed = (raw or "").strip()
    if trimmed == "s1" or trimmed.startswith("s1-"):
        return DEFAULT_MODEL
    if trimmed in ALLOWED_MODELS:
        return trimmed
    return DEFAULT_MODEL


def resolve_model(raw: str | None = None) -> str:
    """Env model wins when it is S2.1-Pro; else the paid switch; else free."""
    overlay = (raw if raw is not None else os.getenv(MODEL_ENV) or "").strip()
    if overlay in ALLOWED_MODELS:
        return overlay
    if paid_model_enabled():
        return PAID_MODEL
    return DEFAULT_MODEL


def _headers(api_key: str, *, model: str | None = None) -> dict[str, str]:
    return {
        "Authorization": f"Bearer {api_key}",
        "Content-Type": "application/json",
        "model": resolve_model(model),
    }


def build_headers(api_key: str, model: str | None = None) -> dict[str, str]:
    return _headers(api_key, model=model)


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


def _line_from_body(body: dict[str, Any] | None, *, preview: bool = False) -> str:
    """Accept ``message`` (Iris) or ``text`` (Hex). Preview uses the sample line."""
    if preview:
        return PREVIEW_TEXT
    raw = "" if body is None else body.get("message")
    if not isinstance(raw, str) or not raw.strip():
        raw = "" if body is None else body.get("text")
    if not isinstance(raw, str):
        raw = str(raw or "")
    line = raw.strip()
    if not line:
        raise RouteError(400, "message is required.", code="fish_audio_empty_text")
    if len(line) > MAX_CHAT_MESSAGE_CHARS:
        raise RouteError(400, "message is too long.", code="fish_audio_empty_text")
    return line


def _clamp_speed(raw: Any) -> float:
    try:
        value = float(raw)
    except (TypeError, ValueError):
        return 1.0
    return max(0.5, min(2.0, value))


def _refuse_key_leak(blob: bytes | str, key: str) -> None:
    if not key:
        return
    text = blob if isinstance(blob, str) else blob.decode("utf-8", errors="replace")
    if key and key in text:
        raise RouteError(
            500,
            "Voice speak refused to return the API key.",
            code="fish_key_leak",
        )
    encoded = key.encode("utf-8")
    if isinstance(blob, (bytes, bytearray)) and encoded and encoded in blob:
        raise RouteError(
            500,
            "Voice speak refused to return the API key.",
            code="fish_key_leak",
        )


def _tts_body(text: str, *, reference_id: str | None, speed: float) -> bytes:
    payload: dict[str, Any] = {
        "text": text,
        "format": "mp3",
        "normalize": True,
        "latency": "normal",
        "prosody": {
            "speed": _clamp_speed(speed),
            "volume": 0,
            "normalize_loudness": True,
        },
    }
    if reference_id:
        payload["reference_id"] = reference_id
    return json.dumps(payload).encode("utf-8")


def synthesize(
    text: str,
    *,
    http: HttpFn | None = None,
    model: str | None = None,
    reference_id: str | None = None,
    speed: float = 1.0,
    sleep: SleepFn | None = None,
) -> bytes:
    """POST text to Fish Audio. Callers must already have checked the flag."""
    key = require_api_key()
    line = (text or "").strip()
    payload = _tts_body(line, reference_id=reference_id, speed=speed)
    caller = http or _stdlib_http
    sleeper = sleep or time.sleep
    chosen = resolve_model(model)
    headers = build_headers(key, chosen)
    status = 0
    audio = b""
    for attempt in range(len(BACKOFF_SECONDS) + 1):
        status, audio = caller("POST", FISH_TTS_URL, headers, payload)
        if status != 429:
            break
        if attempt >= len(BACKOFF_SECONDS):
            raise RouteError(429, VOICE_BUSY_MESSAGE, code="fish_voice_busy")
        sleeper(BACKOFF_SECONDS[attempt])
    if status >= 400 or not audio:
        raise RouteError(
            503,
            "Could not synthesize speech.",
            code="fish_tts_failed",
        )
    _refuse_key_leak(audio, key)
    return audio


def _normalize_voice(item: Any) -> dict[str, Any] | None:
    if not isinstance(item, dict):
        return None
    voice_id = str(item.get("_id") or item.get("id") or "").strip()
    title = str(item.get("title") or item.get("name") or "").strip()
    if not voice_id:
        return None
    if item.get("dmca_taken_down") is True:
        return None
    tags = item.get("tags") if isinstance(item.get("tags"), list) else []
    languages = item.get("languages") if isinstance(item.get("languages"), list) else []
    return {
        "id": voice_id,
        "title": title or voice_id,
        "description": str(item.get("description") or "").strip(),
        "tags": [str(tag) for tag in tags if str(tag).strip()],
        "languages": [str(lang) for lang in languages if str(lang).strip()],
        "state": str(item.get("state") or ""),
        "licensed": bool(item.get("licensed")),
    }


def _haystack(voice: dict[str, Any]) -> str:
    parts = [
        str(voice.get("title") or ""),
        str(voice.get("description") or ""),
        " ".join(str(tag) for tag in voice.get("tags") or []),
    ]
    return " ".join(parts).lower()


def _denied_for_featured(voice: dict[str, Any]) -> bool:
    hay = _haystack(voice)
    return any(token in hay for token in _FEATURED_DENY)


def _score_recipe(voice: dict[str, Any], keywords: tuple[str, ...]) -> int:
    hay = _haystack(voice)
    return sum(1 for word in keywords if word in hay)


def match_featured(voices: list[dict[str, Any]]) -> list[dict[str, Any]]:
    """Map trait recipes onto live Fish ids. No hardcoded placeholders."""
    used: set[str] = set()
    featured: list[dict[str, Any]] = []
    eligible = [voice for voice in voices if not _denied_for_featured(voice)]
    for recipe in FEATURED_RECIPES:
        best: dict[str, Any] | None = None
        best_score = 0
        for voice in eligible:
            if voice["id"] in used:
                continue
            score = _score_recipe(voice, recipe["keywords"])
            if score > best_score:
                best = voice
                best_score = score
        row = {
            "id": recipe["id"],
            "label": recipe["label"],
            "description": recipe["description"],
            "speed": recipe["speed"],
            "voice_id": best["id"] if best and best_score > 0 else None,
            "voice_title": best["title"] if best and best_score > 0 else None,
        }
        if best and best_score > 0:
            used.add(best["id"])
        featured.append(row)
    return featured


def _list_url(page_number: int) -> str:
    query = urllib.parse.urlencode(
        {
            "page_size": LIST_PAGE_SIZE,
            "page_number": page_number,
            "sort_by": "score",
        }
    )
    return f"{FISH_LIST_URL}?{query}"


def _fetch_library(http: HttpFn, key: str) -> list[dict[str, Any]]:
    voices: list[dict[str, Any]] = []
    headers = {
        "Authorization": f"Bearer {key}",
        "Accept": "application/json",
        "model": resolve_model(),
    }
    for page in range(1, LIST_MAX_PAGES + 1):
        status, raw = http("GET", _list_url(page), headers, None)
        if status >= 400:
            raise RouteError(
                503,
                "Could not list Fish Audio voices.",
                code="fish_list_failed",
            )
        try:
            payload = json.loads(raw.decode("utf-8") if raw else "{}")
        except json.JSONDecodeError as exc:
            raise RouteError(
                503,
                "Could not list Fish Audio voices.",
                code="fish_list_failed",
            ) from exc
        items = payload.get("items") if isinstance(payload, dict) else None
        if not isinstance(items, list):
            break
        for item in items:
            voice = _normalize_voice(item)
            if voice:
                voices.append(voice)
        if not payload.get("has_more"):
            break
        if len(items) < LIST_PAGE_SIZE:
            break
    return voices


def cached_voices(*, http: HttpFn | None = None) -> tuple[list[dict[str, Any]], bool, bool]:
    """Return (voices, cached, fallback). Never raises to the catalog route."""
    global _voice_cache, _voice_cache_at, _voice_cache_error
    now = time.time()
    with _cache_lock:
        if (
            _voice_cache is not None
            and (now - _voice_cache_at) < CACHE_TTL_SECONDS
        ):
            return list(_voice_cache), True, _voice_cache_error
    if not fish_voice_enabled():
        return [], False, True
    try:
        key = require_api_key()
    except RouteError:
        return [], False, True
    caller = http or _stdlib_http
    try:
        voices = _fetch_library(caller, key)
    except RouteError:
        return [], False, True
    with _cache_lock:
        _voice_cache = list(voices)
        _voice_cache_at = time.time()
        _voice_cache_error = False
    return voices, False, False


def default_voice_id(voices: list[dict[str, Any]], featured: list[dict[str, Any]]) -> str | None:
    for row in featured:
        if row.get("voice_id"):
            return str(row["voice_id"])
    if voices:
        return str(voices[0]["id"])
    return None


def _stored_profile(user_id: str) -> dict[str, Any]:
    uid = (user_id or "").strip()
    if not uid:
        return {}
    from storage import dynamodb
    from storage import keys

    key = keys.aria_voice_profile_key(uid)
    item = dynamodb.get_item(key["pk"], key["sk"])
    if not isinstance(item, dict):
        return {}
    payload = item.get("payload") if isinstance(item.get("payload"), dict) else item
    return {
        "profile_id": str(payload.get("profile_id") or "").strip() or None,
        "voice_id": str(payload.get("voice_id") or "").strip() or None,
        "speed": _clamp_speed(payload.get("speed", 1.0)),
    }


def save_profile(user_id: str, body: dict[str, Any] | None) -> dict[str, Any]:
    uid = (user_id or "").strip()
    payload = body or {}
    profile_id = str(payload.get("profile_id") or payload.get("id") or "").strip()
    voice_id = str(payload.get("voice_id") or "").strip()
    speed = payload.get("speed")
    known = {row["id"] for row in FEATURED_RECIPES}
    if profile_id and profile_id not in known and not voice_id:
        raise RouteError(400, "Unknown voice profile.", code="fish_unknown_profile")
    recipe = next((row for row in FEATURED_RECIPES if row["id"] == profile_id), None)
    stored = {
        "profile_id": profile_id or None,
        "voice_id": voice_id or None,
        "speed": _clamp_speed(speed if speed is not None else (recipe or {}).get("speed", 1.0)),
    }
    if uid:
        from storage import dynamodb
        from storage import keys

        key = keys.aria_voice_profile_key(uid)
        dynamodb.put_item({**key, "payload": stored, "user_id": uid})
    return stored


def resolve_selection(
    user_id: str,
    body: dict[str, Any] | None,
    *,
    voices: list[dict[str, Any]] | None = None,
    featured: list[dict[str, Any]] | None = None,
) -> dict[str, Any]:
    """Request override, then the account row, then the first featured match."""
    payload = body or {}
    stored = _stored_profile(user_id)
    catalog = voices if voices is not None else []
    pins = featured if featured is not None else match_featured(catalog)
    profile_id = str(payload.get("profile_id") or stored.get("profile_id") or "").strip()
    voice_id = str(payload.get("voice_id") or stored.get("voice_id") or "").strip()
    speed = payload.get("speed")
    if profile_id:
        recipe = next((row for row in pins if row["id"] == profile_id), None)
        if recipe:
            if not voice_id:
                voice_id = str(recipe.get("voice_id") or "")
            if speed is None:
                speed = recipe.get("speed")
    if not voice_id:
        voice_id = default_voice_id(catalog, pins) or ""
    if speed is None:
        speed = stored.get("speed", 1.0)
    return {
        "profile_id": profile_id or None,
        "voice_id": voice_id or None,
        "speed": _clamp_speed(speed),
    }


def catalog(
    user_id: str,
    *,
    query: str = "",
    page: int = 1,
    page_size: int = 20,
    http: HttpFn | None = None,
) -> dict[str, Any]:
    """Featured recipes + paginated Fish list. Fish errors become a fallback."""
    voices, cached, fallback = cached_voices(http=http)
    featured = match_featured(voices)
    needle = (query or "").strip().lower()
    filtered = voices
    if needle:
        filtered = [voice for voice in voices if needle in _haystack(voice)]
    size = max(1, min(int(page_size or 20), CLIENT_PAGE_SIZE_MAX))
    index = max(1, int(page or 1))
    start = (index - 1) * size
    window = filtered[start : start + size]
    selected = resolve_selection(user_id, None, voices=voices, featured=featured)
    payload = {
        "model": resolve_model(),
        "preview_text": PREVIEW_TEXT,
        "selected": selected,
        "featured": featured,
        "voices": window,
        "page": index,
        "page_size": size,
        "total": len(filtered),
        "has_more": start + size < len(filtered),
        "cached": cached,
        "source": "fallback" if fallback else "fish",
        "fallback_voice_id": default_voice_id(voices, featured),
    }
    key = (os.getenv(API_KEY_ENV) or "").strip()
    _refuse_key_leak(json.dumps(payload), key)
    return payload


def speak(
    body: dict[str, Any] | None,
    *,
    user_id: str = "",
    http: HttpFn | None = None,
    sleep: SleepFn | None = None,
) -> dict[str, str | float | None]:
    """Flag-gated speak. Disabled path never reads the key or opens HTTP."""
    _refuse_if_disabled()
    preview = bool((body or {}).get("preview"))
    text = _line_from_body(body, preview=preview)
    # Speak uses the account / request voice id. Catalog fetch stays on GET /ai/voice.
    selection = resolve_selection(user_id, body, voices=[], featured=match_featured([]))
    model = resolve_model()
    audio = synthesize(
        text,
        http=http,
        model=model,
        reference_id=selection.get("voice_id"),
        speed=float(selection.get("speed") or 1.0),
        sleep=sleep,
    )
    encoded = base64.b64encode(audio).decode("ascii")
    payload = {
        "format": "mp3",
        "model": model,
        "audio_base64": encoded,
        "voice_id": selection.get("voice_id"),
        "profile_id": selection.get("profile_id"),
        "speed": selection.get("speed"),
        "preview": preview,
    }
    key = (os.getenv(API_KEY_ENV) or "").strip()
    _refuse_key_leak(json.dumps(payload), key)
    return payload
