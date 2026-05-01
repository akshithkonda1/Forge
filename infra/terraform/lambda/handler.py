import json
import os
from base64 import b64decode
from datetime import datetime, timezone

from ai_router import AIRouter, RouteRequest, RoutingError, default_models, humanize_bytes


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
        },
        "body": json.dumps(body),
    }


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
        raise RoutingError(400, "Request body must be valid JSON.") from exc


def handler(event, _context):
    request_context = event.get("requestContext", {})
    http_context = request_context.get("http", {})
    method = http_context.get("method", "GET")
    path = http_context.get("path", "/")

    if method == "GET" and path == "/health":
        return _response(
            200,
            {
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
                    "models": [
                        {
                            "slot": model.slot,
                            "name": model.name,
                            "modelId": model.model_id,
                        }
                        for model in default_models()
                    ],
                },
            },
        )

    if method == "POST" and path == "/ai/router":
        try:
            payload = _parse_json_body(event)
            request = RouteRequest.from_payload(payload)
            router = AIRouter()
            return _response(200, router.route(request))
        except RoutingError as exc:
            return _response(exc.status_code, exc.to_response())

    return _response(
        501,
        {
            "message": "Forge backend infrastructure is provisioned, but this route is not implemented yet.",
            "method": method,
            "path": path,
        },
    )
