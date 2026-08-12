from __future__ import annotations

import base64
import json
import os
from typing import Any

from responses import RouteError
from security import allow_test_identity, is_production_like, validate_user_id


_TEST_USER_ID = "test-user-00000000"


def _decode_jwt_payload_unverified(token: str) -> dict[str, Any]:
    """Decode JWT payload without verifying the signature.

    WARNING: Only for non-production local tooling. Production must rely on
    API Gateway JWT authorizer claims in requestContext (already verified).
    """
    parts = token.split(".")
    if len(parts) != 3:
        return {}
    padding = 4 - len(parts[1]) % 4
    padded = parts[1] + "=" * padding
    try:
        return json.loads(base64.urlsafe_b64decode(padded).decode("utf-8"))
    except Exception:
        return {}


def _authorizer_claims(event: dict) -> dict[str, Any]:
    """Cognito JWT authorizer places verified claims here (API Gateway HTTP API)."""
    auth = event.get("requestContext", {}).get("authorizer") or {}
    # HTTP API JWT authorizer shape
    jwt = auth.get("jwt") or {}
    claims = jwt.get("claims") or {}
    if claims:
        return claims
    # REST API / Lambda authorizer style
    if isinstance(auth.get("claims"), dict):
        return auth["claims"]
    return {}


def extract_user_id(event: dict, *, required: bool = True) -> str:
    """Return the authenticated Cognito ``sub`` (or raise).

    Order of trust:
    1. API Gateway JWT authorizer claims (signature already verified)
    2. Explicit FORGE_TEST_USER_ID only when non-production
    3. Unverified Authorization header decode only when non-production (local dev)
    4. Hard fail in production — never fall back to a shared test user
    """
    claims = _authorizer_claims(event)
    sub = claims.get("sub") or claims.get("username")
    if sub:
        try:
            return validate_user_id(str(sub))
        except ValueError as exc:
            raise RouteError(401, "Invalid authenticated subject.") from exc

    # Non-production test override (CI / local only)
    if allow_test_identity():
        test_id = os.getenv("FORGE_TEST_USER_ID")
        if test_id:
            try:
                return validate_user_id(test_id)
            except ValueError as exc:
                raise RouteError(401, "Invalid FORGE_TEST_USER_ID.") from exc

        # Local header decode — never in production-like environments
        if not is_production_like():
            headers = event.get("headers") or {}
            # API Gateway lowercases headers in HTTP API
            auth_header = headers.get("authorization") or headers.get("Authorization") or ""
            if auth_header.lower().startswith("bearer "):
                token = auth_header[7:].strip()
                payload = _decode_jwt_payload_unverified(token)
                sub = payload.get("sub")
                if sub:
                    try:
                        return validate_user_id(str(sub))
                    except ValueError:
                        pass

            # Last-resort local default for hermetic unit tests
            if os.getenv("FORGE_ALLOW_ANON_TEST_USER", "").strip().lower() in {
                "1",
                "true",
                "yes",
            }:
                return _TEST_USER_ID

    if required:
        raise RouteError(401, "Authentication required.")
    return ""
