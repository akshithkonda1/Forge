from __future__ import annotations

import os

from core.responses import RouteError


def require_ops_token(event: dict) -> None:
    expected = os.getenv("OPS_SELF_HEAL_TOKEN")
    if not expected:
        raise RouteError(503, "Ops self-heal token is not configured on this environment.")

    headers = {k.lower(): v for k, v in (event.get("headers") or {}).items()}
    provided = headers.get("x-forge-ops-token") or headers.get("authorization", "").removeprefix("Bearer ").strip()
    if not provided or provided != expected:
        raise RouteError(401, "Invalid ops token.", code="unauthorized")