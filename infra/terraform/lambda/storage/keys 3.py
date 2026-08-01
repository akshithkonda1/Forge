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


def aria_context_key(user_id: str) -> dict:
    return {"pk": f"USER#{user_id}", "sk": "ARIA#CONTEXT"}
