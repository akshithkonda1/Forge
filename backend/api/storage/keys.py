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


def chat_thread_key(user_id: str, thread_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"CHAT#{thread_id}"}


def chat_message_key(user_id: str, thread_id: str, created_at: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"CHAT#{thread_id}#MSG#{created_at}"}


def user_pk(user_id: str) -> str:
    return f"USER#{user_id}"


# ARIA-specific keys
def aria_conversation_key(user_id: str, thread_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"ARIA#{thread_id}#CONV"}


def aria_insight_key(user_id: str, date: str, insight_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": f"ARIA#INSIGHT#{date}#{insight_id}"}


def aria_summary_key(user_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": "ARIA#SUMMARY"}


def terra_user_key(terra_user_id: str) -> dict:
    return {"pk": f"TERRA#USER#{terra_user_id}", "sk": "MAPPING"}


def terra_ref_key(user_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": "TERRA#REF"}


def terra_system_key() -> dict:
    return {"pk": "SYSTEM#TERRA", "sk": "INTEGRATION"}


def terra_heal_run_key(run_at: str) -> dict:
    return {"pk": "SYSTEM#TERRA", "sk": f"HEAL#{run_at}"}


def terra_user_heal_key(user_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": "TERRA#HEAL"}
