from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from core.responses import RouteError, ok
from routes._connections import public_connection
from data.seed_data import default_connections, default_profile
from core.seed_policy import empty_profile, resolve
from storage import dynamodb, keys


def _load_profile(user_id: str) -> dict[str, Any]:
    item = dynamodb.get_item(**keys.profile_key(user_id))
    if item:
        return {k: v for k, v in item.items() if k not in ("pk", "sk")}
    return resolve(None, default_profile, empty_profile)


def _load_connections(user_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix(keys.user_pk(user_id), "CONNECTION#")
    if items:
        return [public_connection(i) for i in items]
    return resolve(None, default_connections, list)


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


def handle_delete_account(user_id: str) -> dict:
    removed = dynamodb.delete_partition(keys.user_pk(user_id))
    return ok({
        "deleted": True,
        "userId": user_id,
        "itemsRemoved": removed,
        "deletedAt": datetime.now(timezone.utc).isoformat(),
    })