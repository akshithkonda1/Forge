from __future__ import annotations

import os
from typing import Any

from integrations import terra_config
from runtime import allow_seed_fallback, is_production, self_healing_enabled, uses_dynamodb


def _ai_configured() -> bool:
    return bool(os.getenv("AI_PROVIDER_SECRET_ARN"))


def collect_readiness_checks() -> dict[str, Any]:
    checks = {
        "environment": os.getenv("ENVIRONMENT", "dev"),
        "seedFallbackEnabled": allow_seed_fallback(),
        "authEnforced": is_production() and not os.getenv("FORGE_TEST_USER_ID"),
        "dataStore": "dynamodb" if uses_dynamodb() else "memory",
        "aiSecretsConfigured": _ai_configured(),
        "terraSecretsConfigured": terra_config.is_configured(),
        "selfHealingEnabled": self_healing_enabled(),
    }
    checks["productionReady"] = all(
        [
            checks["dataStore"] == "dynamodb",
            not checks["seedFallbackEnabled"],
            checks["authEnforced"],
            checks["aiSecretsConfigured"],
            checks["terraSecretsConfigured"],
        ]
    )
    return checks


def health_status(checks: dict[str, Any]) -> str:
    """Return top-level health status for API + healer probes."""
    if checks.get("dataStore") != "dynamodb":
        return "degraded"
    if is_production() and not checks.get("productionReady"):
        return "degraded"
    return "ok"


def self_healing_summary() -> dict[str, Any]:
    return {
        "enabled": self_healing_enabled(),
        "apiHealthProbe": True,
        "lambdaRedeployFromArtifact": True,
        "terraStaleConnectionRepair": terra_config.is_configured(),
        "metricNamespace": "Forge/SelfHealing",
    }