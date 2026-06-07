from __future__ import annotations

import os


def environment() -> str:
    return os.getenv("ENVIRONMENT", "dev").strip().lower()


def is_production() -> bool:
    return environment() in {"production", "prod"}


def allow_seed_fallback() -> bool:
    """Demo seed data is allowed only for local in-memory dev and explicit test runs."""
    override = os.getenv("FORGE_ALLOW_SEED_FALLBACK", "").strip().lower()
    if override in {"1", "true", "yes"}:
        return True
    if os.getenv("FORGE_TEST_USER_ID"):
        return True
    if uses_dynamodb() or is_production():
        return False
    return True


def uses_dynamodb() -> bool:
    return bool(os.getenv("APP_DATA_TABLE_NAME"))


def self_healing_enabled() -> bool:
    return os.getenv("FORGE_SELF_HEALING_ENABLED", "true").strip().lower() not in {
        "0",
        "false",
        "no",
    }