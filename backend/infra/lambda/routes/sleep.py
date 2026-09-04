from __future__ import annotations

import base64
import binascii
from typing import Any

from responses import RouteError, ok
from security import assert_body_user_matches_auth, demo_data_enabled
from seed_data import default_sleep
from services import aria_engine
from storage import dynamodb, keys

# A frame at the client's own downscale settings (1024px, JPEG q0.55, same
# helper `ARIACoachService` already uses) lands well under this; the cap is
# here so a malformed or hostile client cannot push a multi-megabyte body
# through the request path before anything looks at it.
MAX_IMAGE_BASE64_CHARS = 400_000

_ENVIRONMENT_TASK = """
TASK — the user shared a photo of the room they sleep in. In 2-4 sentences,
prose only, no markdown, no lists: name the one or two things actually
visible in the photo most likely to be costing them sleep — light sources,
screens, clutter near the bed, temperature or airflow cues, visible noise
sources, bedding — and one concrete, low-effort change for each. Warm and
practical, like a friend glancing over the room with them, never clinical.
Do not moralize and do not use words like "bad," "wrong," "messy," or
"unhealthy." Do not comment on decor taste, tidiness as a personal trait,
or anything in the photo unrelated to sleep.
""".strip()

_ENVIRONMENT_PROMPT = "Here's a photo of where I sleep. What's worth changing?"


def handle_post_sleep_environment_check(body: dict[str, Any], *, user_id: str) -> dict:
    """`POST /sleep/environment-check` — a real vision read of a room photo.

    Mirrors `routes/form_check.py`'s auth/size-cap shape, but this path
    actually calls the model: `BedrockGateway.converse` now accepts an image
    content block (see `ai_router.py`), so there is no "vision routing
    unavailable" stub here — only the same never-raise degrade every other
    live surface uses when Bedrock itself is off or the call fails.
    """
    try:
        assert_body_user_matches_auth(body, user_id)
    except PermissionError as exc:
        raise RouteError(403, str(exc)) from exc

    image = body.get("image_base64")
    if not isinstance(image, str) or not image:
        raise RouteError(400, "'image_base64' is required.")
    if len(image) > MAX_IMAGE_BASE64_CHARS:
        raise RouteError(413, "Image too large.")

    try:
        image_bytes = base64.b64decode(image, validate=True)
    except (binascii.Error, ValueError) as exc:
        raise RouteError(400, "'image_base64' is not valid base64.") from exc

    text = aria_engine.generate_coach_vision(
        _ENVIRONMENT_TASK, _ENVIRONMENT_PROMPT, image_bytes, agent="sleep"
    )
    if not text:
        return ok({"available": False, "reason": "live_reasoning_disabled"})
    return ok({"available": True, "assessment": text})


def _load_sleep(user_id: str, days: int) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=days)
    if items:
        return [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in items]
    return default_sleep()[:days] if demo_data_enabled() else []


def handle_get_sleep(user_id: str, days: int) -> dict:
    return ok({"sleep": _load_sleep(user_id, days)})


def handle_post_sleep_sessions(user_id: str, body: dict) -> dict:
    session = body.get("session")
    if not isinstance(session, dict):
        from responses import RouteError
        raise RouteError(400, "Request body must include a 'session' object.")

    date = session.get("date", "")
    source = session.get("source", "manual")
    if not date:
        from responses import RouteError
        raise RouteError(400, "'session.date' is required.")

    # A malformed score doesn't fail here — it fails later, in an unrelated
    # read (readiness.py, coach/*, progress/summary all do
    # float(latest.get("score", 75))) once this record is the "latest" one.
    # Reject it here instead of persisting something every future reader has
    # to defend against.
    score = session.get("score")
    if score is not None and (isinstance(score, bool) or not isinstance(score, (int, float))):
        from responses import RouteError
        raise RouteError(400, "'session.score' must be a number.")

    item = {**keys.sleep_key(user_id, date, source), **session}
    dynamodb.put_item(item)
    return ok({"session": session})
