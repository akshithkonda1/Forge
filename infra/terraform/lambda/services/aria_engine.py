"""ARIA reasoning engine — Phase 1 (HealthKit only).

This module is the coaching core behind ``POST /ai/chat``. It is a *deterministic
function*: given a HealthKit-shaped context payload it produces consistent,
data-specific, schema-conformant output. No Bedrock call happens here — during
Phase 1 the backend is simulated middleware, so context assembly and reasoning
are pure and fully testable.

The contract it implements is intentionally narrow and versioned:

  * Input  — ``ARIAContext`` (priority-ordered HealthKit signals, explicit nulls).
  * Output — the v1.0 response envelope (schema_version, response_type,
             confidence, confidence_reason, prose_summary, card).

Design rules enforced here (so they cannot silently drift):
  * Every response references at least one concrete metric when data exists.
  * Confidence is calibrated from data completeness and signal agreement —
    never a flat constant.
  * Missing data is declared, never papered over. Degradation is visible in the
    confidence score and the confidence_reason.
  * ``prose_summary`` is mandatory on every response (voice-mode fallback).
"""

from __future__ import annotations

import re
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

# --- Versioned interface -----------------------------------------------------

SCHEMA_VERSION = "1.0"

# Model routing (Section 4 of the ARIA brief). Phase 1 is deterministic so these
# are advisory, but the routing policy is encoded and tested so the live path
# inherits it unchanged.
MODEL_PRIMARY = "claude-opus-4-8"   # multi-signal reasoning, plans
MODEL_FAST = "claude-sonnet-4-6"    # single-metric lookups, voice, clarifications

# Voice orb (AuroraOrbView) hard cap. Cards are suppressed in voice mode; only
# prose_summary is spoken.
VOICE_TOKEN_CAP = 150

# Population reference ranges for sleep architecture, used when no *personal*
# baseline is available. Expressed as a fraction of total sleep time.
DEEP_SLEEP_REF_FRAC = 0.18   # below this we flag low deep sleep
REM_SLEEP_REF_FRAC = 0.20    # below this we flag low REM
EFFICIENCY_REF = 0.85        # below this we flag fragmented sleep

# Minimum nights of sleep history required to speak about a personal baseline.
MIN_SLEEP_BASELINE_NIGHTS = 3


# --- Canonical ARIA system prompt (Section 2) --------------------------------
#
# Phase 1 ``/ai/chat`` is deterministic and does not execute this prompt, but the
# brief treats the prompt as a product artifact ("ARIA is the product"). It is
# defined here as the single canonical version and unit-tested for the four
# things the brief requires it to do. ``build_user_prompt`` injects the live
# context as a structured block beneath it for the future Bedrock path.
ARIA_SYSTEM_PROMPT = f"""\
You are ARIA, the precision health coach inside Forge. You are not a wellness
chatbot. You interpret data: you explain what it means, why it matters today,
and what to do about it — ranked by confidence.

VOICE — direct, precise, warm, in that order. Do not lead with affirmations or
filler. Speak like a sports scientist who genuinely cares about the person in
front of you. Never open with "Great question", "As an AI", or "It's important
to note". Reference the user's actual numbers; if a reply could have been
written without their data, it has failed.

USER MODEL — the block below is ground truth, not user-provided claims. Treat
the chronotype, baselines, and current signals as established facts about this
person and reason over them directly.

CONFIDENCE — express uncertainty in a calibrated, non-evasive way. When
confidence is low, say why (e.g. "only 2 nights of HRV data"), still give a
best estimate, and name the one signal that would change the answer. Never
hedge into a vague non-answer to avoid being wrong.

MISSING DATA — if a signal is absent, say so and lower confidence accordingly.
Do not silently proceed as if it were present.

OUTPUT CONTRACT — respond as a single JSON object conforming to schema version
{SCHEMA_VERSION}: schema_version, response_type (insight | recommendation | plan
| summary | clarification), confidence (0.0-1.0), confidence_reason,
prose_summary (1-3 sentences, usable as a standalone spoken response), and a
matching card. prose_summary is mandatory on every response. In voice mode,
return prose only and cap at ~{VOICE_TOKEN_CAP} tokens — no card.
"""


# --- Context model (Section 1) -----------------------------------------------


def _utcnow_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


@dataclass
class SleepContext:
    duration_minutes: float | None = None
    efficiency: float | None = None       # 0-1
    rem_minutes: float | None = None
    deep_minutes: float | None = None
    hrv: float | None = None              # SDNN ms, during sleep
    resting_hr: float | None = None
    nights_available: int | None = None   # history depth (for baseline gating)


@dataclass
class ReadinessContext:
    hrv_7day_trend: float | None = None   # % vs 30-day baseline
    hrv_30day_baseline: float | None = None
    recovery_score: float | None = None   # 0-100
    hrv_days_available: int | None = None  # history depth (for confidence)


@dataclass
class TrainingContext:
    last_workout_type: str | None = None
    last_workout_duration_minutes: float | None = None
    hours_since_last_workout: float | None = None
    weekly_load_score: float | None = None  # normalized, null if < 3 sessions


@dataclass
class ActivityContext:
    steps_3day_avg: float | None = None
    active_calories_3day_avg: float | None = None


@dataclass
class ChronotypeContext:
    typical_sleep_onset: str | None = None  # "23:30"
    typical_wake_time: str | None = None    # "07:00"
    consistency_score: float | None = None  # 0-1


# Maps every leaf field to the dotted name surfaced in ``missing_fields`` so the
# prompt/UI can declare exactly what is absent.
_FIELD_MAP: dict[str, list[str]] = {
    "sleep": ["duration_minutes", "efficiency", "rem_minutes", "deep_minutes", "hrv", "resting_hr"],
    "readiness": ["hrv_7day_trend", "hrv_30day_baseline", "recovery_score"],
    "training": ["last_workout_type", "last_workout_duration_minutes", "hours_since_last_workout", "weekly_load_score"],
    "activity": ["steps_3day_avg", "active_calories_3day_avg"],
    "chronotype": ["typical_sleep_onset", "typical_wake_time", "consistency_score"],
}


@dataclass
class ARIAContext:
    timestamp: str = field(default_factory=_utcnow_iso)
    sleep: SleepContext = field(default_factory=SleepContext)
    readiness: ReadinessContext = field(default_factory=ReadinessContext)
    training: TrainingContext = field(default_factory=TrainingContext)
    activity: ActivityContext = field(default_factory=ActivityContext)
    chronotype: ChronotypeContext = field(default_factory=ChronotypeContext)

    @property
    def missing_fields(self) -> list[str]:
        groups = {
            "sleep": self.sleep,
            "readiness": self.readiness,
            "training": self.training,
            "activity": self.activity,
            "chronotype": self.chronotype,
        }
        missing: list[str] = []
        for group_name, attrs in _FIELD_MAP.items():
            obj = groups[group_name]
            for attr in attrs:
                if getattr(obj, attr) is None:
                    missing.append(f"{group_name}.{attr}")
        return missing

    @property
    def has_sleep(self) -> bool:
        return self.sleep.duration_minutes is not None

    @property
    def has_hrv(self) -> bool:
        return self.readiness.hrv_7day_trend is not None or self.sleep.hrv is not None

    @property
    def has_training_history(self) -> bool:
        return (
            self.training.weekly_load_score is not None
            or self.training.hours_since_last_workout is not None
        )

    @property
    def sleep_baseline_ready(self) -> bool:
        """True only when we have enough nights to speak of a personal baseline."""
        nights = self.sleep.nights_available
        return self.has_sleep and (nights is None or nights >= MIN_SLEEP_BASELINE_NIGHTS)

    # -- Parsing ---------------------------------------------------------------

    @classmethod
    def from_payload(cls, body: dict[str, Any]) -> "ARIAContext":
        """Build a context from a request body.

        Accepts the rich nested ``context`` object when present; otherwise
        derives a minimal context from the legacy flat ``recent_metrics`` bag
        the deployed iOS client still sends. Either way, absent signals stay
        ``None`` so ``missing_fields`` stays honest.
        """
        rich = body.get("context")
        if isinstance(rich, dict):
            return cls._from_rich(rich)
        return cls._from_legacy_metrics(_coerce_metrics(body.get("recent_metrics")))

    @classmethod
    def _from_rich(cls, data: dict[str, Any]) -> "ARIAContext":
        sleep = data.get("sleep") or {}
        readiness = data.get("readiness") or {}
        training = data.get("training") or {}
        activity = data.get("activity") or {}
        chronotype = data.get("chronotype") or {}
        return cls(
            timestamp=str(data.get("timestamp") or _utcnow_iso()),
            sleep=SleepContext(
                duration_minutes=_num(sleep.get("durationMinutes")),
                efficiency=_num(sleep.get("efficiency")),
                rem_minutes=_num(sleep.get("remMinutes")),
                deep_minutes=_num(sleep.get("deepMinutes")),
                hrv=_num(sleep.get("hrv")),
                resting_hr=_num(sleep.get("restingHR")),
                nights_available=_int(sleep.get("nightsAvailable")),
            ),
            readiness=ReadinessContext(
                hrv_7day_trend=_num(readiness.get("hrv7DayTrend")),
                hrv_30day_baseline=_num(readiness.get("hrv30DayBaseline")),
                recovery_score=_num(readiness.get("recoveryScore")),
                hrv_days_available=_int(readiness.get("hrvDaysAvailable")),
            ),
            training=TrainingContext(
                last_workout_type=_str(training.get("lastWorkoutType")),
                last_workout_duration_minutes=_num(training.get("lastWorkoutDurationMinutes")),
                hours_since_last_workout=_num(training.get("hoursSinceLastWorkout")),
                weekly_load_score=_num(training.get("weeklyLoadScore")),
            ),
            activity=ActivityContext(
                steps_3day_avg=_num(activity.get("steps3DayAvg")),
                active_calories_3day_avg=_num(activity.get("activeCalories3DayAvg")),
            ),
            chronotype=ChronotypeContext(
                typical_sleep_onset=_str(chronotype.get("typicalSleepOnset")),
                typical_wake_time=_str(chronotype.get("typicalWakeTime")),
                consistency_score=_num(chronotype.get("consistencyScore")),
            ),
        )

    @classmethod
    def _from_legacy_metrics(cls, metrics: dict[str, float]) -> "ARIAContext":
        """Bridge the flat ``recent_metrics`` bag onto the structured context.

        Only fields we can actually infer are populated; everything else stays
        ``None`` so the engine correctly reports thin data instead of inventing
        precision the legacy payload never carried.
        """
        ctx = cls()
        if "readiness" in metrics:
            ctx.readiness.recovery_score = metrics["readiness"]
        if "recovery_score" in metrics:
            ctx.readiness.recovery_score = metrics["recovery_score"]
        if "hrv" in metrics:
            ctx.sleep.hrv = metrics["hrv"]
        if "hrv_trend" in metrics:
            ctx.readiness.hrv_7day_trend = metrics["hrv_trend"]
        if "sleep_minutes" in metrics:
            ctx.sleep.duration_minutes = metrics["sleep_minutes"]
        elif "sleep_hours" in metrics:
            ctx.sleep.duration_minutes = metrics["sleep_hours"] * 60
        if "deep_minutes" in metrics:
            ctx.sleep.deep_minutes = metrics["deep_minutes"]
        if "rem_minutes" in metrics:
            ctx.sleep.rem_minutes = metrics["rem_minutes"]
        if "steps" in metrics:
            ctx.activity.steps_3day_avg = metrics["steps"]
        if "hours_since_workout" in metrics:
            ctx.training.hours_since_last_workout = metrics["hours_since_workout"]
        return ctx

    def user_model_block(self) -> str:
        """Structured ground-truth block for prompt injection (Section 2b)."""
        lines = [
            "[USER MODEL — ground truth]",
            f"- timestamp: {self.timestamp}",
            f"- sleep.duration_min: {_fmt(self.sleep.duration_minutes)}",
            f"- sleep.deep_min: {_fmt(self.sleep.deep_minutes)}",
            f"- sleep.rem_min: {_fmt(self.sleep.rem_minutes)}",
            f"- sleep.efficiency: {_fmt(self.sleep.efficiency)}",
            f"- sleep.hrv_ms: {_fmt(self.sleep.hrv)}",
            f"- readiness.hrv_7day_trend_pct: {_fmt(self.readiness.hrv_7day_trend)}",
            f"- readiness.recovery_score: {_fmt(self.readiness.recovery_score)}",
            f"- training.hours_since_last_workout: {_fmt(self.training.hours_since_last_workout)}",
            f"- training.weekly_load_score: {_fmt(self.training.weekly_load_score)}",
            f"- chronotype.consistency_score: {_fmt(self.chronotype.consistency_score)}",
            f"- missing_fields: {', '.join(self.missing_fields) or 'none'}",
        ]
        return "\n".join(lines)


# --- Model routing (Section 4) -----------------------------------------------


def select_model(response_type: str, *, voice_mode: bool = False) -> str:
    """Pick the model the live path would use for this response.

    Voice mode is always latency-bound (Sonnet). Otherwise multi-signal work
    (recommendation / plan / summary) goes to Opus; single-metric lookups and
    clarifications go to the fast model.
    """
    if voice_mode:
        return MODEL_FAST
    if response_type in ("recommendation", "plan", "summary"):
        return MODEL_PRIMARY
    return MODEL_FAST


# --- Request classification --------------------------------------------------

_ADVICE_PATTERNS = (
    "should i", "what should", "what do i", "what would you", "recommend",
    "advice", "train today", "work out", "workout today", "push", "rest",
    "recover", "recovery", "tired", "exhausted", "wiped", "drained",
    "plan my", "how hard", "go hard", "what's the move", "whats the move",
)
_INSIGHT_PATTERNS = (
    "how was my", "how did i", "how's my", "hows my", "what's my", "whats my",
    "my sleep", "my hrv", "my readiness", "my recovery", "my steps",
    "last night", "did i sleep",
)


def classify_request(message: str, ctx: ARIAContext) -> str:
    """Return the response_type for this turn: insight | recommendation | clarification."""
    text = (message or "").lower()

    usable = ctx.has_sleep or ctx.has_hrv or ctx.readiness.recovery_score is not None
    if not usable:
        return "clarification"

    if any(p in text for p in _ADVICE_PATTERNS):
        return "recommendation"

    # Low recovery is itself a reason to coach rather than merely report.
    recovery = ctx.readiness.recovery_score
    if recovery is not None and recovery < 55:
        return "recommendation"

    if any(p in text for p in _INSIGHT_PATTERNS):
        return "insight"

    # Default: if we have rich signal, surface the highest-priority insight;
    # otherwise nudge toward a recommendation.
    return "insight" if ctx.sleep_baseline_ready or ctx.has_hrv else "recommendation"


# --- Signal interpreters -----------------------------------------------------


@dataclass
class Signal:
    metric: str
    current_value: str
    vs_baseline: str
    interpretation: str
    priority: str  # high | medium | low
    direction: str  # "negative" | "positive" | "neutral" — for conflict detection


def _interpret_sleep(ctx: ARIAContext) -> Signal | None:
    s = ctx.sleep
    if s.duration_minutes is None:
        return None

    hours = s.duration_minutes / 60
    parts: list[str] = [f"{hours:.1f} h total"]
    direction = "neutral"
    priority = "low"
    interp_bits: list[str] = []

    if s.deep_minutes is not None:
        deep_frac = s.deep_minutes / s.duration_minutes if s.duration_minutes else 0
        parts.append(f"{s.deep_minutes:.0f} min deep ({deep_frac * 100:.0f}%)")
        if deep_frac < DEEP_SLEEP_REF_FRAC:
            direction = "negative"
            priority = "high"
            interp_bits.append(
                f"deep sleep is {deep_frac * 100:.0f}% of the night, under the ~{DEEP_SLEEP_REF_FRAC * 100:.0f}% "
                "typical floor — the stage that drives physical recovery came up short"
            )
        else:
            interp_bits.append(f"deep sleep at {deep_frac * 100:.0f}% is in a healthy band")

    if s.rem_minutes is not None and s.duration_minutes:
        rem_frac = s.rem_minutes / s.duration_minutes
        if rem_frac < REM_SLEEP_REF_FRAC:
            interp_bits.append(f"REM is light at {rem_frac * 100:.0f}%")
            if priority == "low":
                priority = "medium"
                direction = "negative"

    if s.efficiency is not None:
        if s.efficiency < EFFICIENCY_REF:
            interp_bits.append(f"efficiency {s.efficiency * 100:.0f}% means the night was fragmented")
            direction = "negative"
            priority = "high" if priority != "high" else priority

    if hours < 6:
        interp_bits.append(f"{hours:.1f} h is below the 7 h floor for cognitive recovery")
        direction = "negative"
        priority = "high"
    elif hours >= 7.5 and direction == "neutral":
        interp_bits.append(f"{hours:.1f} h is solid duration")
        direction = "positive"

    baseline_note = (
        "vs typical adult ranges (no personal sleep baseline yet)"
        if not ctx.sleep_baseline_ready
        else "vs your recent nights"
    )
    interpretation = "; ".join(interp_bits) if interp_bits else "sleep architecture looks unremarkable"
    return Signal(
        metric="Sleep",
        current_value=", ".join(parts),
        vs_baseline=baseline_note,
        interpretation=interpretation,
        priority=priority,
        direction=direction,
    )


def _interpret_readiness(ctx: ARIAContext) -> Signal | None:
    r = ctx.readiness
    if r.hrv_7day_trend is None and r.recovery_score is None:
        return None

    parts: list[str] = []
    interp_bits: list[str] = []
    direction = "neutral"
    priority = "low"

    if r.hrv_7day_trend is not None:
        sign = "+" if r.hrv_7day_trend >= 0 else ""
        parts.append(f"HRV {sign}{r.hrv_7day_trend:.0f}% vs 30-day baseline")
        if r.hrv_7day_trend <= -8:
            direction = "negative"
            priority = "high"
            interp_bits.append(
                f"HRV is {abs(r.hrv_7day_trend):.0f}% below baseline — your autonomic system is still carrying load"
            )
        elif r.hrv_7day_trend >= 5:
            direction = "positive"
            interp_bits.append(f"HRV is {r.hrv_7day_trend:.0f}% above baseline — recovery is trending up")
        else:
            interp_bits.append("HRV is tracking near baseline")

    if r.recovery_score is not None:
        parts.append(f"recovery {r.recovery_score:.0f}/100")
        if r.recovery_score < 55:
            direction = "negative"
            priority = "high"
            interp_bits.append(f"recovery score {r.recovery_score:.0f} sits in the low band")
        elif r.recovery_score >= 80:
            if direction != "negative":
                direction = "positive"
            interp_bits.append(f"recovery score {r.recovery_score:.0f} is strong")

    return Signal(
        metric="Readiness",
        current_value=", ".join(parts),
        vs_baseline="vs 30-day HRV baseline",
        interpretation="; ".join(interp_bits) or "readiness is mid-band",
        priority=priority,
        direction=direction,
    )


def _interpret_training(ctx: ARIAContext) -> Signal | None:
    t = ctx.training
    if t.hours_since_last_workout is None and t.weekly_load_score is None:
        return None
    parts: list[str] = []
    interp_bits: list[str] = []
    priority = "low"
    direction = "neutral"

    if t.hours_since_last_workout is not None:
        hrs = t.hours_since_last_workout
        label = t.last_workout_type or "your last session"
        parts.append(f"{hrs:.0f} h since {label}")
        if hrs < 24:
            interp_bits.append(f"only {hrs:.0f} h since {label} — recovery window is still open")
            priority = "medium"
        elif hrs > 72:
            interp_bits.append(f"{hrs:.0f} h of rest — you're well recovered for intensity")
            direction = "positive"

    if t.weekly_load_score is not None:
        parts.append(f"weekly load {t.weekly_load_score:.0f}")
        if t.weekly_load_score >= 80:
            interp_bits.append("weekly load is high — watch for accumulating fatigue")
            priority = "medium"

    return Signal(
        metric="Training load",
        current_value=", ".join(parts),
        vs_baseline="vs your rolling week",
        interpretation="; ".join(interp_bits) or "training load is moderate",
        priority=priority,
        direction=direction,
    )


_PRIORITY_RANK = {"high": 0, "medium": 1, "low": 2}


def _gather_signals(ctx: ARIAContext) -> list[Signal]:
    signals = [
        _interpret_sleep(ctx),
        _interpret_readiness(ctx),
        _interpret_training(ctx),
    ]
    present = [s for s in signals if s is not None]
    present.sort(key=lambda s: _PRIORITY_RANK.get(s.priority, 3))
    return present


# --- Confidence calibration (Section 5) --------------------------------------


def _calibrate_confidence(ctx: ARIAContext, signals: list[Signal]) -> tuple[float, str]:
    """Return (confidence, confidence_reason). Calibrated, never a flat constant.

    ``confidence`` accumulates soft penalties/bonuses; ``ceiling`` holds the hard
    cap imposed by degraded data states. The ceiling is applied last so a
    signal-coherence bonus can never breach a degraded-data limit.
    """
    confidence = 0.9
    ceiling = 0.92
    reasons: list[str] = []

    if not ctx.has_sleep:
        confidence -= 0.35
        reasons.append("no last-night sleep data")
    elif not ctx.sleep_baseline_ready:
        ceiling = min(ceiling, 0.4)
        nights = ctx.sleep.nights_available
        reasons.append(
            f"only {nights} night(s) of sleep history" if nights is not None
            else "no personal sleep baseline yet (<3 nights)"
        )
    elif ctx.sleep.deep_minutes is None and ctx.sleep.rem_minutes is None:
        confidence -= 0.1
        reasons.append("sleep stages unavailable (duration only)")

    if not ctx.has_hrv:
        ceiling = min(ceiling, 0.65)
        reasons.append("no HRV — readiness scoring disabled, using sleep proxies")
    else:
        days = ctx.readiness.hrv_days_available
        if days is not None and days < 3:
            ceiling = min(ceiling, 0.5)
            reasons.append(f"only {days} day(s) of HRV")

    if not ctx.has_training_history:
        ceiling = min(ceiling, 0.7)
        reasons.append("no recent workout history")

    # Signal conflict — coherent signals raise trust, contradictory ones lower it.
    directions = {s.direction for s in signals if s.direction in ("negative", "positive")}
    if "negative" in directions and "positive" in directions:
        confidence -= 0.12
        reasons.append("signals diverge (e.g. sleep and HRV disagree)")
    elif len(signals) >= 2 and directions == {"negative"}:
        # Multiple signals agreeing is the strongest case.
        confidence += 0.02

    confidence = max(0.1, min(ceiling, round(confidence, 2)))
    reason = "; ".join(reasons) if reasons else "full last-night sleep and HRV-trend data, signals are coherent"
    return confidence, reason


# --- Response assembly (Section 3) -------------------------------------------


def _clarification_response(ctx: ARIAContext, voice_mode: bool) -> dict[str, Any]:
    question = "What did last night's sleep look like — roughly how many hours, and did you train today?"
    prose = (
        "I don't have today's HealthKit signals yet, so I won't guess. "
        + question
    )
    card = None if voice_mode else {"question": question, "why": "no usable sleep, HRV, or recovery signal in this request"}
    return _envelope(
        response_type="clarification",
        confidence=0.2,
        confidence_reason="no usable sleep, HRV, or recovery data in context",
        prose_summary=prose,
        card=card,
        message=prose,
        suggested_actions=["Sync HealthKit", "Log last night's sleep", "Tell ARIA about today"],
        voice_mode=voice_mode,
    )


def _recommendation_response(ctx: ARIAContext, signals: list[Signal], voice_mode: bool) -> dict[str, Any]:
    confidence, reason = _calibrate_confidence(ctx, signals)
    lead = signals[0] if signals else None
    negative = [s for s in signals if s.direction == "negative"]

    if negative:
        driver = negative[0]
        action = "Keep today low-intensity — Zone 2 cardio or mobility, not a hard session"
        timing = "Reassess tomorrow once HRV and deep sleep recover"
        rationale = f"{driver.metric.lower()}: {driver.interpretation}"
        expected = "Protecting today should pull HRV back toward baseline within 24-48 h"
        chat = (
            f"Hold back today. {_cap(driver.interpretation)}. "
            f"{action.lower().replace('keep today', 'Keep it')}, and we reassess tomorrow."
        )
        prose = f"{_cap(driver.interpretation)} — keep today easy and let recovery catch up."
        actions = ["Show recovery plan", "Swap to Zone 2", "Protect tonight's sleep"]
    elif lead and lead.direction == "positive":
        action = "Green light for intensity — this is a day to push"
        timing = "Train in your usual window while readiness is high"
        rationale = f"{lead.metric.lower()}: {lead.interpretation}"
        expected = "You can absorb a hard stimulus today without digging a recovery hole"
        chat = f"You're primed. {_cap(lead.interpretation)}. Good day to go after a hard session or a PR attempt."
        prose = f"{_cap(lead.interpretation)} — you're clear to push hard today."
        actions = ["Build a hard session", "Set a PR target", "Review readiness"]
    else:
        detail = lead.interpretation if lead else "your signals are mid-band"
        action = "Train at moderate intensity with controlled progressive overload"
        timing = "Your normal training window works today"
        rationale = detail
        expected = "Steady stimulus keeps adaptation moving without overreaching"
        chat = f"Solid middle ground today. {_cap(detail)}. Match the session to that and keep overload controlled."
        prose = f"{_cap(detail)} — train moderate and keep overload controlled."
        actions = ["Today's workout", "Tune intensity", "Check sleep trend"]

    # No workout history: stay conservative and ask one calibrating question (Section 5).
    if not ctx.has_training_history:
        actions = actions[:2] + ["Tell ARIA your last workout"]
        chat += " I don't have your recent training load yet — what and when was your last real session?"

    card = None if voice_mode else {
        "action": action,
        "rationale": rationale,
        "timing": timing,
        "expected_effect": expected,
    }
    return _envelope(
        response_type="recommendation",
        confidence=confidence,
        confidence_reason=reason,
        prose_summary=prose,
        card=card,
        message=chat,
        suggested_actions=actions,
        voice_mode=voice_mode,
    )


def _insight_response(ctx: ARIAContext, signals: list[Signal], voice_mode: bool) -> dict[str, Any]:
    confidence, reason = _calibrate_confidence(ctx, signals)
    lead = signals[0] if signals else None
    if lead is None:
        return _clarification_response(ctx, voice_mode)

    chat = f"{lead.metric}: {lead.current_value} ({lead.vs_baseline}). {_cap(lead.interpretation)}."
    prose = f"{lead.metric}: {lead.current_value}. {_cap(lead.interpretation)}."
    card = None if voice_mode else {
        "metric": lead.metric,
        "current_value": lead.current_value,
        "vs_baseline": lead.vs_baseline,
        "interpretation": lead.interpretation,
        "priority": lead.priority,
    }
    actions = ["What should I do about it?", "Show the trend", "Compare to last week"]
    return _envelope(
        response_type="insight",
        confidence=confidence,
        confidence_reason=reason,
        prose_summary=prose,
        card=card,
        message=chat,
        suggested_actions=actions,
        voice_mode=voice_mode,
    )


def generate_response(message: str, ctx: ARIAContext, *, voice_mode: bool = False) -> dict[str, Any]:
    """Top-level entry: message + context -> versioned ARIA response envelope."""
    response_type = classify_request(message, ctx)
    signals = _gather_signals(ctx)

    if response_type == "clarification":
        return _clarification_response(ctx, voice_mode)
    if response_type == "recommendation":
        return _recommendation_response(ctx, signals, voice_mode)
    return _insight_response(ctx, signals, voice_mode)


def _envelope(
    *,
    response_type: str,
    confidence: float,
    confidence_reason: str,
    prose_summary: str,
    card: dict[str, Any] | None,
    message: str,
    suggested_actions: list[str],
    voice_mode: bool,
) -> dict[str, Any]:
    """Assemble the v1.0 response envelope.

    Spec fields are canonical; ``message``/``suggested_actions`` are kept for the
    deployed chat client. In voice mode the card is suppressed and prose is
    trimmed toward the token cap.
    """
    if voice_mode:
        card = None
        message = prose_summary
    return {
        "schema_version": SCHEMA_VERSION,
        "response_type": response_type,
        "confidence": confidence,
        "confidence_reason": confidence_reason,
        "prose_summary": prose_summary,
        "card": card,
        # --- compatibility layer for the deployed chat surface ---
        "message": message,
        "suggested_actions": suggested_actions,
        "model": select_model(response_type, voice_mode=voice_mode),
    }


def build_user_prompt(message: str, ctx: ARIAContext) -> str:
    """User-turn prompt for the future Bedrock path: question + injected context."""
    return f"{ctx.user_model_block()}\n\n[USER MESSAGE]\n{message.strip()}"


# --- coercion helpers --------------------------------------------------------


def _num(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _int(value: Any) -> int | None:
    n = _num(value)
    return int(n) if n is not None else None


def _str(value: Any) -> str | None:
    if value is None:
        return None
    text = str(value).strip()
    return text or None


def _coerce_metrics(raw: Any) -> dict[str, float]:
    if not isinstance(raw, dict):
        return {}
    out: dict[str, float] = {}
    for key, value in raw.items():
        n = _num(value)
        if n is not None:
            out[str(key)] = n
    return out


def _fmt(value: float | None) -> str:
    if value is None:
        return "null"
    if isinstance(value, float) and value.is_integer():
        return str(int(value))
    return f"{value:.2f}" if isinstance(value, float) else str(value)


def _cap(text: str) -> str:
    text = text.strip()
    return text[:1].upper() + text[1:] if text else text


# Voice helper: a rough token estimate so callers can assert the cap.
def estimate_tokens(text: str) -> int:
    words = re.findall(r"\S+", text)
    return int(len(words) / 0.75) if words else 0
