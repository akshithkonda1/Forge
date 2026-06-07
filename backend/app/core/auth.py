from __future__ import annotations

import base64
import json
import os
from typing import Any

from core.responses import RouteError
from core.runtime import allow_seed_fallback


_TEST_USER_ID = "test-user-00000000"


def _decode_jwt_payload(token: str) -> dict[str, Any]:
    parts = token.split(".")
    if len(parts) != 3:
        return {}
    padding = 4 - len(parts[1]) % 4
    padded = parts[1] + "=" * padding
    try:
        return json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))
    except Exception:
        return {}


def _claims_from_event(event: dict) -> dict[str, Any]:
    auth_header = (event.get("headers") or {}).get("authorization", "")
    if auth_header.lower().startswith("bearer "):
        token = auth_header[7:]
        claims = _decode_jwt_payload(token)
        if claims.get("sub"):
            return claims

    return (
        event.get("requestContext", {})
        .get("authorizer", {})
        .get("jwt", {})
        .get("claims", {})
        or {}
    )


def extract_user_id(event: dict) -> str:
    """Return the Cognito sub from the JWT or fail closed in production."""
    test_id = os.getenv("FORGE_TEST_USER_ID")
    if test_id:
        return test_id

    claims = _claims_from_event(event)
    sub = claims.get("sub")
    if sub:
        return str(sub)

    if allow_seed_fallback():
        return _TEST_USER_ID

    raise RouteError(401, "Authentication required.", code="unauthorized")