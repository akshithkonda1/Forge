"""Quality of Life — holistic, multi-aspect life score.

Python port of ForgeCore's ``QualityOfLifeCalculator.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/QualityOfLifeCalculator.swift``),
kept numerically identical to it: same pillars, same weights, same response
curves, same personalized targets, same confidence model. Every constant and
formula below has a citation back to the Swift source it mirrors, so a
divergence is easy to spot on either side.

Ported: the pure scoring algorithm only (``score()`` and everything the
Swift file marks "Pillars" / "Signal combination" / "Response curves" /
"Personalized targets"). Not ported, deliberately: ``QualityOfLifeLivingStore``
(UserDefaults persistence — an iOS-only concern), ``isQuestion``/
``coachingLine`` (chat-phrase detection and randomized-variety text
selection — production already narrates its own lifestyle signal via
``aria_engine.life_rhythm_training_plan``/``LifestyleContext``, so porting a
second, differently-worded narrator would duplicate rather than consolidate
intelligence), and ``QualityOfLifeBand.color`` (SwiftUI-only).

Grades life across seven independent pillars — sleep, activity, nutrition,
hydration, body/vitals, mind, and connection — each counted exactly once. A
missing pillar redistributes its weight and lowers confidence instead of
being invented, so the score is always graded on whatever aspects are known.

Stdlib only. Deterministic. Pure -- no I/O, matching every other module in
this package.

Integration note: production's ``aria_evidence.detect_pattern`` currently
treats Lifestyle QoL as **client-authored only** (see that function's
"client-authored score only" comment) — this module makes it possible for
the backend to independently compute the same score from ``ARIAContext``'s
own sleep/activity/nutrition/body signals, but does not yet wire that in.
Whether a server-computed score should replace, cross-check, or simply sit
alongside the client-authored one is a real product decision, not something
this port decides unilaterally.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field

from . import hydration_engine

# --- Pillars -------------------------------------------------------------
# Mirrors QualityOfLifePillar (Swift L30-78): weight() + maxSignals + title.

SLEEP = "sleep"
ACTIVITY = "activity"
NUTRITION = "nutrition"
HYDRATION = "hydration"
VITALS = "vitals"
MIND = "mind"
SOCIAL = "social"

PILLARS = (SLEEP, ACTIVITY, NUTRITION, HYDRATION, VITALS, MIND, SOCIAL)

# Weight in a fully-populated blend. These sum to 1.0; a pillar with no data
# redistributes its weight over the pillars that do.
_PILLAR_WEIGHT: dict[str, float] = {
    SLEEP: 0.22,
    ACTIVITY: 0.18,
    NUTRITION: 0.15,
    VITALS: 0.15,
    MIND: 0.12,
    SOCIAL: 0.10,
    HYDRATION: 0.08,
}

# Number of distinct signals the pillar can be measured from -- used to
# express how deeply a pillar was covered (present signals / this).
_PILLAR_MAX_SIGNALS: dict[str, int] = {
    SLEEP: 3,      # duration, deep, REM
    ACTIVITY: 3,   # steps, active calories, exercise minutes
    NUTRITION: 4,  # protein, calories, fibre, added sugar
    VITALS: 5,     # HRV, resting HR, VO2max, SpO2, respiration
    MIND: 5,       # mindful, stress, mood, weekly mood, work strain
    SOCIAL: 3,     # felt connection, meaningful interactions, calendar load
    HYDRATION: 1,  # intake vs need
}

PILLAR_TITLE: dict[str, str] = {
    SLEEP: "Sleep",
    ACTIVITY: "Activity",
    NUTRITION: "Nutrition",
    HYDRATION: "Hydration",
    VITALS: "Body & Vitals",
    MIND: "Mind & Stress",
    SOCIAL: "Connection",
}

# --- Archetype-remapped weights -------------------------------------------
# Mirrors QualityOfLifePersona.weight(for:) (Swift L135-160). "unset" and
# "balanced" both use the population _PILLAR_WEIGHT table unchanged.

_ARCHETYPE_WEIGHT: dict[str, dict[str, float]] = {
    "homebody": {
        SLEEP: 0.28,
        NUTRITION: 0.22,
        MIND: 0.16,
        SOCIAL: 0.12,
        VITALS: 0.08,
        HYDRATION: 0.08,
        ACTIVITY: 0.06,
    },
    "outdoors": {
        ACTIVITY: 0.24,
        VITALS: 0.18,
        NUTRITION: 0.16,
        SLEEP: 0.14,
        MIND: 0.12,
        SOCIAL: 0.10,
        HYDRATION: 0.06,
    },
}


def persona_weight(archetype: str, pillar: str) -> float:
    table = _ARCHETYPE_WEIGHT.get(archetype)
    if table is None:
        return _PILLAR_WEIGHT[pillar]
    return table[pillar]


# --- Band ------------------------------------------------------------------
# Mirrors QualityOfLifeBand (Swift L480-521): score thresholds + label +
# supportiveDescriptor. `.color` (SwiftUI) is not ported.

def band_for_score(score: int) -> str:
    if score >= 85:
        return "thriving"
    if score >= 70:
        return "steady"
    if score >= 50:
        return "strained"
    return "depleted"


BAND_LABEL: dict[str, str] = {
    "thriving": "Thriving",
    "steady": "Steady",
    "strained": "Strained",
    "depleted": "Depleted",
}

BAND_SUPPORTIVE_DESCRIPTOR: dict[str, str] = {
    "thriving": "Life is in a good rhythm right now — protect what's working.",
    "steady": "A solid, balanced stretch. Small steady wins keep it here.",
    "strained": "A few areas are asking for attention. Pick one to ease first.",
    "depleted": "Several signals are low. Be gentle — recovery is the work today.",
}


# --- Inputs ------------------------------------------------------------------
# Mirrors QualityOfLifeInputs (Swift L526-632). Every signal is optional; the
# calculator scores whatever is present and reports how much of life that
# covered. Field names keep Swift's units in the name (Hours, Minutes, Grams,
# ...) rather than translating to snake_case-only, so a value's unit is never
# ambiguous when read next to the Swift source.

@dataclass
class QualityOfLifeInputs:
    # Sleep
    sleep_hours: float | None = None
    deep_sleep_minutes: float | None = None
    rem_sleep_minutes: float | None = None
    # Activity
    steps: int | None = None
    active_calories: int | None = None
    exercise_minutes: float | None = None
    # Nutrition
    protein_grams: float | None = None
    total_calories: int | None = None
    fiber_grams: float | None = None
    added_sugar_grams: float | None = None
    # Hydration
    water_glasses: float | None = None
    # Body / vitals
    hrv_ms: float | None = None
    hrv_baseline_ms: float | None = None
    resting_hr: float | None = None
    resting_hr_baseline: float | None = None
    vo2_max: float | None = None
    oxygen_saturation_percent: float | None = None
    respiratory_rate: float | None = None
    # Mind
    mindful_minutes: float | None = None
    stress_level_0to1: float | None = None  # 0 = calm, 1 = maximally stressed
    self_reported_mood_0to10: float | None = None
    # Connection
    social_connection_0to10: float | None = None
    meaningful_social_interactions: int | None = None
    # Life context
    calendar_busyness_0to1: float | None = None
    weekly_mood_0to10: float | None = None
    sleep_need_preference_hours: float | None = None
    work_strain_0to10: float | None = None
    # Personalization (population defaults used when absent)
    body_mass_kg: float | None = None
    age: int | None = None
    biological_sex_female: bool | None = None


# --- Score -------------------------------------------------------------------
# Mirrors QualityOfLifeScore (Swift L634-671): overall/rawOverall/confidence/
# pillarScores plus band/isEstimate/gradedAspects/score(for:)/smoothed(...).

@dataclass
class QualityOfLifeScore:
    overall: int
    raw_overall: int
    confidence: float
    pillar_scores: dict[str, int] = field(default_factory=dict)

    @property
    def band(self) -> str:
        return band_for_score(self.overall)

    @property
    def is_estimate(self) -> bool:
        return self.confidence < 0.5

    @property
    def graded_aspects(self) -> int:
        return len(self.pillar_scores)

    def score_for(self, pillar: str) -> int | None:
        return self.pillar_scores.get(pillar)

    def smoothed(self, previous_overall: int | None, alpha: float = 0.6) -> "QualityOfLifeScore":
        """Blend with a previous day's overall so a single noisy day doesn't
        swing the score. Smoothing is scaled by confidence: a low-confidence
        day moves the trend less. No previous value -> returned unchanged."""
        if previous_overall is None:
            return self
        effective_alpha = min(1.0, max(0.0, alpha)) * max(0.35, self.confidence)
        blended = self.raw_overall * effective_alpha + previous_overall * (1 - effective_alpha)
        return QualityOfLifeScore(
            overall=round(blended),
            raw_overall=self.raw_overall,
            confidence=self.confidence,
            pillar_scores=dict(self.pillar_scores),
        )


# --- Signal combination -------------------------------------------------------
# Mirrors the private Signal/PillarResult/combine (Swift L849-872).

def _clamp(value: float, lo: float, hi: float) -> float:
    return min(max(value, lo), hi)


@dataclass(frozen=True)
class _Signal:
    value: float
    weight: float


@dataclass(frozen=True)
class _PillarResult:
    score: float
    depth: float


def _combine(signals: list[_Signal], max_signals: int) -> _PillarResult | None:
    if not signals:
        return None
    total_weight = sum(s.weight for s in signals)
    if total_weight <= 0:
        return None
    score = sum(s.value * s.weight for s in signals) / total_weight
    depth = len(signals) / max(1, max_signals)
    return _PillarResult(score=score, depth=depth)


# --- Response curves -----------------------------------------------------
# Mirrors rising/optimum/descending (Swift L874-896) exactly, constant for
# constant.

def rising(ratio: float) -> float:
    """"More is better" with diminishing returns and a soft cap. Concave up
    to the target (r = 1 -> 100), then a gentle penalty for gross overshoot
    so a data glitch or over-training does not read as perfect."""
    if ratio <= 0:
        return 0.0
    if ratio <= 1:
        return 100.0 * (1 - (1 - ratio) * (1 - ratio))
    return max(100.0 - (ratio - 1) * 20.0, 60.0)


def optimum(ratio: float, sigma: float) -> float:
    """Inverted-U for signals with a real optimum (sleep duration, calories,
    respiration): best at the target, worse on either side. Gaussian falloff."""
    d = ratio - 1
    return _clamp(100.0 * math.exp(-(d * d) / (2 * sigma * sigma)), 0, 100)


def descending(value: float, zero_at: float) -> float:
    """"Less is better": full marks at 0, zero at `zero_at`, linear between."""
    if zero_at <= 0:
        return 0.0
    return _clamp(100.0 * (1 - value / zero_at), 0, 100)


# --- Personalized targets -------------------------------------------------
# Mirrors sleepNeedHours/proteinTargetGrams/calorieTarget (Swift L900-916).

def _sleep_need_hours(age: int | None, preference: float | None = None) -> float:
    if preference is not None and 4 <= preference <= 11:
        return preference
    if age is None:
        return 8.0
    if age < 18:
        return 9.0
    if age >= 65:
        return 7.5
    return 8.0


def _protein_target_grams(body_mass_kg: float | None) -> float:
    if body_mass_kg is not None and body_mass_kg > 0:
        return max(60.0, 1.6 * body_mass_kg)
    return 130.0


def _calorie_target(body_mass_kg: float | None, sex_female: bool | None) -> float:
    if body_mass_kg is not None and body_mass_kg > 0:
        return max(1_400.0, body_mass_kg * 31.0)
    return 2_000.0 if sex_female is True else 2_400.0


# --- Pillars (independent; each counted once) ------------------------------
# Mirrors sleepPillar..socialPillar (Swift L728-847) signal-for-signal,
# including every physiological-plausibility guard.

def _sleep_pillar(i: QualityOfLifeInputs) -> _PillarResult | None:
    hours = i.sleep_hours
    if hours is None or not (0 < hours <= 16):
        return None
    need = _sleep_need_hours(i.age, i.sleep_need_preference_hours)
    signals = [_Signal(optimum(hours / need, sigma=0.16), 0.70)]  # duration has a real optimum
    if i.deep_sleep_minutes is not None and 0 <= i.deep_sleep_minutes <= 360:
        signals.append(_Signal(rising(i.deep_sleep_minutes / 60.0), 0.15))
    if i.rem_sleep_minutes is not None and 0 <= i.rem_sleep_minutes <= 360:
        signals.append(_Signal(rising(i.rem_sleep_minutes / 90.0), 0.15))
    return _combine(signals, _PILLAR_MAX_SIGNALS[SLEEP])


def _activity_pillar(i: QualityOfLifeInputs) -> _PillarResult | None:
    signals: list[_Signal] = []
    if i.steps is not None and 0 <= i.steps <= 80_000:
        signals.append(_Signal(rising(i.steps / 8_000.0), 1))
    if i.active_calories is not None and 0 <= i.active_calories <= 5_000:
        signals.append(_Signal(rising(i.active_calories / 500.0), 1))
    if i.exercise_minutes is not None and 0 <= i.exercise_minutes <= 600:
        signals.append(_Signal(rising(i.exercise_minutes / 30.0), 1))
    return _combine(signals, _PILLAR_MAX_SIGNALS[ACTIVITY])


def _nutrition_pillar(i: QualityOfLifeInputs) -> _PillarResult | None:
    signals: list[_Signal] = []
    if i.protein_grams is not None and 0 <= i.protein_grams <= 500:
        signals.append(_Signal(rising(i.protein_grams / _protein_target_grams(i.body_mass_kg)), 0.35))
    if i.total_calories is not None and 0 < i.total_calories <= 12_000:
        target = _calorie_target(i.body_mass_kg, i.biological_sex_female)
        signals.append(_Signal(optimum(i.total_calories / target, sigma=0.22), 0.35))  # adequacy, not "more"
    if i.fiber_grams is not None and 0 <= i.fiber_grams <= 150:
        signals.append(_Signal(rising(i.fiber_grams / 30.0), 0.15))
    if i.added_sugar_grams is not None and 0 <= i.added_sugar_grams <= 500:
        signals.append(_Signal(descending(i.added_sugar_grams, zero_at=60), 0.15))  # less is better
    return _combine(signals, _PILLAR_MAX_SIGNALS[NUTRITION])


def _hydration_pillar(i: QualityOfLifeInputs) -> _PillarResult | None:
    glasses = i.water_glasses
    if glasses is None or not (0 <= glasses <= 40):
        return None
    # QoL calls HydrationEngine's bare weight-only overload (activeCalories=0,
    # cycle=.none, hotEnvironment=false) -- see quality_of_life.swift's own
    # call site. Now that hydration_engine.py exists (a full, separately
    # tested port), this calls the real functions instead of duplicating
    # their formula.
    target_ml = hydration_engine.target_milliliters(i.body_mass_kg)
    need_glasses = max(1.0, hydration_engine.glasses_from_milliliters(target_ml))
    return _combine([_Signal(rising(glasses / need_glasses), 1)], _PILLAR_MAX_SIGNALS[HYDRATION])


def _vitals_pillar(i: QualityOfLifeInputs) -> _PillarResult | None:
    signals: list[_Signal] = []
    if i.hrv_ms is not None and 0 < i.hrv_ms <= 250:
        if i.hrv_baseline_ms is not None and i.hrv_baseline_ms > 0:
            # Scored against the person's own baseline: +-30% -> 50...100.
            signals.append(_Signal(
                _clamp(75 + (i.hrv_ms / i.hrv_baseline_ms - 1.0) / 0.30 * 25, 0, 100), 0.30,
            ))
        else:
            signals.append(_Signal(rising(i.hrv_ms / 55.0), 0.30))
    if i.resting_hr is not None and 25 <= i.resting_hr <= 150:
        if i.resting_hr_baseline is not None and i.resting_hr_baseline > 0:
            signals.append(_Signal(
                _clamp(80 - (i.resting_hr - i.resting_hr_baseline) / i.resting_hr_baseline / 0.15 * 30, 0, 100),
                0.30,
            ))
        else:
            # Age-graded expectation: a resting HR near ~55 is excellent.
            signals.append(_Signal(descending(max(0.0, i.resting_hr - 45), zero_at=55), 0.30))
    if i.vo2_max is not None and 0 < i.vo2_max <= 90:
        signals.append(_Signal(rising((i.vo2_max - 20) / (55 - 20)), 0.18))
    if i.oxygen_saturation_percent is not None and 50 <= i.oxygen_saturation_percent <= 100:
        signals.append(_Signal(_clamp((i.oxygen_saturation_percent - 90) / (99 - 90), 0, 1) * 100, 0.12))
    if i.respiratory_rate is not None and 4 <= i.respiratory_rate <= 40:
        signals.append(_Signal(optimum(i.respiratory_rate / 15.0, sigma=0.20), 0.10))  # ~15 breaths/min optimum
    return _combine(signals, _PILLAR_MAX_SIGNALS[VITALS])


def _mind_pillar(i: QualityOfLifeInputs) -> _PillarResult | None:
    signals: list[_Signal] = []
    if i.mindful_minutes is not None and 0 <= i.mindful_minutes <= 600:
        signals.append(_Signal(rising(i.mindful_minutes / 10.0), 1))
    if i.stress_level_0to1 is not None:
        signals.append(_Signal(_clamp(1 - i.stress_level_0to1, 0, 1) * 100, 1))
    if i.self_reported_mood_0to10 is not None:
        signals.append(_Signal(rising(i.self_reported_mood_0to10 / 10.0), 1))
    if i.weekly_mood_0to10 is not None and 0 <= i.weekly_mood_0to10 <= 10:
        signals.append(_Signal(rising(i.weekly_mood_0to10 / 10.0), 1.2))
    if i.work_strain_0to10 is not None and 0 <= i.work_strain_0to10 <= 10:
        signals.append(_Signal(_clamp(1 - i.work_strain_0to10 / 10.0, 0, 1) * 100, 0.9))
    return _combine(signals, _PILLAR_MAX_SIGNALS[MIND])


def _social_pillar(i: QualityOfLifeInputs) -> _PillarResult | None:
    signals: list[_Signal] = []
    if i.social_connection_0to10 is not None:
        signals.append(_Signal(rising(i.social_connection_0to10 / 10.0), 1))
    if i.meaningful_social_interactions is not None and i.meaningful_social_interactions >= 0:
        signals.append(_Signal(_clamp(25 + i.meaningful_social_interactions * 20, 0, 100), 1))
    if i.calendar_busyness_0to1 is not None and 0 <= i.calendar_busyness_0to1 <= 1:
        # A packed week without felt connection is strain, not thriving.
        connection = (i.social_connection_0to10 if i.social_connection_0to10 is not None else 5.0) / 10.0
        load = _clamp(100 * (1 - i.calendar_busyness_0to1) * (0.45 + 0.55 * connection), 0, 100)
        signals.append(_Signal(load, 0.8))
    return _combine(signals, _PILLAR_MAX_SIGNALS[SOCIAL])


_PILLAR_FUNCS = {
    SLEEP: _sleep_pillar,
    ACTIVITY: _activity_pillar,
    NUTRITION: _nutrition_pillar,
    HYDRATION: _hydration_pillar,
    VITALS: _vitals_pillar,
    MIND: _mind_pillar,
    SOCIAL: _social_pillar,
}


# --- Public entry point ---------------------------------------------------
# Mirrors QualityOfLifeCalculator.score(from:persona:) (Swift L678-724).

def score(inputs: QualityOfLifeInputs, archetype: str = "balanced") -> QualityOfLifeScore:
    """Blend every pillar that has data, weighting each by its share and
    renormalizing over what is present. Absence of a signal lowers
    confidence, never the score."""
    scores: dict[str, float] = {}
    depths: dict[str, float] = {}

    for pillar in PILLARS:
        result = _PILLAR_FUNCS[pillar](inputs)
        if result is None:
            continue
        scores[pillar] = _clamp(result.score, 0, 100)
        depths[pillar] = _clamp(result.depth, 0, 1)

    coverage = sum(persona_weight(archetype, p) for p in scores)
    if coverage <= 0:
        # Nothing measured yet -- reported honestly, never fabricated.
        return QualityOfLifeScore(overall=0, raw_overall=0, confidence=0.0, pillar_scores={})

    blended = sum(v * persona_weight(archetype, p) for p, v in scores.items()) / coverage
    # Confidence rewards both breadth (which pillars) and depth (how fully
    # each was measured). A pillar with any signal is already informative,
    # so presence earns 60% of its weight and full depth earns the rest --
    # shallow coverage still reads as an estimate without being punitive.
    confidence = sum(
        persona_weight(archetype, p) * (0.6 + 0.4 * depths.get(p, 0.0)) for p in scores
    )

    rounded = {p: round(v) for p, v in scores.items()}
    overall = round(_clamp(blended, 0, 100))
    return QualityOfLifeScore(
        overall=overall,
        raw_overall=overall,
        confidence=_clamp(confidence, 0, 1),
        pillar_scores=rounded,
    )
