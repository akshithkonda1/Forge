"""Form-check and session-briefing coaching.

Vision form-check stays on the iPhone (Vision / CoreML, plus Foundation
Models where an API is available). Apple Private Cloud Compute is only
reached through Apple's own frameworks — Forge never sends a frame or
pose to its servers. A posted ``image_base64`` is refused with 451.

The briefing mode, if ever called, is text-only, JWT-authenticated, and
sanitized. The iOS client currently authors the briefing on-device and
does not post a snapshot.
"""

from __future__ import annotations

import re
from typing import Any

from responses import RouteError, ok
from security import assert_body_user_matches_auth, sanitize_user_text
from aria_core import aria_engine

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

    if body.get("image_base64") is not None:
        raise RouteError(
            451,
            "Form-check vision stays on device, never goes to a server.",
            code="form_check_on_device",
        )
    context = _clean_context(body.get("context"))
    return ok(
        {
            "available": False,
            "reason": "form_check_stays_on_device",
            "context": {"exerciseName": context["exerciseName"]},
        }
    )
