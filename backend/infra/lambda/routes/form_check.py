"""Form-check and session-briefing coaching, server-side.

This route exists because the iOS client was calling `api.anthropic.com`
directly, with a key read from `Bundle.main.infoDictionary["ANTHROPIC_API_KEY"]`.
That is an extractable secret in any build that sets it — trivial to pull from a
downloaded IPA — and every one of those requests skipped auth, `security.py`
sanitization, the model router, the security law, and all cost controls.

So the interesting part of this file is not what it generates, it is that
generation happens *here*: behind the JWT authorizer, with the caller's identity
taken from the token rather than the body, with text sanitized, and through the
same `live_system_prompt()` every other live surface uses.

Vision is not routed yet. `BedrockGateway.converse()` calls the native Converse
operation, and whether image content blocks work through it against the
configured models is unverified — see the Grok verification note in ai_router.py
for the same class of unknown. Rather than guess, the vision mode answers
`available: false`, which the client already knows how to handle: it falls back
to the on-device heuristic it used whenever the API key was absent. The client
integration point is therefore unchanged, and no key ships in the binary.
"""

from __future__ import annotations

import re
from typing import Any

from responses import RouteError, ok
from security import assert_body_user_matches_auth, sanitize_user_text
from services import aria_engine

# A frame at the client's own downscale settings (1024px, JPEG q0.55) lands well
# under this; the cap is here so a malformed or hostile client cannot push a
# multi-megabyte body through the request path before anything looks at it.
MAX_IMAGE_BASE64_CHARS = 400_000
MAX_FIELD_CHARS = 200
MAX_CUES = 6
MAX_SNAPSHOT_CHARS = 4_000

_WHITESPACE_RE = re.compile(r"\s+")

_BRIEFING_TASK = """
TASK — write a session debrief: 3-4 sentences, prose only, no markdown, no lists.
Reference the strongest concrete numbers in the summary, name one balance or
recovery observation, and end with a single specific focus for next session.
""".strip()


def _bind_user(body: dict[str, Any], user_id: str) -> str:
    try:
        return assert_body_user_matches_auth(body, user_id)
    except PermissionError as exc:
        raise RouteError(403, str(exc)) from exc


def _clean_context(raw: Any) -> dict[str, Any]:
    """Whitespace-normalized, length-capped view of the live workout context.

    Every field is client-authored, so all of it is untrusted text headed for a
    prompt — it goes through the same sanitizer as a chat message.
    """
    if not isinstance(raw, dict):
        raise RouteError(400, "'context' must be an object.")

    def text(key: str) -> str:
        # Every one of these is a single-line label — an exercise name, a set
        # label, an elapsed time. `sanitize_user_text` keeps ordinary newlines,
        # which is right for a chat message and wrong here: a newline in a field
        # this short is never legitimate and is exactly the shape used to fake a
        # new section of the prompt. Collapse to spaces, then sanitize.
        flattened = _WHITESPACE_RE.sub(" ", str(raw.get(key) or ""))
        return sanitize_user_text(flattened, max_chars=MAX_FIELD_CHARS)

    def number(key: str) -> int:
        value = raw.get(key)
        if isinstance(value, bool) or not isinstance(value, (int, float)):
            return 0
        return int(value)

    cues_raw = raw.get("cues")
    cues = [
        sanitize_user_text(_WHITESPACE_RE.sub(" ", str(c)), max_chars=MAX_FIELD_CHARS)
        for c in (cues_raw if isinstance(cues_raw, list) else [])
    ]

    exercise = text("exerciseName")
    if not exercise:
        raise RouteError(400, "'context.exerciseName' is required.")

    return {
        "exerciseName": exercise,
        "setLabel": text("setLabel"),
        "weight": number("weight"),
        "reps": text("reps"),
        "heartRate": number("heartRate"),
        "hrZone": number("hrZone"),
        "spO2": number("spO2"),
        "elapsed": text("elapsed"),
        "cues": [c for c in cues if c][:MAX_CUES],
    }


def handle_post_form_check(body: dict[str, Any], *, user_id: str) -> dict:
    """`POST /workouts/form-check` — vision form read, or a session briefing."""
    _bind_user(body, user_id)
    mode = str(body.get("mode") or "vision").strip().lower()

    if mode == "briefing":
        snapshot = sanitize_user_text(
            str(body.get("snapshot") or ""), max_chars=MAX_SNAPSHOT_CHARS
        )
        if not snapshot:
            raise RouteError(400, "'snapshot' is required for a briefing.")
        text = aria_engine.generate_coach_text(_BRIEFING_TASK, snapshot)
        if not text:
            return ok({"available": False, "reason": "live_reasoning_disabled"})
        return ok({"available": True, "briefing": text})

    if mode != "vision":
        raise RouteError(400, "'mode' must be 'vision' or 'briefing'.")

    context = _clean_context(body.get("context"))
    image = body.get("image_base64")
    if image is not None:
        if not isinstance(image, str):
            raise RouteError(400, "'image_base64' must be a string.")
        if len(image) > MAX_IMAGE_BASE64_CHARS:
            raise RouteError(413, "Frame too large.")

    # Deliberately not guessing at image support through the native Converse
    # operation. The client falls back to its on-device read, which is what it
    # did whenever the key was absent — i.e. in every build shipped so far.
    return ok(
        {
            "available": False,
            "reason": "vision_routing_unavailable",
            "context": {"exerciseName": context["exerciseName"]},
        }
    )
