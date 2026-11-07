"""Health conditions stay on-device unless the user opted in.

Wearable metrics (sleep, HRV, steps) are coaching signals. Clinical
conditions, medications, and diagnoses are not — they reach a prompt only
when ``shareHealth`` is true *and* the item itself is opted in. Raw health
text must never be logged.

Stdlib-only. Wraps ``aria_context_memory.server_context`` so /ai/chat,
memory inject, and fusion share one gate.
"""

from __future__ import annotations

import re
from typing import Any

from . import aria_context_memory as acm

_HEALTH_LOG_RE = re.compile(
    r"(?i)\b(?:seizure|epilep\w*|diagnos\w*|medication|prescription|"
    r"condition|allergy|allergies|insulin|cholesterol|asthma|diabet\w*)\b"
)


def share_flags(payload: dict[str, Any] | None) -> dict[str, bool]:
    """Read opt-in flags. Missing keys are False — fail closed."""
    raw = payload if isinstance(payload, dict) else {}
    nested = raw.get("share") if isinstance(raw.get("share"), dict) else {}
    memory = raw.get("memoryShare") if isinstance(raw.get("memoryShare"), dict) else {}
    permissions = raw.get("permissions") if isinstance(raw.get("permissions"), dict) else {}
    return {
        "shareHealth": _flag(
            raw.get("shareHealth"),
            nested.get("shareHealth"),
            memory.get("shareHealth"),
            permissions.get("shareHealth"),
        ),
        "shareDreams": _flag(
            raw.get("shareDreams"),
            nested.get("shareDreams"),
            memory.get("shareDreams"),
            permissions.get("shareDreams"),
        ),
    }


def health_opted_in(payload: dict[str, Any] | None) -> bool:
    return bool(share_flags(payload)["shareHealth"])


def filter_memory_items(
    items: list[dict[str, Any]] | None,
    payload: dict[str, Any] | None = None,
) -> list[dict[str, Any]]:
    """Drop health/dream items the user has not opted to share with the server."""
    share = share_flags(payload)
    kept: list[dict[str, Any]] = []
    for item in items or []:
        if not isinstance(item, dict):
            continue
        domain = str(item.get("domain") or "") or acm.classify(
            str(item.get("text") or item.get("summary") or "")
        )
        row = dict(item)
        row["domain"] = domain
        opt = bool(row.get("shareOptIn"))
        if domain == "health_constraints" and not (share["shareHealth"] and opt):
            continue
        if domain == "sleep_dreams" and not (share["shareDreams"] and opt):
            continue
        kept.append(row)
    return kept


def server_context(
    items: list[dict[str, Any]] | None,
    payload: dict[str, Any] | None = None,
) -> dict[str, str]:
    """Prompt-safe memory summaries. Empty when nothing is shareable."""
    return acm.server_context(filter_memory_items(items, payload), share_flags(payload))


def filter_memory_text(text: str, payload: dict[str, Any] | None = None) -> str:
    """Drop health-classified lines from a rendered memory block unless opted in."""
    if health_opted_in(payload):
        return str(text or "")
    kept: list[str] = []
    for raw in str(text or "").splitlines():
        line = raw.strip()
        if not line:
            continue
        domain = acm.classify(line)
        if domain in acm.SENSITIVE:
            continue
        if _HEALTH_LOG_RE.search(line):
            continue
        kept.append(raw)
    return "\n".join(kept)


_PHYSIO_PLAN_IDS = frozenset(
    {"hrv", "recovery", "sleep", "sleep_debt_7d", "rhr", "resting_hr"}
)

# Derived body tokens that must not land on ARIA#CONTEXT / lifestyle.
HEALTH_PATTERN_TOKENS = frozenset(
    {
        "low_readiness_streak",
        "strong_sleep_recovery",
    }
)

_HEALTH_INSIGHT_RE = re.compile(
    r"(?i)(?:\bhrv\b|readiness|recovery score|sleep debt|"
    r"short on sleep|running short on sleep|last night ran short|"
    r"wearable picture|protect sleep|the body is asking|"
    r"resting hr|\brhr\b|low_readiness|strong_sleep_recovery)"
)


def plan_has_health_conclusions(plan: Any) -> bool:
    """True when a stored supervision plan was derived from body signals."""
    if not isinstance(plan, dict) or not plan:
        return False
    for factor in plan.get("factors") or []:
        if not isinstance(factor, dict):
            continue
        fid = str(factor.get("id") or "").lower()
        lane = str(factor.get("lane") or "").lower()
        if fid in _PHYSIO_PLAN_IDS or lane == "physiological":
            return True
    blob = " ".join(
        str(plan.get(key) or "")
        for key in ("aging_reason", "next_advice", "guide", "signals")
    ).lower()
    if any(token in blob for token in ("hrv", "recovery is", "last night ran short", "sleep debt")):
        return True
    return False


def insight_has_health_conclusions(text: str) -> bool:
    """True when a takeaway/headline was derived from body signals."""
    raw = str(text or "").strip()
    if not raw:
        return False
    if raw.lower() in HEALTH_PATTERN_TOKENS:
        return True
    return bool(_HEALTH_INSIGHT_RE.search(raw))


def filter_health_pattern_tokens(values: Any) -> list[str]:
    """Drop readiness/sleep-derived pattern slugs from living memory."""
    kept: list[str] = []
    for item in values or []:
        text = str(item).strip()
        if not text:
            continue
        if text.lower() in HEALTH_PATTERN_TOKENS:
            continue
        if insight_has_health_conclusions(text):
            continue
        kept.append(text)
    return kept


def ctx_has_health_signals(ctx: Any) -> bool:
    """True when this-turn context carries wearable/body numbers."""
    if ctx is None:
        return False
    sleep = getattr(ctx, "sleep", None)
    if sleep is not None:
        for field in ("duration_minutes", "hrv", "resting_hr"):
            if getattr(sleep, field, None) is not None:
                return True
    readiness = getattr(ctx, "readiness", None)
    if readiness is not None:
        for field in ("recovery_score", "hrv_7day_trend", "hrv_30day_baseline"):
            if getattr(readiness, field, None) is not None:
                return True
    activity = getattr(ctx, "activity", None)
    if activity is not None:
        for field in ("steps", "active_calories", "workout_load"):
            if getattr(activity, field, None) is not None:
                return True
    return False


def _clear_health_stance(clean: Any) -> None:
    clean.last_stance = None
    clean.last_bucket = None
    clean.last_stance_p = 0.0
    clean.last_predicted_reward = 0.0
    clean.last_specialists = ()
    clean.last_sources = ()


def strip_health_from_persona(state: Any, ctx: Any = None) -> Any:
    """Return a copy safe to write to ARIA#PERSONA.

    Conversation, calendar, and relationship stay. last_plan / aging / plan_q
    built from readiness, HRV, or sleep do not. Stance chosen from those
    signals is also dropped.
    """
    if state is None:
        return None
    from .contextual_learner import PersonaState

    clean = PersonaState.from_dict(state.as_dict() if hasattr(state, "as_dict") else None)
    health_plan = plan_has_health_conclusions(clean.last_plan)
    if health_plan:
        from .contextual_learner import _default_aging

        clean.last_plan = None
        clean.last_plan_choice = None
        clean.last_aging_pace = None
        clean.aging = _default_aging()
        clean.n_aging = 0
        clean.plan_q = {}
        _clear_health_stance(clean)
    if ctx_has_health_signals(ctx):
        _clear_health_stance(clean)
    return clean


def without_health_for_persona(ctx: Any) -> Any:
    """Copy of ``ctx`` with body/health domains emptied.

    Lifestyle tags, calendar kinds, and conversation stay. Sleep, readiness,
    vitals, clinical lists, and other derived body scores do not — those
    conclusions must not be written to the server persona.
    """
    if ctx is None:
        return None
    from dataclasses import replace

    from . import aria_engine

    if not isinstance(ctx, aria_engine.ARIAContext):
        return None
    return replace(
        ctx,
        sleep=aria_engine.SleepContext(),
        readiness=aria_engine.ReadinessContext(),
        activity=aria_engine.ActivityContext(),
        body=aria_engine.BodyContext(),
        nutrition=aria_engine.NutritionContext(),
        aging=aria_engine.AgingContext(),
        vitals=aria_engine.VitalsContext(),
        clinical_data=aria_engine.ClinicalDataContext(),
        medication_layer=aria_engine.MedicationLayerContext(),
    )


def redact_clinical_context(ctx: Any, payload: dict[str, Any] | None) -> Any:
    """Zero clinical lists on an ARIAContext unless shareHealth is on.

    Wearable domains are untouched. The original object is copied only when
    redaction is needed so callers can still compare.
    """
    if health_opted_in(payload):
        return ctx
    clinical = getattr(ctx, "clinical_data", None)
    if clinical is None:
        return ctx
    empty = not any(
        getattr(clinical, field, None)
        for field in (
            "allergies",
            "medications",
            "conditions",
            "immunizations",
            "lab_results",
            "procedures",
        )
    )
    if empty and not getattr(getattr(ctx, "medication_layer", None), "on_file", None):
        return ctx
    from . import aria_engine

    sanitized, _restricted = aria_engine.apply_permissions(
        ctx,
        aria_engine.DataPermissions.from_payload({"clinical_data": False}),
    )
    return sanitized


def redact_for_log(text: str) -> str:
    """Replace raw health tokens before a line reaches CloudWatch."""
    raw = str(text or "")
    if not raw:
        return raw
    return _HEALTH_LOG_RE.sub("[health-redacted]", raw)


def contains_raw_health(text: str) -> bool:
    return bool(_HEALTH_LOG_RE.search(text or ""))


def _flag(*values: Any) -> bool:
    for value in values:
        if isinstance(value, bool):
            return value
        if isinstance(value, str) and value.strip().lower() in {"1", "true", "yes", "on"}:
            return True
    return False
