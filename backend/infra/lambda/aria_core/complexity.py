"""Deterministic complexity classifier for the three-model escalation ladder.

Tiers (compute × task complexity):

1. Sonnet — default. Short replies, intent, insights, simple recommendations.
2. Grok 4.7 — more complex than Sonnet should handle alone (multi-domain,
   tradeoffs, moderate planning).
3. Opus — complex reasoning and planning (multi-week programming, many
   constraints).
4. Ensemble — all three draft independently, then a synthesis step. Only the
   most complex requests.

Classification is cheap and local: keyword/structure signals plus optional
context conflict. Injection and medical-safety turns are held at Tier 1 so
they cannot spend their way up the ladder. Sonnet may self-assess one step
up; the classifier never spends a model call to rank itself.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any, Iterable, Mapping

from .untrusted import looks_like_injection

TIER_SONNET = 1
TIER_GROK = 2
TIER_OPUS = 3
TIER_ENSEMBLE = 4
TIER_NAMES = {
    TIER_SONNET: "sonnet",
    TIER_GROK: "grok",
    TIER_OPUS: "opus",
    TIER_ENSEMBLE: "ensemble",
}

# Self-assessed confidence at or below this may justify one-step escalation.
SELF_ESCALATE_CONFIDENCE = 0.45
MAX_SELF_ESCALATE_STEPS = 1

# Score bands. Tuned so short insights stay Tier 1 and T4 requires plan+tradeoff.
GROK_SCORE = 3
OPUS_SCORE = 8
ENSEMBLE_SCORE = 10

# Owner mix: most traffic stays on Sonnet. Used by COST.md arithmetic.
EXPECTED_TRAFFIC_MIX = {
    TIER_SONNET: 0.88,
    TIER_GROK: 0.08,
    TIER_OPUS: 0.035,
    TIER_ENSEMBLE: 0.005,
}

_PLAN_HINTS = (
    "training plan",
    "week plan",
    "weekly plan",
    "4-week",
    "8-week",
    "plan my week",
    "plan the next",
    "programming",
    "periodiz",
    "block plan",
    "map the week",
    "schedule my week",
    "multi-day",
    "plan a block",
)
_TRADEOFF_HINTS = (
    "tradeoff",
    "trade-off",
    "from every angle",
    "reconcile",
    "conflicting",
    "weigh",
    "optimize",
    "periodized",
    "every angle",
    "all things considered",
)
_MULTI_DOMAIN_HINTS = (
    ("sleep", "train"),
    ("sleep", "work"),
    ("travel", "train"),
    ("protein", "sleep"),
    ("hrv", "load"),
    ("readiness", "plan"),
)
_COMPLEX_QUESTION = (
    "why is",
    "how do i fit",
    "how should i fit",
    "how should i balance",
    "what's the trade",
    "around travel",
)
_SAFETY_HOLD = (
    "diagnos",
    "prescribe",
    "what drug",
    "dosage",
    "chest pain",
    "call 911",
    "emergency",
)


@dataclass(frozen=True)
class ComplexityDecision:
    """Audit-friendly classifier result. ``reasons`` are codes, never user text."""

    tier: int
    score: int
    reasons: tuple[str, ...]
    allow_self_escalate: bool

    @property
    def name(self) -> str:
        return TIER_NAMES.get(self.tier, "sonnet")


def _lower(text: str) -> str:
    return " ".join(str(text or "").lower().split())


def _context_conflicts(context: Mapping[str, Any] | None) -> bool:
    if not isinstance(context, Mapping):
        return False
    readiness = context.get("readiness") if isinstance(context.get("readiness"), dict) else {}
    sleep = context.get("sleep") if isinstance(context.get("sleep"), dict) else {}
    training = context.get("training") if isinstance(context.get("training"), dict) else {}
    try:
        recovery = float(readiness.get("recoveryScore") or readiness.get("recovery_score") or 100)
    except (TypeError, ValueError):
        recovery = 100.0
    try:
        duration = float(sleep.get("durationMinutes") or sleep.get("duration_minutes") or 480)
    except (TypeError, ValueError):
        duration = 480.0
    overreached = bool(training.get("isOvertrained") or training.get("is_overtrained"))
    return overreached or recovery < 45 or duration < 300


def _domain_count(blob: str) -> int:
    domains = ("sleep", "train", "workout", "protein", "travel", "work", "hrv", "readiness", "stress")
    return sum(1 for token in domains if token in blob)


def classify_complexity(
    question: str,
    *,
    response_type: str = "",
    context: Mapping[str, Any] | None = None,
    package_count: int = 0,
    voice_mode: bool = False,
    safety_lock: bool = False,
) -> ComplexityDecision:
    """Return the cheapest tier that can honestly handle this request."""
    blob = _lower(question)
    reasons: list[str] = []
    score = 0

    if voice_mode:
        return ComplexityDecision(TIER_SONNET, 0, ("voice_mode",), False)
    if safety_lock or any(token in blob for token in _SAFETY_HOLD):
        return ComplexityDecision(TIER_SONNET, 0, ("safety_hold_tier1",), False)
    if looks_like_injection(question):
        return ComplexityDecision(TIER_SONNET, 0, ("injection_hold_tier1",), False)

    length = len(blob)
    if length > 320:
        score += 2
        reasons.append("long_question")
    elif length > 140:
        score += 1
        reasons.append("medium_question")

    if any(hint in blob for hint in _PLAN_HINTS) or response_type == "plan":
        score += 4
        reasons.append("plan_intent")
        if _domain_count(blob) >= 3:
            score += 2
            reasons.append("plan_multi_constraint")
    if any(hint in blob for hint in _TRADEOFF_HINTS):
        score += 3
        reasons.append("tradeoff")
    pairs = sum(1 for a, b in _MULTI_DOMAIN_HINTS if a in blob and b in blob)
    if pairs or _domain_count(blob) >= 3:
        score += 1 + max(pairs, 1)
        reasons.append("multi_domain")
    if any(hint in blob for hint in _COMPLEX_QUESTION):
        score += 1
        reasons.append("complex_question")
    if _context_conflicts(context):
        score += 2
        reasons.append("context_conflict")
    if package_count >= 3:
        score += 1
        reasons.append("many_packages")
    if response_type in {"plan", "summary"} and score < 4:
        score += 1
        reasons.append("structured_response")

    if score >= ENSEMBLE_SCORE and "tradeoff" in reasons and "plan_intent" in reasons:
        tier = TIER_ENSEMBLE
        reasons.append("ensemble_threshold")
    elif score >= OPUS_SCORE:
        tier = TIER_OPUS
    elif score >= GROK_SCORE:
        tier = TIER_GROK
    else:
        tier = TIER_SONNET
        if not reasons:
            reasons.append("default_tier1")

    allow = tier in {TIER_SONNET, TIER_GROK} and "injection_hold_tier1" not in reasons
    return ComplexityDecision(tier, score, tuple(reasons), allow)


def next_tier(current: int) -> int:
    return min(TIER_OPUS, current + 1)


def should_self_escalate(
    decision: ComplexityDecision,
    *,
    confidence: float | None,
    needs_escalation: bool,
    already_escalated: int = 0,
) -> bool:
    """One-step bump from Sonnet/Grok self-assess. Never jumps to ensemble."""
    if not decision.allow_self_escalate:
        return False
    if already_escalated >= MAX_SELF_ESCALATE_STEPS:
        return False
    if decision.tier >= TIER_OPUS:
        return False
    if not needs_escalation:
        return False
    if confidence is None:
        return False
    try:
        value = float(confidence)
    except (TypeError, ValueError):
        return False
    return value <= SELF_ESCALATE_CONFIDENCE


def escalation_log(
    decision: ComplexityDecision,
    *,
    models: Iterable[str],
    extra: str | None = None,
) -> dict[str, Any]:
    """PII-free routing audit. No question text, no health numbers."""
    payload: dict[str, Any] = {
        "tier": decision.tier,
        "tierName": decision.name,
        "score": decision.score,
        "reasons": list(decision.reasons),
        "models": [str(item) for item in models],
    }
    if extra:
        payload["extra"] = extra
    return payload
