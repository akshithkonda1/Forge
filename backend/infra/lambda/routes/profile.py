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

    # Field-level UpdateItem, not a read-modify-write PutItem: two concurrent
    # PUTs patching different fields used to both read the same pre-update
    # snapshot, so whichever wrote second silently discarded the first's
    # change even though the first request had already returned 200 with it
    # applied. SET-ing only the patched fields makes each field's write
    # independent -- no lost-update window. See storage.dynamodb.update_item.
    fields = dict(patch)
    if demo_data_enabled() and _stored_profile(user_id) is None:
        # First save on a fresh demo account: seed whatever this patch didn't
        # already set from the fixture, same as before, so the profile isn't
        # sparse until a later PUT happens to touch each field. Merging onto
        # the fixture unconditionally (regardless of whether anything was
        # stored) was the earlier bug here -- it persisted the demo user's
        # name and device list into every subsequent save. Gating this on
        # "nothing stored yet" keeps the one-time seed without reviving that.
        # Safe even if two first saves race: default_profile() is static, so
        # both would seed identical values for whichever fields neither
        # patch sets.
        for key, value in default_profile().items():
            fields.setdefault(key, value)

    item_key = keys.profile_key(user_id)
    profile = dynamodb.update_item(item_key["pk"], item_key["sk"], fields)
    profile = {k: v for k, v in profile.items() if k not in ("pk", "sk")}

    return ok({"profile": profile, "connections": _load_connections(user_id)})
