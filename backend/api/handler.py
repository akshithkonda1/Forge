import json
import os
from base64 import b64decode
from datetime import datetime, timezone

from ai_router import AIRouter, RouteRequest, RoutingError, default_models, humanize_bytes
from aria_agent import ARIA_ANALYSIS_MODEL, ARIA_CHAT_MODEL
from auth import extract_user_id
from integrations import terra_config
from integrations.terra_self_integration import get_integration_state
from ops_auth import require_ops_token
from responses import RouteError, error_response, not_found, ok
from routes import aria, chat, coach, dashboard, health, integrations, profile, progress, sleep, terra, workouts


def _raw_body(event: dict) -> str:
    body = event.get("body")
    if not body:
        return ""

    if event.get("isBase64Encoded"):
        return b64decode(body).decode("utf-8")

    if isinstance(body, dict):
        return json.dumps(body)
    return str(body)


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


def _terra_health_summary() -> dict:
    state = get_integration_state()
    return {
        "configured": terra_config.is_configured(),
        "webhookConfigured": terra_config.is_webhook_configured(),
        "webhookPath": "/integrations/terra/webhook",
        "status": state.get("status", "unknown"),
        "apiReachable": state.get("apiReachable", False),
        "selfIntegration": {
            "lastBootstrapAt": state.get("lastBootstrapAt"),
            "webhookUrl": state.get("webhookUrl"),
        },
        "selfHealing": {
            "enabled": True,
            "path": "/integrations/terra/self-heal",
        },
    }


def _query_int(event: dict, name: str, default: int, *, minimum: int = 1, maximum: int = 365) -> int:
    params = event.get("queryStringParameters") or {}
    try:
        value = int(params.get(name, default))
    except (TypeError, ValueError):
        return default
    return max(minimum, min(maximum, value))


def handler(event, _context):
    if event.get("forgeAction") == "terra-self-heal":
        return terra.handle_scheduled_self_heal()

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
            "aria": {
                "backend": os.getenv("ARIA_BACKEND", "bedrock"),
                "status": "configured",
                "chatModel": ARIA_CHAT_MODEL,
                "analysisModel": ARIA_ANALYSIS_MODEL,
                "backupModel": os.getenv("ARIA_BACKUP_MODEL", ARIA_ANALYSIS_MODEL),
                "features": [
                    "tool-use",
                    "extended-thinking",
                    "prompt-caching",
                    "conversation-memory",
                    "proactive-insights",
                    "voice-processing",
                    "backup-model",
                ],
            },
            "integrations": {
                "terra": _terra_health_summary(),
            },
        })

    if method == "GET" and path == "/integrations/terra/health":
        return terra.handle_get_integration_health()

    if method == "POST" and path == "/integrations/terra/self-integrate":
        try:
            require_ops_token(event)
            return terra.handle_post_self_integrate()
        except RouteError as exc:
            return error_response(exc)

    if method == "POST" and path == "/integrations/terra/self-heal":
        try:
            require_ops_token(event)
            return terra.handle_post_self_heal()
        except RouteError as exc:
            return error_response(exc)

    # --- Terra webhook (signature verified, no JWT) ---
    if method == "POST" and path == "/integrations/terra/webhook":
        try:
            return terra.handle_post_webhook(_raw_body(event), event.get("headers") or {})
        except RouteError as exc:
            return error_response(exc)

    # --- AI router (no user-scoped data required) ---
    if method == "POST" and path == "/ai/router":
        try:
            payload = _parse_json_body(event)
            request = RouteRequest.from_payload(payload)
            router = AIRouter()
            return ok(router.route(request))
        except RoutingError as exc:
            return error_response(RouteError(exc.status_code, exc.args[0]))

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

        if method == "POST" and path == "/integrations/terra/widget":
            return terra.handle_post_widget(user_id, body)

        if method == "GET" and path == "/integrations/terra/status":
            return terra.handle_get_status(user_id)

        # --- ARIA routes ---
        if method == "POST" and path == "/aria/chat":
            return aria.handle_post_aria_chat(user_id, body)

        if method == "POST" and path == "/aria/analyze":
            return aria.handle_post_aria_analyze(user_id, body)

        if method == "POST" and path == "/aria/plan":
            return aria.handle_post_aria_plan(user_id, body)

        if method == "POST" and path == "/aria/voice":
            return aria.handle_post_aria_voice(user_id, body)

        if method == "POST" and path == "/aria/insights/generate":
            return aria.handle_post_aria_insights_generate(user_id, body)

        if method == "GET" and path == "/aria/insights":
            days = _query_int(event, "days", 7, minimum=1, maximum=30)
            return aria.handle_get_aria_insights(user_id, days)

        if method == "GET" and path == "/aria/conversation":
            thread_id = (event.get("queryStringParameters") or {}).get("threadId", "current")
            return aria.handle_get_aria_conversation(user_id, thread_id)

        if method == "DELETE" and path == "/aria/conversation":
            thread_id = (event.get("queryStringParameters") or {}).get("threadId", "current")
            return aria.handle_delete_aria_conversation(user_id, thread_id)

    except RouteError as exc:
        return error_response(exc)

    return not_found(method, path)
