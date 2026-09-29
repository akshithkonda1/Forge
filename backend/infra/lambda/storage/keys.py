from __future__ import annotations


def profile_key(user_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": "PROFILE"}


def connection_key(user_id: str, provider: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"CONNECTION#{provider}"}


def metric_key(user_id: str, metric_type: str, started_at: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"METRIC#{metric_type}#{started_at}"}


def sleep_key(user_id: str, date: str, source: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"SLEEP#{date}#{source}"}


def workout_log_key(user_id: str, started_at: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"WORKOUT#{started_at}"}


def workout_plan_key(user_id: str, date: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"PLAN#{date}"}


def readiness_key(user_id: str, date: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"READINESS#{date}"}


def chat_message_key(user_id: str, thread_id: str, created_at: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"CHAT#{thread_id}#MSG#{created_at}"}


def user_pk(user_id: str) -> str:
    return f"USER#{user_id}"


def aria_context_key(user_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": "ARIA#CONTEXT"}


def aria_persona_key(user_id: str) -> dict:
    """Durable how-you-work model. Survives dummy-orchestrator removal."""
    return {"pk": f"USER#{user_id}", "sk": "ARIA#PERSONA"}


def aria_memory_settings_key(user_id: str) -> dict:
    """Dummy-offline Rowan contract: memory_enabled, disabled_folders,
    persona_enabled, tone, check_in. Not wired into CoachContextEngine.
    """
    return {"pk": f"USER#{user_id}", "sk": "ARIA#MEMORY_SETTINGS"}


def aria_body_snapshot_key(user_id: str) -> dict:
    """Last BodyModel projection so /ai/chat shares /ai/observe's ingested truth."""
    return {"pk": f"USER#{user_id}", "sk": "ARIA#BODY_SNAPSHOT"}


def weekly_review_key(user_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": "ARIA#WEEKLY_REVIEW"}


SHORT_TERM_MEMORY_PREFIX = "ARIA#STM#"


def aria_short_term_key(user_id: str, mem_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"{SHORT_TERM_MEMORY_PREFIX}{mem_id}"}


def aria_short_term_prefix() -> str:
    return SHORT_TERM_MEMORY_PREFIX


EMERGENCY_EVENT_PREFIX = "EMERGENCY#"


def emergency_event_key(user_id: str, at_iso: str) -> dict:
    """Audit record for an emergency escalation decision (vitals monitor)."""
    return {"pk": f"USER#{user_id}", "sk": f"{EMERGENCY_EVENT_PREFIX}{at_iso}"}


CATALOG_PK = "CATALOG#DEVICES"


def catalog_device_key(device_id: str) -> dict:
    return {"pk": CATALOG_PK, "sk": f"DEVICE#{device_id}"}


def catalog_device_sk_prefix() -> str:
    return "DEVICE#"


def rate_limit_key(user_id: str, bucket: str) -> dict:
    """Per-user rate-limit counter. ``bucket`` is a coarse window id (e.g. aria-chat:2026-09-14T03)."""
    return {"pk": f"USER#{user_id}", "sk": f"RATELIMIT#{bucket}"}
