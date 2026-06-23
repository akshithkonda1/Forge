"""ARIA reasoning engine — Phase 1 (HealthKit + app data).

This module is the coaching core behind ``POST /ai/chat``. ``generate_response``
is a *deterministic function*: given a context payload it produces consistent,
data-specific, schema-conformant output with no external calls, so it stays pure
and fully testable. ``generate_response_live`` wraps it with a real Claude call on
Amazon Bedrock (opt-in via ``ARIA_BEDROCK_ENABLED``): it overlays the model's
reasoning onto the deterministic envelope and falls back to it on any failure, so
the endpoint never breaks because Bedrock is unreachable.

The contract it implements is versioned (v1.1):

  * Input  — ``ARIAContext`` spanning every app data domain (sleep, readiness,
             activity, training, chronotype, body, nutrition, profile, progress,
             lifestyle), each with explicit nulls.
  * Permissions — ``DataPermissions`` gate which domains ARIA may use. Denied
             domains are *redacted* before reasoning ever sees them, so blocked
             data cannot leak into a response.
  * Output — the response envelope (schema_version, response_type, confidence,
             confidence_reason, prose_summary, card, restricted_domains).

Design rules enforced here (so they cannot silently drift):
  * Every response references at least one concrete metric when data exists.
  * Confidence is calibrated from data completeness and signal agreement —
    never a flat constant.
  * Missing data is declared, never papered over. A domain the user turned off
    is reported as *restricted*, distinct from merely *missing*.
  * ``prose_summary`` is mandatory on every response (voice-mode fallback).
"""

from __future__ import annotations

import json
import os
import re
import threading
from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any, Callable

# --- Versioned interface -----------------------------------------------------

SCHEMA_VERSION = "1.1"

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

# Every data domain ARIA can reason over, in signal-priority order. This is also
# the permission surface — each is independently grantable.
ALL_DOMAINS = (
    "sleep",
    "readiness",
    "activity",
    "training",
    "chronotype",
    "body",
    "nutrition",
    "profile",
    "progress",
    "lifestyle",
)

# Client-friendly aliases so permission/context payloads can use natural names.
_DOMAIN_ALIASES = {
    "recovery": "readiness",
    "hrv": "readiness",
    "workouts": "training",
    "workout": "training",
    "exercise": "training",
    "steps": "activity",
    "movement": "activity",
    "weight": "body",
    "body_metrics": "body",
    "bodymetrics": "body",
    "meals": "nutrition",
    "diet": "nutrition",
    "food": "nutrition",
    "goals": "profile",
    "preferences": "profile",
    "patterns": "lifestyle",
    "habits": "lifestyle",
}


# --- Canonical ARIA system prompt (Section 2) --------------------------------
#
# Phase 1 ``/ai/chat`` is deterministic and does not execute this prompt, but the
# brief treats the prompt as a product artifact ("ARIA is the product"). It is
# defined here as the single canonical version and unit-tested for the behaviors
# the brief requires it to have.
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
the chronotype, baselines, goals, and current signals as established facts about
this person and reason over them directly.

DATA PERMISSIONS — you may only use the data domains the user has granted. A
domain listed as restricted is off-limits: never use it, infer it, or reference
its values. When a restricted domain would have materially changed your answer,
say so plainly and lower confidence — do not pretend it is merely missing.

CONFIDENCE — express uncertainty in a calibrated, non-evasive way. When
confidence is low, say why (e.g. "only 2 nights of HRV data"), still give a
best estimate, and name the one signal that would change the answer. Never
hedge into a vague non-answer to avoid being wrong.

MISSING DATA — if a signal is absent, say so and lower confidence accordingly.
Do not silently proceed as if it were present.

OUTPUT CONTRACT — respond as a single JSON object conforming to schema version
{SCHEMA_VERSION}: schema_version, response_type (insight | recommendation | plan
| summary | clarification), confidence (0.0-1.0), confidence_reason,
prose_summary (1-3 sentences, usable as a standalone spoken response), a matching
card, and restricted_domains. prose_summary is mandatory on every response. In
voice mode, return prose only and cap at ~{VOICE_TOKEN_CAP} tokens — no card.
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


@dataclass
class BodyContext:
    weight_kg: float | None = None
    weight_trend_kg: float | None = None    # signed 30-day delta
    body_fat_pct: float | None = None
    vo2_max: float | None = None


@dataclass
class NutritionContext:
    calories_in_3day_avg: float | None = None
    protein_g_3day_avg: float | None = None
    hydration_ml_3day_avg: float | None = None
    calorie_target: float | None = None


@dataclass
class ProfileContext:
    primary_goal: str | None = None       # lose-fat | build-muscle | improve-endurance | ...
    experience_level: str | None = None   # beginner | intermediate | advanced | elite
    coaching_style: str | None = None     # push-hard | balanced | patient | data-driven
    constraints: list[str] = field(default_factory=list)  # injuries, time, equipment


@dataclass
class ProgressContext:
    workouts_completed_30d: int | None = None
    new_personal_records: int | None = None
    training_load_trend: str | None = None       # rising | steady | falling
    recovery_consistency_delta: float | None = None  # signed change in recovery consistency


@dataclass
class LifestyleContext:
    tags: list[str] = field(default_factory=list)
    recent_patterns: list[str] = field(default_factory=list)
    goals: list[str] = field(default_factory=list)


# Scalar leaves surfaced in ``missing_fields``. List-valued domains (profile
# constraints, lifestyle) report presence separately.
_FIELD_MAP: dict[str, list[str]] = {
    "sleep": ["duration_minutes", "efficiency", "rem_minutes", "deep_minutes", "hrv", "resting_hr"],
    "readiness": ["hrv_7day_trend", "hrv_30day_baseline", "recovery_score"],
    "training": ["last_workout_type", "last_workout_duration_minutes", "hours_since_last_workout", "weekly_load_score"],
    "activity": ["steps_3day_avg", "active_calories_3day_avg"],
    "chronotype": ["typical_sleep_onset", "typical_wake_time", "consistency_score"],
    "body": ["weight_kg", "weight_trend_kg", "body_fat_pct", "vo2_max"],
    "nutrition": ["calories_in_3day_avg", "protein_g_3day_avg", "hydration_ml_3day_avg", "calorie_target"],
    "profile": ["primary_goal", "experience_level", "coaching_style"],
    "progress": ["workouts_completed_30d", "new_personal_records", "training_load_trend", "recovery_consistency_delta"],
}

# Type per domain — used to mint a fresh empty instance when a domain is redacted.
_DOMAIN_TYPES = {
    "sleep": SleepContext,
    "readiness": ReadinessContext,
    "activity": ActivityContext,
    "training": TrainingContext,
    "chronotype": ChronotypeContext,
    "body": BodyContext,
    "nutrition": NutritionContext,
    "profile": ProfileContext,
    "progress": ProgressContext,
    "lifestyle": LifestyleContext,
}


@dataclass
class ARIAContext:
    timestamp: str = field(default_factory=_utcnow_iso)
    sleep: SleepContext = field(default_factory=SleepContext)
    readiness: ReadinessContext = field(default_factory=ReadinessContext)
    training: TrainingContext = field(default_factory=TrainingContext)
    activity: ActivityContext = field(default_factory=ActivityContext)
    chronotype: ChronotypeContext = field(default_factory=ChronotypeContext)
    body: BodyContext = field(default_factory=BodyContext)
    nutrition: NutritionContext = field(default_factory=NutritionContext)
    profile: ProfileContext = field(default_factory=ProfileContext)
    progress: ProgressContext = field(default_factory=ProgressContext)
    lifestyle: LifestyleContext = field(default_factory=LifestyleContext)

    @property
    def _groups(self) -> dict[str, Any]:
        return {name: getattr(self, name) for name in ALL_DOMAINS}

    @property
    def missing_fields(self) -> list[str]:
        groups = self._groups
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
    def has_progress(self) -> bool:
        p = self.progress
        return any(
            v is not None
            for v in (p.workouts_completed_30d, p.new_personal_records, p.training_load_trend)
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
        derives a minimal context from the legacy flat ``recent_metrics`` bag.
        Either way, absent signals stay ``None`` so ``missing_fields`` stays
        honest.
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
        body = data.get("body") or {}
        nutrition = data.get("nutrition") or {}
        profile = data.get("profile") or {}
        progress = data.get("progress") or {}
        lifestyle = data.get("lifestyle") or {}
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
            body=BodyContext(
                weight_kg=_num(body.get("weightKg")),
                weight_trend_kg=_num(body.get("weightTrendKg")),
                body_fat_pct=_num(body.get("bodyFatPct")),
                vo2_max=_num(body.get("vo2Max")),
            ),
            nutrition=NutritionContext(
                calories_in_3day_avg=_num(nutrition.get("caloriesIn3DayAvg")),
                protein_g_3day_avg=_num(nutrition.get("proteinG3DayAvg")),
                hydration_ml_3day_avg=_num(nutrition.get("hydrationMl3DayAvg")),
                calorie_target=_num(nutrition.get("calorieTarget")),
            ),
            profile=ProfileContext(
                primary_goal=_str(profile.get("primaryGoal")),
                experience_level=_str(profile.get("experienceLevel")),
                coaching_style=_str(profile.get("coachingStyle")),
                constraints=_str_list(profile.get("constraints")),
            ),
            progress=ProgressContext(
                workouts_completed_30d=_int(progress.get("workoutsCompleted30d")),
                new_personal_records=_int(progress.get("newPersonalRecords")),
                training_load_trend=_str(progress.get("trainingLoadTrend")),
                recovery_consistency_delta=_num(progress.get("recoveryConsistencyDelta")),
            ),
            lifestyle=LifestyleContext(
                tags=_str_list(lifestyle.get("tags")),
                recent_patterns=_str_list(lifestyle.get("recentPatterns")),
                goals=_str_list(lifestyle.get("goals")),
            ),
        )

    @classmethod
    def _from_legacy_metrics(cls, metrics: dict[str, float]) -> "ARIAContext":
        """Bridge the flat ``recent_metrics`` bag onto the structured context."""
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
        if "active_calories" in metrics:
            ctx.activity.active_calories_3day_avg = metrics["active_calories"]
        if "hours_since_workout" in metrics:
            ctx.training.hours_since_last_workout = metrics["hours_since_workout"]
        if "weight_kg" in metrics:
            ctx.body.weight_kg = metrics["weight_kg"]
        if "weight_trend_kg" in metrics:
            ctx.body.weight_trend_kg = metrics["weight_trend_kg"]
        return ctx

    def user_model_block(self, restricted: list[str] | None = None) -> str:
        """Structured ground-truth block for prompt injection (Section 2b)."""
        restricted = restricted or []
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
            f"- activity.steps_3day_avg: {_fmt(self.activity.steps_3day_avg)}",
            f"- training.hours_since_last_workout: {_fmt(self.training.hours_since_last_workout)}",
            f"- training.weekly_load_score: {_fmt(self.training.weekly_load_score)}",
            f"- body.weight_trend_kg: {_fmt(self.body.weight_trend_kg)}",
            f"- body.vo2_max: {_fmt(self.body.vo2_max)}",
            f"- nutrition.protein_g_3day_avg: {_fmt(self.nutrition.protein_g_3day_avg)}",
            f"- profile.primary_goal: {self.profile.primary_goal or 'null'}",
            f"- profile.coaching_style: {self.profile.coaching_style or 'null'}",
            f"- profile.constraints: {', '.join(self.profile.constraints) or 'none'}",
            f"- chronotype.consistency_score: {_fmt(self.chronotype.consistency_score)}",
            f"- lifestyle.patterns: {', '.join(self.lifestyle.recent_patterns) or 'none'}",
            f"- missing_fields: {', '.join(self.missing_fields) or 'none'}",
            f"- restricted_domains: {', '.join(restricted) or 'none'}",
        ]
        return "\n".join(lines)


# --- Data permissions --------------------------------------------------------


def normalize_domain(name: Any) -> str | None:
    key = str(name or "").strip().lower().replace("-", "_").replace(" ", "_")
    if key in ALL_DOMAINS:
        return key
    return _DOMAIN_ALIASES.get(key)


@dataclass
class DataPermissions:
    """Per-domain grants gating which data ARIA may use.

    Stateless: parsed from each request. Default posture is allow-unless-denied
    so existing clients keep working; flip ``default_allow`` for opt-in.
    """

    granted: dict[str, bool] = field(default_factory=dict)

    @classmethod
    def allow_all(cls) -> "DataPermissions":
        return cls({domain: True for domain in ALL_DOMAINS})

    @classmethod
    def from_payload(cls, raw: Any, *, default_allow: bool = True) -> "DataPermissions":
        granted = {domain: default_allow for domain in ALL_DOMAINS}

        if isinstance(raw, dict) and ("allow" in raw or "deny" in raw):
            allow = raw.get("allow")
            deny = raw.get("deny")
            if isinstance(allow, list):
                allowed = {d for d in (normalize_domain(x) for x in allow) if d}
                granted = {domain: (domain in allowed) for domain in ALL_DOMAINS}
            if isinstance(deny, list):
                for item in deny:
                    domain = normalize_domain(item)
                    if domain:
                        granted[domain] = False
        elif isinstance(raw, dict):
            for key, value in raw.items():
                domain = normalize_domain(key)
                if domain:
                    granted[domain] = bool(value)
        elif isinstance(raw, (list, tuple)):
            allowed = {d for d in (normalize_domain(x) for x in raw) if d}
            granted = {domain: (domain in allowed) for domain in ALL_DOMAINS}

        return cls(granted)

    def allows(self, domain: str) -> bool:
        return self.granted.get(domain, True)

    def restricted(self) -> list[str]:
        return [domain for domain in ALL_DOMAINS if not self.granted.get(domain, True)]


def apply_permissions(ctx: ARIAContext, permissions: DataPermissions) -> tuple[ARIAContext, list[str]]:
    """Redact denied domains so reasoning physically cannot reference them.

    Returns the sanitized context and the list of restricted domain names.
    """
    restricted = permissions.restricted()
    if not restricted:
        return ctx, []
    sanitized = ARIAContext(timestamp=ctx.timestamp, **{name: getattr(ctx, name) for name in ALL_DOMAINS})
    for domain in restricted:
        setattr(sanitized, domain, _DOMAIN_TYPES[domain]())
    return sanitized, restricted


# --- Model routing (Section 4) -----------------------------------------------


def select_model(response_type: str, *, voice_mode: bool = False) -> str:
    """Pick the model the live path would use for this response."""
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
    "my sleep", "my hrv", "my readiness", "my recovery", "my steps", "my weight",
    "my vo2", "last night", "did i sleep",
)
_SUMMARY_PATTERNS = (
    "progress", "this month", "this week", "review", "trending", "trend",
    "how am i doing", "how's it going", "summary", "recap", "personal record",
    " pr ", "prs",
)

# Words → the domain a question is *about*, so an insight answers what was asked
# rather than whatever signal happens to be highest priority.
_DOMAIN_KEYWORDS: dict[str, tuple[str, ...]] = {
    "sleep": ("sleep", "slept", "deep", "rem", "bed"),
    "readiness": ("readiness", "recovery", "hrv", "recovered", "ready"),
    "training": ("training", "workout", "session", "load", "lift", "run"),
    "activity": ("steps", "active", "move", "moving", "walk"),
    "body": ("weight", "vo2", "body fat", "bodyfat", "lean", "scale"),
    "nutrition": ("protein", "calorie", "nutrition", "eat", "diet", "hydrat", "water", "macro"),
    "progress": ("progress", "trend", "month", "improving", "personal record", "pr"),
}


def _focus_domain(message: str) -> str | None:
    text = (message or "").lower()
    for domain, words in _DOMAIN_KEYWORDS.items():
        if any(word in text for word in words):
            return domain
    return None


def classify_request(message: str, ctx: ARIAContext) -> str:
    """Return the response_type: insight | recommendation | summary | clarification."""
    text = (message or "").lower()

    usable = (
        ctx.has_sleep
        or ctx.has_hrv
        or ctx.readiness.recovery_score is not None
        or ctx.has_progress
        or ctx.activity.steps_3day_avg is not None
        or ctx.body.weight_trend_kg is not None
    )
    if not usable:
        return "clarification"

    if any(p in text for p in _ADVICE_PATTERNS):
        return "recommendation"

    recovery = ctx.readiness.recovery_score
    if recovery is not None and recovery < 55:
        return "recommendation"

    focus = _focus_domain(text)

    # A specific question about one domain is an insight — even if it contains a
    # generic word like "trend" that also reads as a progress summary.
    if focus and focus != "progress":
        return "insight"

    if (focus == "progress" or any(p in text for p in _SUMMARY_PATTERNS)) and ctx.has_progress:
        return "summary"

    if any(p in text for p in _INSIGHT_PATTERNS) or focus:
        return "insight"

    return "insight" if ctx.sleep_baseline_ready or ctx.has_hrv else "recommendation"


# --- Signal interpreters -----------------------------------------------------


@dataclass
class Signal:
    domain: str
    metric: str
    current_value: str
    vs_baseline: str
    interpretation: str
    priority: str   # high | medium | low
    direction: str  # negative | positive | neutral


def _interpret_sleep(ctx: ARIAContext) -> Signal | None:
    s = ctx.sleep
    if s.duration_minutes is None:
        return None

    hours = s.duration_minutes / 60
    parts: list[str] = [f"{hours:.1f} h total"]
    direction = "neutral"
    priority = "low"
    interp_bits: list[str] = []

    if s.deep_minutes is not None and s.duration_minutes:
        deep_frac = s.deep_minutes / s.duration_minutes
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

    if s.efficiency is not None and s.efficiency < EFFICIENCY_REF:
        interp_bits.append(f"efficiency {s.efficiency * 100:.0f}% means the night was fragmented")
        direction = "negative"
        priority = "high"

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
    return Signal("sleep", "Sleep", ", ".join(parts), baseline_note, interpretation, priority, direction)


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
        "readiness", "Readiness", ", ".join(parts), "vs 30-day HRV baseline",
        "; ".join(interp_bits) or "readiness is mid-band", priority, direction,
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
        "training", "Training load", ", ".join(parts), "vs your rolling week",
        "; ".join(interp_bits) or "training load is moderate", priority, direction,
    )


def _interpret_activity(ctx: ARIAContext) -> Signal | None:
    a = ctx.activity
    if a.steps_3day_avg is None and a.active_calories_3day_avg is None:
        return None
    parts: list[str] = []
    interp_bits: list[str] = []
    direction = "neutral"
    priority = "low"

    if a.steps_3day_avg is not None:
        parts.append(f"{a.steps_3day_avg:.0f} steps/day (3-day avg)")
        if a.steps_3day_avg < 5000:
            interp_bits.append(f"{a.steps_3day_avg:.0f} steps/day is light — daily movement is low")
            direction = "negative"
            priority = "medium"
        elif a.steps_3day_avg >= 10000:
            interp_bits.append(f"{a.steps_3day_avg:.0f} steps/day clears the 10k mark — strong baseline movement")
            direction = "positive"

    if a.active_calories_3day_avg is not None:
        parts.append(f"{a.active_calories_3day_avg:.0f} active kcal/day")

    return Signal(
        "activity", "Activity", ", ".join(parts), "vs a 3-day average",
        "; ".join(interp_bits) or "daily activity is moderate", priority, direction,
    )


def _interpret_body(ctx: ARIAContext) -> Signal | None:
    b = ctx.body
    if b.weight_trend_kg is None and b.vo2_max is None and b.body_fat_pct is None:
        return None
    parts: list[str] = []
    interp_bits: list[str] = []
    direction = "neutral"
    goal = ctx.profile.primary_goal

    if b.weight_trend_kg is not None:
        sign = "+" if b.weight_trend_kg >= 0 else ""
        parts.append(f"weight {sign}{b.weight_trend_kg:.1f} kg/30d")
        losing = b.weight_trend_kg < -0.2
        gaining = b.weight_trend_kg > 0.2
        if goal == "lose-fat":
            if losing:
                direction = "positive"
                interp_bits.append(f"down {abs(b.weight_trend_kg):.1f} kg over 30 days — the fat-loss trend is working")
            elif gaining:
                direction = "negative"
                interp_bits.append(f"up {b.weight_trend_kg:.1f} kg against a fat-loss goal — the deficit isn't landing")
        elif goal == "build-muscle":
            if gaining:
                direction = "positive"
                interp_bits.append(f"up {b.weight_trend_kg:.1f} kg over 30 days — lean mass is trending the right way")
            elif losing:
                interp_bits.append(f"down {abs(b.weight_trend_kg):.1f} kg while building — check you're eating enough")
        else:
            interp_bits.append(f"weight has moved {sign}{b.weight_trend_kg:.1f} kg over 30 days")

    if b.vo2_max is not None:
        parts.append(f"VO2max {b.vo2_max:.0f}")
        if b.vo2_max >= 45:
            interp_bits.append(f"VO2max {b.vo2_max:.0f} is strong aerobic fitness")
        elif b.vo2_max < 35:
            interp_bits.append(f"VO2max {b.vo2_max:.0f} leaves aerobic headroom to build")

    return Signal(
        "body", "Body", ", ".join(parts), "vs a 30-day trend",
        "; ".join(interp_bits) or "body metrics are stable", "low", direction,
    )


def _interpret_nutrition(ctx: ARIAContext) -> Signal | None:
    n = ctx.nutrition
    if n.protein_g_3day_avg is None and n.calories_in_3day_avg is None:
        return None
    parts: list[str] = []
    interp_bits: list[str] = []
    direction = "neutral"
    priority = "low"

    if n.protein_g_3day_avg is not None:
        parts.append(f"{n.protein_g_3day_avg:.0f} g protein/day")
        weight = ctx.body.weight_kg
        if weight:
            target = 1.6 * weight
            if n.protein_g_3day_avg < 0.85 * target:
                direction = "negative"
                priority = "medium"
                interp_bits.append(
                    f"protein is {n.protein_g_3day_avg:.0f} g/day, under the ~{target:.0f} g your bodyweight calls for"
                )
            else:
                interp_bits.append(f"protein at {n.protein_g_3day_avg:.0f} g/day is supporting recovery")

    if n.calories_in_3day_avg is not None:
        parts.append(f"{n.calories_in_3day_avg:.0f} kcal/day")
        if n.calorie_target:
            delta = n.calories_in_3day_avg - n.calorie_target
            interp_bits.append(f"intake is {delta:+.0f} kcal vs your {n.calorie_target:.0f} target")

    return Signal(
        "nutrition", "Nutrition", ", ".join(parts), "vs your targets",
        "; ".join(interp_bits) or "fueling looks on track", priority, direction,
    )


_PRIORITY_RANK = {"high": 0, "medium": 1, "low": 2}

_INTERPRETERS = (
    _interpret_sleep,
    _interpret_readiness,
    _interpret_training,
    _interpret_activity,
    _interpret_body,
    _interpret_nutrition,
)


def _gather_signals(ctx: ARIAContext) -> list[Signal]:
    present = [signal for interp in _INTERPRETERS if (signal := interp(ctx)) is not None]
    present.sort(key=lambda s: _PRIORITY_RANK.get(s.priority, 3))
    return present


def _signal_for_domain(signals: list[Signal], domain: str | None) -> Signal | None:
    if domain is None:
        return None
    for signal in signals:
        if signal.domain == domain:
            return signal
    return None


# --- Confidence calibration (Section 5) --------------------------------------


def _calibrate_confidence(
    ctx: ARIAContext, signals: list[Signal], restricted: list[str]
) -> tuple[float, str]:
    """Return (confidence, confidence_reason). Calibrated, never a flat constant.

    Hard degraded-data caps live in ``ceiling`` and are applied last, so a
    coherence bonus can never breach them. Restricted domains are reported as
    permission-blocked rather than merely missing.
    """
    confidence = 0.9
    ceiling = 0.92
    reasons: list[str] = []
    blocked = set(restricted)

    def _why(domain: str, missing_phrase: str) -> str:
        return f"{domain} is off (permission)" if domain in blocked else missing_phrase

    if not ctx.has_sleep:
        confidence -= 0.35
        reasons.append(_why("sleep", "no last-night sleep data"))
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
        reasons.append(_why("readiness", "no HRV — readiness scoring disabled, using sleep proxies"))
    else:
        days = ctx.readiness.hrv_days_available
        if days is not None and days < 3:
            ceiling = min(ceiling, 0.5)
            reasons.append(f"only {days} day(s) of HRV")

    if not ctx.has_training_history:
        ceiling = min(ceiling, 0.7)
        reasons.append(_why("training", "no recent workout history"))

    directions = {s.direction for s in signals if s.direction in ("negative", "positive")}
    if "negative" in directions and "positive" in directions:
        confidence -= 0.12
        reasons.append("signals diverge (e.g. sleep and HRV disagree)")
    elif len(signals) >= 2 and directions == {"negative"}:
        confidence += 0.02

    confidence = max(0.1, min(ceiling, round(confidence, 2)))
    reason = "; ".join(reasons) if reasons else "full last-night sleep and HRV-trend data, signals are coherent"
    return confidence, reason


# --- Profile-aware shaping ----------------------------------------------------

_GOAL_FOCUS = {
    "lose-fat": "keeps you in the deficit without torching recovery",
    "build-muscle": "protects the hypertrophy stimulus you're building",
    "improve-endurance": "keeps aerobic adaptation on track",
    "athletic-performance": "keeps you sharp for performance",
    "general-fitness": "keeps your training sustainable",
}


def _apply_profile(chat: str, expected: str, ctx: ARIAContext) -> tuple[str, str]:
    """Fold goals, constraints, and experience into a recommendation."""
    goal = ctx.profile.primary_goal
    if goal in _GOAL_FOCUS:
        expected = f"{expected} — {_GOAL_FOCUS[goal]}"
    if ctx.profile.constraints:
        chat = f"{chat} Work around your {ctx.profile.constraints[0]}."
    if ctx.profile.experience_level == "beginner":
        chat = f"{chat} Keep it simple — consistency beats intensity right now."
    return chat, expected


# --- Response assembly (Section 3) -------------------------------------------


def _clarification_response(ctx: ARIAContext, restricted: list[str], voice_mode: bool) -> dict[str, Any]:
    if restricted:
        question = (
            f"I can only see what you've shared — {', '.join(restricted)} "
            f"{'is' if len(restricted) == 1 else 'are'} off. Turn it on or tell me directly?"
        )
        why = f"usable domains are restricted by permission: {', '.join(restricted)}"
        actions = ["Review data permissions", "Tell ARIA directly", "Sync HealthKit"]
    else:
        question = "What did last night's sleep look like — roughly how many hours, and did you train today?"
        why = "no usable sleep, HRV, recovery, or activity signal in this request"
        actions = ["Sync HealthKit", "Log last night's sleep", "Tell ARIA about today"]
    prose = f"I won't guess without data. {question}"
    card = None if voice_mode else {"question": question, "why": why}
    return _envelope(
        response_type="clarification",
        confidence=0.2,
        confidence_reason=why,
        prose_summary=prose,
        card=card,
        message=prose,
        suggested_actions=actions,
        voice_mode=voice_mode,
    )


def _recommendation_response(
    message: str, ctx: ARIAContext, signals: list[Signal], restricted: list[str], voice_mode: bool
) -> dict[str, Any]:
    confidence, reason = _calibrate_confidence(ctx, signals, restricted)
    lead = signals[0] if signals else None
    negative = [s for s in signals if s.direction == "negative"]

    if negative:
        driver = negative[0]
        action = "Keep today low-intensity — Zone 2 cardio or mobility, not a hard session"
        timing = "Reassess tomorrow once HRV and deep sleep recover"
        if ctx.chronotype.typical_sleep_onset:
            timing = f"{timing}; protect your {ctx.chronotype.typical_sleep_onset} wind-down tonight"
        rationale = f"{driver.metric.lower()}: {driver.interpretation}"
        expected = "Protecting today should pull HRV back toward baseline within 24-48 h"
        chat = f"Hold back today. {_cap(driver.interpretation)}. Keep it low-intensity, and we reassess tomorrow."
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

    chat, expected = _apply_profile(chat, expected, ctx)

    if not ctx.has_training_history and "training" not in restricted:
        actions = actions[:2] + ["Tell ARIA your last workout"]
        chat = f"{chat} I don't have your recent training load yet — what and when was your last real session?"

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


def _insight_response(
    message: str, ctx: ARIAContext, signals: list[Signal], restricted: list[str], voice_mode: bool
) -> dict[str, Any]:
    confidence, reason = _calibrate_confidence(ctx, signals, restricted)
    focus = _focus_domain(message)
    focus_signal = _signal_for_domain(signals, focus)

    # If they asked about a domain that's turned off, say so — don't quietly
    # answer a different question with whatever data we happen to have.
    if focus and focus_signal is None and focus in restricted:
        prose = f"Your {focus} data is turned off for ARIA, so I can't read it. Turn it on and I'll break it down."
        return _envelope(
            response_type="clarification",
            confidence=0.2,
            confidence_reason=f"{focus} restricted by permission",
            prose_summary=prose,
            card=None if voice_mode else {"question": prose, "why": f"{focus} restricted by permission"},
            message=prose,
            suggested_actions=["Review data permissions", "Ask about something else"],
            voice_mode=voice_mode,
        )

    # Answer what was asked: prefer the signal for the focus domain, then fall
    # back to the highest-priority signal.
    lead = focus_signal or (signals[0] if signals else None)
    if lead is None:
        return _clarification_response(ctx, restricted, voice_mode)

    chat = f"{lead.metric}: {lead.current_value} ({lead.vs_baseline}). {_cap(lead.interpretation)}."
    prose = f"{lead.metric}: {lead.current_value}. {_cap(lead.interpretation)}."
    card = None if voice_mode else {
        "metric": lead.metric,
        "current_value": lead.current_value,
        "vs_baseline": lead.vs_baseline,
        "interpretation": lead.interpretation,
        "priority": lead.priority,
    }
    return _envelope(
        response_type="insight",
        confidence=confidence,
        confidence_reason=reason,
        prose_summary=prose,
        card=card,
        message=chat,
        suggested_actions=["What should I do about it?", "Show the trend", "Compare to last week"],
        voice_mode=voice_mode,
    )


def _summary_response(
    ctx: ARIAContext, signals: list[Signal], restricted: list[str], voice_mode: bool
) -> dict[str, Any]:
    p = ctx.progress
    if not ctx.has_progress:
        return _clarification_response(ctx, restricted, voice_mode)

    confidence, reason = _calibrate_confidence(ctx, signals, restricted)
    facts: list[str] = []
    if p.workouts_completed_30d is not None:
        facts.append(f"{p.workouts_completed_30d} workouts in 30 days")
    if p.new_personal_records:
        facts.append(f"{p.new_personal_records} new PR{'s' if p.new_personal_records != 1 else ''}")
    if p.training_load_trend:
        facts.append(f"load {p.training_load_trend}")
    headline = "; ".join(facts) or "limited progress data"

    trend = (p.training_load_trend or "steady").lower()
    if trend == "rising":
        risk = "Load is climbing — schedule a deload before fatigue outpaces adaptation."
    elif trend == "falling":
        risk = "Load is drifting down — add one quality session to hold momentum."
    else:
        risk = "Load is steady — vary the stimulus so you don't plateau."

    if p.new_personal_records:
        win = f"{p.new_personal_records} PR{'s' if p.new_personal_records != 1 else ''} this block — strength is moving."
    elif p.workouts_completed_30d is not None:
        win = f"You logged {p.workouts_completed_30d} sessions — consistency is the win."
    else:
        win = "You're showing up — that's the foundation."

    goal = ctx.profile.primary_goal
    rec = "Hold the structure and progress one variable next block."
    if goal in _GOAL_FOCUS:
        rec = f"Next block: bias toward your {goal} goal — {_GOAL_FOCUS[goal]}."

    prose = f"Last 30 days: {headline}. {win}"
    chat = f"{prose} {risk}"
    card = None if voice_mode else {
        "period_days": 30,
        "headline": headline,
        "win": win,
        "risk": risk,
        "recommendation": rec,
    }
    return _envelope(
        response_type="summary",
        confidence=confidence,
        confidence_reason=reason,
        prose_summary=prose,
        card=card,
        message=chat,
        suggested_actions=["Plan next block", "Show load chart", "Review PRs"],
        voice_mode=voice_mode,
    )


def generate_response(
    message: str,
    ctx: ARIAContext,
    *,
    permissions: DataPermissions | None = None,
    voice_mode: bool = False,
) -> dict[str, Any]:
    """Top-level entry: message + context (+ permissions) -> response envelope."""
    perms = permissions if isinstance(permissions, DataPermissions) else DataPermissions.allow_all()
    ctx, restricted = apply_permissions(ctx, perms)

    response_type = classify_request(message, ctx)
    signals = _gather_signals(ctx)

    if response_type == "clarification":
        envelope = _clarification_response(ctx, restricted, voice_mode)
    elif response_type == "summary":
        envelope = _summary_response(ctx, signals, restricted, voice_mode)
    elif response_type == "recommendation":
        envelope = _recommendation_response(message, ctx, signals, restricted, voice_mode)
    else:
        envelope = _insight_response(message, ctx, signals, restricted, voice_mode)

    envelope["restricted_domains"] = restricted
    return envelope


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
    """Assemble the response envelope.

    Spec fields are canonical; ``message``/``suggested_actions`` are kept for the
    deployed chat client. In voice mode the card is suppressed and prose is used.
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
        "restricted_domains": [],
        # --- compatibility layer for the deployed chat surface ---
        "message": message,
        "suggested_actions": suggested_actions,
        "model": select_model(response_type, voice_mode=voice_mode),
    }


def build_user_prompt(message: str, ctx: ARIAContext, restricted: list[str] | None = None) -> str:
    """User-turn prompt for the Bedrock path: question + injected context."""
    return f"{ctx.user_model_block(restricted)}\n\n[USER MESSAGE]\n{message.strip()}"


# --- Live reasoning path (Section 4 — Bedrock) -------------------------------
#
# ``generate_response`` above is the deterministic core. This layer wraps it with
# a real Claude call on Amazon Bedrock: the deterministic pass still runs first
# (it classifies the request, picks the model, and provides a guaranteed,
# schema-conformant fallback), then the live model's reasoning is overlaid onto
# that envelope. Any failure — boto3 missing, network error, malformed JSON,
# empty prose — falls back to the deterministic envelope, so the endpoint never
# fails because Bedrock is unreachable. Bedrock is opt-in via ``ARIA_BEDROCK_ENABLED``
# so the default/offline path (and CI) stay hermetic.

# Concrete Bedrock model id backing each routing class. The ``anthropic.`` prefix
# is required by the Bedrock Converse API (mirrors ai_router / query_router).
LIVE_MODEL_IDS = {
    MODEL_PRIMARY: "anthropic.claude-opus-4-8",
    MODEL_FAST: "anthropic.claude-sonnet-4-6",
}
LIVE_MAX_TOKENS = 700
LIVE_TEMPERATURE = 0.3

_RESPONSE_TYPES = {"insight", "recommendation", "plan", "summary", "clarification"}
_TRUE_FLAGS = {"1", "true", "yes", "on"}

# Lazily-built Bedrock gateway, shared across invocations within a warm Lambda.
_gateway: Any = None
_gateway_lock = threading.Lock()


def bedrock_enabled() -> bool:
    """True when the live Bedrock path is turned on via env (opt-in)."""
    return os.getenv("ARIA_BEDROCK_ENABLED", "").strip().lower() in _TRUE_FLAGS


def _bedrock_model_id(model_class: str) -> str:
    return LIVE_MODEL_IDS.get(model_class, LIVE_MODEL_IDS[MODEL_FAST])


def _default_converse(model_id: str, system_prompt: str, user_prompt: str) -> str:
    """Call Bedrock via the shared gateway. boto3 is imported lazily inside the
    gateway, so this module stays import-light and the offline path never touches it."""
    global _gateway
    gateway = _gateway
    if gateway is None:
        with _gateway_lock:
            if _gateway is None:
                from ai_router import BedrockGateway  # lazy: avoids boto3 at module load

                _gateway = BedrockGateway()
            gateway = _gateway
    result = gateway.converse(
        model_id=model_id,
        system_prompt=system_prompt,
        user_prompt=user_prompt,
        max_tokens=LIVE_MAX_TOKENS,
        temperature=LIVE_TEMPERATURE,
    )
    return str(result.get("answer") or "")


def generate_response_live(
    message: str,
    ctx: ARIAContext,
    *,
    permissions: DataPermissions | None = None,
    voice_mode: bool = False,
    converse: Callable[[str, str, str], str] | None = None,
) -> dict[str, Any]:
    """Top-level entry for the live path: deterministic reasoning, then a real
    Claude pass overlaid on top. Falls back to the deterministic envelope on any
    error. ``converse`` is injectable so tests never need boto3 or AWS."""
    base = generate_response(message, ctx, permissions=permissions, voice_mode=voice_mode)
    caller = converse or _default_converse

    perms = permissions if isinstance(permissions, DataPermissions) else DataPermissions.allow_all()
    sanitized, restricted = apply_permissions(ctx, perms)
    model_id = _bedrock_model_id(select_model(base["response_type"], voice_mode=voice_mode))

    user_prompt = build_user_prompt(message, sanitized, restricted)
    if voice_mode:
        user_prompt += f"\n\n[VOICE MODE] Reply with prose only (no card), {VOICE_TOKEN_CAP} tokens max."

    try:
        text = caller(model_id, ARIA_SYSTEM_PROMPT, user_prompt)
        data = _parse_model_envelope(text)
        prose = str(data.get("prose_summary") or "").strip()
        if not prose:
            raise ValueError("model response missing prose_summary")
    except Exception as exc:  # noqa: BLE001 — any failure must degrade, never raise
        fallback = dict(base)
        fallback["reasoning_source"] = "deterministic"
        fallback["reasoning_error"] = str(exc) or exc.__class__.__name__
        return fallback

    return _merge_live_envelope(base, data, prose, model_id, voice_mode)


def _merge_live_envelope(
    base: dict[str, Any], data: dict[str, Any], prose: str, model_id: str, voice_mode: bool
) -> dict[str, Any]:
    """Overlay the model's reasoning onto the deterministic envelope. The
    deterministic skeleton guarantees every field is present and schema-conformant;
    only validated model fields replace it."""
    merged = dict(base)
    merged["prose_summary"] = prose

    response_type = data.get("response_type")
    if response_type in _RESPONSE_TYPES:
        merged["response_type"] = response_type

    confidence = _coerce_confidence(data.get("confidence"))
    if confidence is not None:
        merged["confidence"] = confidence

    reason = data.get("confidence_reason")
    if isinstance(reason, str) and reason.strip():
        merged["confidence_reason"] = reason.strip()

    recommendation = data.get("recommendation")
    if isinstance(recommendation, str) and recommendation.strip():
        merged["recommendation"] = recommendation.strip()

    if voice_mode:
        merged["card"] = None
    else:
        model_card = data.get("card")
        if isinstance(model_card, dict):
            base_card = base.get("card")
            merged["card"] = {**base_card, **model_card} if isinstance(base_card, dict) else model_card

    # The model's prose is the natural-language answer for both chat and voice.
    merged["message"] = prose
    merged["model"] = model_id
    merged["reasoning_source"] = "bedrock"
    return merged


def _parse_model_envelope(text: str) -> dict[str, Any]:
    """Best-effort extraction of the JSON envelope from a model response."""
    cleaned = re.sub(r"```(?:json)?", "", text or "").replace("```", "").strip()
    start, end = cleaned.find("{"), cleaned.rfind("}")
    if start != -1 and end > start:
        cleaned = cleaned[start:end + 1]
    try:
        data = json.loads(cleaned)
    except (ValueError, TypeError):
        return {}
    return data if isinstance(data, dict) else {}


def _coerce_confidence(value: Any) -> float | None:
    """Clamp a model-supplied confidence to [0, 1]; None when not a number."""
    if isinstance(value, bool) or value is None:
        return None
    try:
        return max(0.0, min(1.0, float(value)))
    except (TypeError, ValueError):
        return None


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


def _str_list(value: Any) -> list[str]:
    if not isinstance(value, (list, tuple)):
        return []
    return [s for s in (_str(item) for item in value) if s]


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
