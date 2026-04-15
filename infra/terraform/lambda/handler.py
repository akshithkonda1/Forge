import json
import os
from datetime import datetime, timezone


def _response(status_code: int, body: dict) -> dict:
    return {
        "statusCode": status_code,
        "headers": {
            "content-type": "application/json",
        },
        "body": json.dumps(body),
    }


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
            },
        )

    return _response(
        501,
        {
            "message": "Forge backend infrastructure is provisioned, but this route is not implemented yet.",
            "method": method,
            "path": path,
        },
    )
