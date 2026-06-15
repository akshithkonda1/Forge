import json
import os
from base64 import b64decode
from datetime import datetime, timezone

from ai_router import AIRouter, RouteRequest, RoutingError, default_models, humanize_bytes
from auth import extract_user_id
from responses import RouteError, error_response, not_found, ok
from routes import aria, chat, coach, dashboard, health, integrations, profile, progress, sleep, workouts


def _parse_json_body(event: dict) -> dict:
    body = event.get("body")
    if not body:
        return {}

    if event.get("isBase64Encoded"):
        body = b64decode(body).decode("utf-8")

    if isinstance(body, dict):
        return body

    try:
        return json.loads(body)
    except json.JSONDecodeError as exc:
        raise RouteError(400, "Request body must be valid JSON.") from exc


def _query_int(event: dict, name: str, default: int, *, minimum: int = 1, maximum: int = 365) -> int:
    params = event.get("queryStringParameters") or {}
    try:
        value = int(params.get(name, default))
    except (TypeError, ValueError):
        return default
    return max(minimum, min(maximum, value))


def handler(event, _context):
    request_context = event.get("requestContext", {})
    http_context = request_context.get("http", {})
    method = http_context.get("method", "GET")
    path = http_context.get("path", "/")
    if path != "/":
        path = path.rstrip("/")

    # --- Health check (no auth required) ---
    if method == "GET" and path == "/health":
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

    # --- AI router (no user-scoped data required) ---
    if method == "POST" and path == "/ai/router":
        try:
            payload = _parse_json_body(event)
            request = RouteRequest.from_payload(payload)
            router = AIRouter()
            return ok(router.route(request))
        except RoutingError as exc:
            return error_response(RouteError(exc.status_code, exc.args[0]))

    # --- ARIA contextual intelligence (body carries user_id for local + mobile clients) ---
    if method == "POST" and path == "/ai/chat":
        try:
            return aria.handle_post_ai_chat(_parse_json_body(event))
        except RouteError as exc:
            return error_response(exc)

    if method == "POST" and path == "/ai/feedback/reaction":
        try:
            return aria.handle_post_feedback_reaction(_parse_json_body(event))
        except RouteError as exc:
            return error_response(exc)

    if method == "POST" and path == "/ai/feedback/plan-outcome":
        try:
            return aria.handle_post_feedback_plan_outcome(_parse_json_body(event))
        except RouteError as exc:
            return error_response(exc)

    # --- All routes below require user identity ---
    try:
        user_id = extract_user_id(event)
        body = _parse_json_body(event) if method in ("POST", "PUT", "PATCH") else {}

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

        if method == "GET" and path == "/workouts/today":
            return workouts.handle_get_workouts_today(user_id)

        if method == "GET" and path == "/workouts/history":
            days = _query_int(event, "days", 30, maximum=365)
            return workouts.handle_get_workouts_history(user_id, days)

        if method == "POST" and path == "/workouts/logs":
            return workouts.handle_post_workout_log(user_id, body)

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

        if method == "POST" and path.startswith("/integrations/") and path.endswith("/sync"):
            provider = path[len("/integrations/"):-len("/sync")]
            if provider and "/" not in provider:
                return integrations.handle_post_integration_sync(user_id, provider, body)

    except RouteError as exc:
        return error_response(exc)

    return not_found(method, path)
