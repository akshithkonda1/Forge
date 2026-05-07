from __future__ import annotations

from typing import Any

from responses import RouteError, ok
from seed_data import default_connections, default_profile
from storage import dynamodb, keys


def _load_profile(user_id: str) -> dict[str, Any]:
    item = dynamodb.get_item(**keys.profile_key(user_id))
    if item:
        return {k: v for k, v in item.items() if k not in ("pk", "sk")}
    return default_profile()


def _load_connections(user_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix(keys.user_pk(user_id), "CONNECTION#")
    if items:
        return [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in items]
    return default_connections()


def handle_get_me(user_id: str) -> dict:
    return ok({"profile": _load_profile(user_id), "connections": _load_connections(user_id)})


def handle_put_profile(user_id: str, body: dict) -> dict:
    patch = body.get("profile")
    if not isinstance(patch, dict):
        raise RouteError(400, "Request body must include a 'profile' object.")

    profile = _load_profile(user_id)
    profile.update(patch)

    item = {**keys.profile_key(user_id), **profile}
    dynamodb.put_item(item)

    return ok({"profile": profile, "connections": _load_connections(user_id)})
