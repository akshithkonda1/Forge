from __future__ import annotations

from typing import Any

from empty_state import empty_profile
from responses import RouteError, ok
from security import demo_data_enabled
from seed_data import default_connections, default_profile
from storage import dynamodb, keys


def _stored_profile(user_id: str) -> dict[str, Any] | None:
    """What this account actually saved -- no fixture, no shell."""
    item = dynamodb.get_item(**keys.profile_key(user_id))
    if item:
        return {k: v for k, v in item.items() if k not in ("pk", "sk")}
    return None


def _load_profile(user_id: str) -> dict[str, Any]:
    stored = _stored_profile(user_id)
    if stored is not None:
        return stored
    return default_profile() if demo_data_enabled() else empty_profile()


def _load_connections(user_id: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix(keys.user_pk(user_id), "CONNECTION#")
    if items:
        return [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in items]
    return default_connections() if demo_data_enabled() else []


def handle_get_me(user_id: str) -> dict:
    return ok({"profile": _load_profile(user_id), "connections": _load_connections(user_id)})


def handle_put_profile(user_id: str, body: dict) -> dict:
    patch = body.get("profile")
    if not isinstance(patch, dict):
        raise RouteError(400, "Request body must include a 'profile' object.")

    # Merge onto what was stored, never onto a display fallback. Merging onto
    # the fixture made the first save of a brand new account persist the demo
    # user's name and device list into that account for good -- a read-path
    # placeholder becoming real, permanent data the user never entered.
    base = _stored_profile(user_id)
    if base is None:
        base = default_profile() if demo_data_enabled() else {}

    profile = {**base, **patch}

    item = {**keys.profile_key(user_id), **profile}
    dynamodb.put_item(item)

    return ok({"profile": profile, "connections": _load_connections(user_id)})
