from __future__ import annotations

from core.responses import RouteError, ok
from services import push_dispatch


def handle_post_device_push(user_id: str, body: dict) -> dict:
    token = body.get("token")
    if not isinstance(token, str) or not token.strip():
        raise RouteError(400, "Request body must include a non-empty 'token'.")

    platform = str(body.get("platform") or "ios")
    bundle_id = body.get("bundleId")
    if bundle_id is not None and not isinstance(bundle_id, str):
        raise RouteError(400, "'bundleId' must be a string when provided.")

    try:
        result = push_dispatch.register_device(
            user_id,
            token=token,
            platform=platform,
            bundle_id=bundle_id,
        )
    except ValueError as exc:
        raise RouteError(400, str(exc)) from exc

    return ok(result)


def handle_delete_device_push(user_id: str, body: dict) -> dict:
    token = body.get("token")
    if token is not None and (not isinstance(token, str) or not token.strip()):
        raise RouteError(400, "'token' must be a non-empty string when provided.")

    result = push_dispatch.unregister_device(user_id, token=token)
    return ok(result)


def handle_get_device_push(user_id: str) -> dict:
    return ok({"devices": push_dispatch.list_devices(user_id)})