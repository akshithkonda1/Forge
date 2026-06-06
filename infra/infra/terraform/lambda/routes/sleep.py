from __future__ import annotations

from typing import Any

from responses import ok
from seed_data import default_sleep
from storage import dynamodb, keys


def _load_sleep(user_id: str, days: int) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=days)
    if items:
        return [{k: v for k, v in i.items() if k not in ("pk", "sk")} for i in items]
    return default_sleep()[:days]


def handle_get_sleep(user_id: str, days: int) -> dict:
    return ok({"sleep": _load_sleep(user_id, days)})


def handle_post_sleep_sessions(user_id: str, body: dict) -> dict:
    session = body.get("session")
    if not isinstance(session, dict):
        from responses import RouteError
        raise RouteError(400, "Request body must include a 'session' object.")

    date = session.get("date", "")
    source = session.get("source", "manual")
    if not date:
        from responses import RouteError
        raise RouteError(400, "'session.date' is required.")

    item = {**keys.sleep_key(user_id, date, source), **session}
    dynamodb.put_item(item)
    return ok({"session": session})
