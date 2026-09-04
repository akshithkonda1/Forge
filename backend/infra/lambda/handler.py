import binascii
import json
import logging
import os
import uuid
from base64 import b64decode
from datetime import datetime, timezone

from ai_router import (
    AIRouter,
    RouteRequest,
    RoutingError,
    bedrock_enabled,
    default_models,
    humanize_bytes,
)
from auth import extract_user_id
from responses import RouteError, error_response, not_found, ok
from routes import (
    aria,
    biometrics,
    chat,
    coach,
    dashboard,
    devices,
    form_check,
    health,
    integrations,
    profile,
    progress,
    sleep,
    watch,
    workouts,
)
from security import (
    MAX_JSON_BODY_CHARS,
    is_production_like,
    redacted_health_payload,
)


LOGGER = logging.getLogger("forge.handler")

# Base64 inflates by 4/3, so this is the encoded ceiling for a body that could
# still be under MAX_JSON_BODY_CHARS once decoded. Checked *before* decoding, so
# a 50 MB payload is rejected on its length rather than after being expanded
# into the function's memory.
MAX_ENCODED_BODY_CHARS = (MAX_JSON_BODY_CHARS * 4) // 3 + 4


def _parse_json_body(event: dict) -> dict:
    body = event.get("body")
    if not body:
        return {}

    # A dict body only happens when something upstream already parsed it (test
    # harnesses, direct invokes). Checked before the base64 branch because
    # b64decode raises TypeError on a dict.
    if isinstance(body, dict):
        return body

    if isinstance(body, str) and len(body) > MAX_ENCODED_BODY_CHARS:
        raise RouteError(413, "Request body too large.")

    if event.get("isBase64Encoded"):
        try:
            decoded = b64decode(body, validate=True)
        except (binascii.Error, ValueError, TypeError) as exc:
            raise RouteError(400, "Request body is not valid base64.") from exc
        try:
            # Split from the decode above deliberately: UnicodeDecodeError is a
            # subclass of ValueError, so a single combined `except` would
            # swallow it into the base64 message and mislead the client.
            body = decoded.decode("utf-8")
        except UnicodeDecodeError as exc:
            raise RouteError(400, "Request body must be UTF-8 text.") from exc

    if isinstance(body, str) and len(body) > MAX_JSON_BODY_CHARS:
        raise RouteError(413, "Request body too large.")

    try:
        parsed = json.loads(body)
    except (json.JSONDecodeError, TypeError, ValueError) as exc:
        raise RouteError(400, "Request body must be valid JSON.") from exc

    # json.loads happily returns a list, a string, a number, or None. Every
    # route downstream calls body.get(...), so anything but an object used to
    # escape the handler as an AttributeError and surface as a bare 502 — a
    # client only had to send `[]` to reach it.
    if not isinstance(parsed, dict):
        raise RouteError(400, "Request body must be a JSON object.")

    return parsed


def _query_int(event: dict, name: str, default: int, *, minimum: int = 1, maximum: int = 365) -> int:
    params = event.get("queryStringParameters") or {}
    try:
        value = int(params.get(name, default))
    except (TypeError, ValueError):
        return default
    return max(minimum, min(maximum, value))


def _route(event, _context):
    request_context = event.get("requestContext", {})
    http_context = request_context.get("http", {})
    method = http_context.get("method", "GET")
    path = http_context.get("path", "/")
    if path != "/":
        path = path.rstrip("/")

    # --- Health check (no auth) — never inventory infra in production ---
    if method == "GET" and path == "/health":
        if is_production_like() and os.getenv("FORGE_HEALTH_VERBOSE", "").lower() not in {
            "1",
            "true",
            "yes",
        }:
            return ok(redacted_health_payload())
        models = default_models()
        return ok({
            "status": "ok",
            "service": "forge-backend",
            "environment": os.getenv("ENVIRONMENT", "unknown"),
            "timestamp": datetime.now(timezone.utc).isoformat(),
            "resources": {
                "appDataTable": os.getenv("APP_DATA_TABLE_NAME"),
                "uploadsBucket": os.getenv("UPLOADS_BUCKET_NAME"),
                "userPoolId": os.getenv("USER_POOL_ID"),
            },
            "router": {
                "maxPackageBytes": 10 * 1024 * 1024 * 1024,
                "maxPackageHuman": humanize_bytes(10 * 1024 * 1024 * 1024),
                "defaultStartModel": {
                    "slot": models[0].slot,
                    "name": models[0].name,
                    "modelId": models[0].model_id,
                },
                "models": [
                    {"slot": m.slot, "name": m.name, "modelId": m.model_id}
                    for m in models
                ],
            },
        })

    # Public product shelf — not user data. The phone merges this onto the
    # bundled catalog so a new SKU can appear without an App Store release.
    if method == "GET" and path == "/devices/catalog":
        return devices.handle_get_devices_catalog()

    # --- AI router (authenticated; no cross-user data in request) ---
    if method == "POST" and path == "/ai/router":
        try:
            # Require auth so the multi-model path cannot be used anonymously for cost abuse.
            extract_user_id(event, required=True)
            # Gate Bedrock the same way /ai/chat is gated: with the flag off, this
            # route never constructs the router or reaches Amazon Bedrock. The
            # gateway enforces the same rule as defense-in-depth.
            if not bedrock_enabled():
                raise RouteError(
                    503,
                    "Live AI routing is disabled. Set ARIA_BEDROCK_ENABLED to enable Amazon Bedrock.",
                    code="bedrock_disabled",
                )
            payload = _parse_json_body(event)
            request = RouteRequest.from_payload(payload)
            router = AIRouter()
            return ok(router.route(request))
        except RouteError as exc:
            return error_response(exc)
        except RoutingError as exc:
            return error_response(RouteError(exc.status_code, exc.args[0]))

    # --- Authenticated surface (identity from JWT / authorizer only) ---
    try:
        user_id = extract_user_id(event)
        body = _parse_json_body(event) if method in ("POST", "PUT", "PATCH") else {}

        # AI routes: always bind to authenticated principal (ignore spoofed body user_id)
        if method == "POST" and path == "/ai/archetype":
            return aria.handle_post_ai_archetype(body, user_id=user_id)

        if method == "POST" and path == "/ai/chat":
            return aria.handle_post_ai_chat(body, user_id=user_id)

        if method == "POST" and path == "/ai/weekly-review":
            return aria.handle_post_ai_weekly_review(body, user_id=user_id)

        if method == "POST" and path == "/ai/observe":
            return biometrics.handle_post_observe(body, user_id=user_id)

        if method == "POST" and path == "/ai/feedback/reaction":
            return aria.handle_post_feedback_reaction(body, user_id=user_id)

        if method == "POST" and path == "/ai/feedback/plan-outcome":
            return aria.handle_post_feedback_plan_outcome(body, user_id=user_id)

        if method == "GET" and path == "/me":
            return profile.handle_get_me(user_id)

        if method == "PUT" and path == "/me/profile":
            return profile.handle_put_profile(user_id, body)

        if method == "GET" and path == "/dashboard/today":
            return dashboard.handle_get_dashboard_today(user_id)

        if method == "GET" and path == "/sleep":
            days = _query_int(event, "days", 14, maximum=90)
            return sleep.handle_get_sleep(user_id, days)

        if method == "POST" and path == "/sleep/sessions":
            return sleep.handle_post_sleep_sessions(user_id, body)

        if method == "POST" and path == "/sleep/environment-check":
            return sleep.handle_post_sleep_environment_check(body, user_id=user_id)

        if method == "GET" and path == "/workouts/today":
            return workouts.handle_get_workouts_today(user_id)

        if method == "GET" and path == "/workouts/history":
            days = _query_int(event, "days", 30, maximum=365)
            return workouts.handle_get_workouts_history(user_id, days)

        if method == "POST" and path == "/workouts/logs":
            return workouts.handle_post_workout_log(user_id, body)

        if method == "POST" and path == "/workouts/form-check":
            return form_check.handle_post_form_check(body, user_id=user_id)

        if method == "GET" and path == "/progress/summary":
            days = _query_int(event, "days", 30, maximum=365)
            return progress.handle_get_progress_summary(user_id, days)

        if method == "GET" and path == "/chat/threads/current":
            return chat.handle_get_chat_thread(user_id)

        if method == "POST" and path == "/chat/threads/current/messages":
            return chat.handle_post_chat_message(user_id, body)

        if method == "POST" and path == "/health/batch":
            return health.handle_post_health_batch(user_id, body)

        if method == "POST" and path == "/coach/messages":
            return coach.handle_post_coach_message(user_id, body)

        if method == "POST" and path == "/coach/workout-plan":
            return coach.handle_post_coach_workout_plan(user_id, body)

        if method == "POST" and path == "/coach/sleep-insight":
            return coach.handle_post_coach_sleep_insight(user_id, body)

        if method == "POST" and path == "/coach/progress-review":
            return coach.handle_post_coach_progress_review(user_id, body)

        if method == "POST" and path == "/watch/aria/suggest":
            return watch.handle_post_watch_aria_suggest(body, user_id)

        if method == "POST" and path == "/devices/catalog/seen":
            return devices.handle_post_devices_seen(body)

        if method == "POST" and path.startswith("/integrations/") and path.endswith("/sync"):
            provider = path[len("/integrations/"):-len("/sync")]
            if provider and "/" not in provider:
                return integrations.handle_post_integration_sync(user_id, provider, body)

    except RouteError as exc:
        return error_response(exc)
    except PermissionError as exc:
        return error_response(RouteError(403, str(exc) or "Forbidden."))

    return not_found(method, path)


def _describe(event: dict) -> tuple[str, str]:
    """Method and path for a log line, from an event that may be anything.

    Deliberately total. This runs on the error path, and an exception raised
    while describing an error would replace a useful 500 with an opaque one.
    """
    try:
        http = (event or {}).get("requestContext", {}).get("http", {})
        return str(http.get("method", "?"))[:16], str(http.get("path", "?"))[:256]
    except Exception:  # noqa: BLE001 - the log line is not worth a second failure
        return "?", "?"


def handler(event, context=None):
    """Public entry point. Nothing escapes this function.

    An unhandled exception here is not merely a stack trace in a log: API
    Gateway turns it into a bare 502 with no body a client can act on, and the
    traceback — which quotes request content — lands in CloudWatch. Before this
    boundary existed, a request body of ``[]`` was enough to reach that path,
    because every route calls ``body.get(...)`` and ``json.loads`` will happily
    return a list.

    Unexpected failures get a stable JSON shape and a correlation id. The
    exception text itself is logged, never returned; it can carry user data or
    infrastructure detail and neither belongs in a client response.
    """
    request_id = getattr(context, "aws_request_id", None) or uuid.uuid4().hex
    try:
        return _route(event, context)
    except RouteError as exc:
        return error_response(exc)
    except PermissionError as exc:
        return error_response(RouteError(403, str(exc) or "Forbidden."))
    except Exception:  # noqa: BLE001 - this is the boundary; it catches everything
        method, path = _describe(event)
        LOGGER.exception(
            "Unhandled error serving %s %s (request %s)", method, path, request_id
        )
        return error_response(
            RouteError(
                500,
                "Something went wrong on our side.",
                code="internal_error",
            )
        )
