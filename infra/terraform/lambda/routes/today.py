from __future__ import annotations

from responses import RouteError, ok
from services import adaptive_week, anomalies, briefs, daily_decision, household, ledger, source_map
from services import cycle_partner


def handle_get_decision(user_id: str) -> dict:
    ledger.refresh_after_ingest(user_id)
    adaptive_week.maybe_rewrite(user_id)
    return ok(daily_decision.ensure_today(user_id))


def handle_get_brief(user_id: str, slot: str) -> dict:
    if slot == "evening":
        return ok(briefs.evening(user_id))
    return ok(briefs.morning(user_id))


def handle_post_evening_brief(user_id: str, body: dict) -> dict:
    return ok(briefs.answer_evening(user_id, str(body.get("answer") or body.get("text") or "")))


def handle_get_notifications(user_id: str) -> dict:
    return ok(briefs.notifications_due(user_id))


def handle_get_sources(user_id: str) -> dict:
    profile = ledger.load_profile(user_id)
    return ok(source_map.snapshot(user_id, ledger.connected_device_ids(profile)))


def handle_get_anomalies(user_id: str) -> dict:
    return ok({"coach": "ARIA", "anomalies": anomalies.detect(user_id)})


def handle_get_week(user_id: str) -> dict:
    return ok(adaptive_week.maybe_rewrite(user_id))


def handle_post_week_rewrite(user_id: str) -> dict:
    return ok(adaptive_week.build(user_id, reason="manual"))


def handle_get_household(user_id: str) -> dict:
    return ok(household.load(user_id))


def handle_put_household(user_id: str, body: dict) -> dict:
    members = body.get("members")
    if not isinstance(members, list):
        raise RouteError(400, "Request body must include a 'members' array.")
    return ok(household.replace(user_id, members))


def handle_post_partner_mindset(user_id: str, body: dict) -> dict:
    # Redacted fields only. Nothing is persisted.
    if not isinstance(body, dict):
        raise RouteError(400, "Request body must be an object.")
    return ok(cycle_partner.mindset(body))
