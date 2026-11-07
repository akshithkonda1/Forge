"""Kokoro-82M catalog — on-device mouth only.

Hex never synthesizes speech. GET /ai/voice returns the shipped Kokoro
presets. PUT /ai/voice stores the selected preset. POST /ai/voice/speak
is gone. Dummy / offline / over-quota never open HTTP from this module.

Licenses: hexgrad/Kokoro-82M and mattmireles/kokoro-coreml are Apache-2.0.
Ship preset voices only. ARIA's locked preset is ``af_heart``.
"""

from __future__ import annotations

from typing import Any

from responses import RouteError

PROVIDER = "kokoro"
MODEL = "kokoro-82m"
ARIA_PRESET = "af_heart"
LICENSE = "Apache-2.0"
PACKAGE = "mattmireles/kokoro-coreml"
WEIGHTS = "hexgrad/Kokoro-82M"
STARTER_BUNDLE_MB = 210
PREVIEW_TEXT = (
    "I'm ARIA. Let's look at how you actually slept and what that means for "
    "training today. One next move, not a new identity."
)
LOAD_FAILED_MESSAGE = "Voice could not load. The text reply is shown."

ALLOWED_PRESETS = frozenset(
    {"af_heart", "af_bella", "af_sarah", "af_aoede", "am_michael"}
)

FEATURED_RECIPES: tuple[dict[str, Any], ...] = (
    {
        "id": "warm",
        "label": "Warm",
        "description": "Close, unhurried, a woman in the room.",
        "voice_id": "af_heart",
        "speed": 1.0,
    },
    {
        "id": "calm",
        "label": "Calm",
        "description": "Even, low, a man who is not in a hurry.",
        "voice_id": "am_michael",
        "speed": 0.95,
    },
    {
        "id": "neutral",
        "label": "Neutral",
        "description": "Clear and even. Not styled as a man or a woman.",
        "voice_id": "af_sarah",
        "speed": 1.0,
    },
    {
        "id": "spark",
        "label": "Spark",
        "description": "Brighter and a little faster. Still a coach, not a bit.",
        "voice_id": "af_aoede",
        "speed": 1.08,
    },
    {
        "id": "ember",
        "label": "Ember",
        "description": (
            "Blunt, gruff, confident. A young tomboy coach — original voice, "
            "not a character impression."
        ),
        "voice_id": "af_bella",
        "speed": 1.05,
    },
)

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


def sanitize_preset(raw: str | None) -> str:
    trimmed = str(raw or "").strip()
    return trimmed if trimmed in ALLOWED_PRESETS else ARIA_PRESET


def featured() -> list[dict[str, Any]]:
    return [dict(row) for row in FEATURED_RECIPES]


def labels_avoid_trademarked_characters(
    rows: list[dict[str, Any]] | None = None,
) -> bool:
    blob = " ".join(
        f"{row.get('id', '')} {row.get('label', '')} {row.get('description', '')}"
        for row in (rows if rows is not None else FEATURED_RECIPES)
    ).lower()
    return all(token not in blob for token in _FEATURED_DENY)


def _clamp_speed(value: Any) -> float:
    try:
        speed = float(value)
    except (TypeError, ValueError):
        return 1.0
    return max(0.7, min(speed, 1.2))


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
        "voice_id": sanitize_preset(payload.get("voice_id")),
        "speed": _clamp_speed(payload.get("speed", 1.0)),
    }


def save_profile(user_id: str, body: dict[str, Any] | None) -> dict[str, Any]:
    uid = (user_id or "").strip()
    payload = body or {}
    profile_id = str(payload.get("profile_id") or payload.get("id") or "").strip()
    known = {row["id"] for row in FEATURED_RECIPES}
    recipe = next((row for row in FEATURED_RECIPES if row["id"] == profile_id), None)
    if profile_id and profile_id not in known:
        raise RouteError(400, "Unknown voice profile.", code="kokoro_unknown_profile")
    voice_id = sanitize_preset(
        payload.get("voice_id") or (recipe or {}).get("voice_id") or ARIA_PRESET
    )
    stored = {
        "profile_id": profile_id or "warm",
        "voice_id": voice_id,
        "speed": _clamp_speed(
            payload.get("speed")
            if payload.get("speed") is not None
            else (recipe or {}).get("speed", 1.0)
        ),
    }
    if uid:
        from storage import dynamodb
        from storage import keys

        key = keys.aria_voice_profile_key(uid)
        dynamodb.put_item({**key, "payload": stored, "user_id": uid})
    return stored


def resolve_selection(user_id: str, body: dict[str, Any] | None) -> dict[str, Any]:
    payload = body or {}
    stored = _stored_profile(user_id)
    profile_id = str(payload.get("profile_id") or stored.get("profile_id") or "warm").strip()
    recipe = next((row for row in FEATURED_RECIPES if row["id"] == profile_id), FEATURED_RECIPES[0])
    voice_id = sanitize_preset(
        payload.get("voice_id") or stored.get("voice_id") or recipe["voice_id"]
    )
    speed = payload.get("speed")
    if speed is None:
        speed = stored.get("speed", recipe["speed"])
    return {
        "profile_id": recipe["id"],
        "voice_id": voice_id,
        "speed": _clamp_speed(speed),
    }


def catalog(
    user_id: str,
    *,
    query: str = "",
    page: int = 1,
    page_size: int = 20,
) -> dict[str, Any]:
    """Local Kokoro presets. Never opens a socket."""
    pins = featured()
    needle = (query or "").strip().lower()
    filtered = pins
    if needle:
        filtered = [
            row
            for row in pins
            if needle
            in f"{row['id']} {row['label']} {row['description']} {row['voice_id']}".lower()
        ]
    size = max(1, min(int(page_size or 20), 20))
    index = max(1, int(page or 1))
    start = (index - 1) * size
    window = filtered[start : start + size]
    return {
        "provider": PROVIDER,
        "model": MODEL,
        "license": LICENSE,
        "preview_text": PREVIEW_TEXT,
        "selected": resolve_selection(user_id, None),
        "featured": pins,
        "voices": window,
        "page": index,
        "page_size": size,
        "total": len(filtered),
        "has_more": start + size < len(filtered),
        "source": PROVIDER,
        "aria_preset": ARIA_PRESET,
        "starter_bundle_mb": STARTER_BUNDLE_MB,
    }
