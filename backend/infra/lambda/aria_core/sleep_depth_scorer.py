"""Sleep depth score — versus this person's own nights, blended with
chronotype targets until the personal baseline is thick enough to trust.

Python port of ForgeCore's ``SleepDepthScorer.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/SleepDepthScorer.swift``),
kept numerically identical to it. Every constant and formula below cites the
exact Swift source line range it mirrors.

Cold start (fewer than ``COLD_START_NIGHTS`` observed nights) scores purely
against population chronotype targets, since there is not yet enough signal
to know what is normal *for this person*. From there the score blends
linearly toward a fully personal baseline (z-scored against this person's
own running mean/spread) as more nights are observed, reaching 100% personal
at ``FULL_PERSONAL_NIGHTS``. ``unusual_flags`` explain *why* a night scored
low/high in the person's own terms ("shorter than your usual night"), not
population terms -- see ``SleepDepthScorerTests.swift``'s own
``testFlagsStayQualitativeWithNoStagePercent`` for why these stay
qualitative (no raw percentages or stage minutes leak into the copy).

Depends on ``aria_core.biometrics.statistics.OnlineStat`` (Welford running
mean/variance + EWMA), the same dependency ``OnlineStat.swift`` names in its
own docstring ("Mirrors ... so on-device sleep depth and the Lambda recovery
path share one definition of 'unusual for you'"). Porting this module
surfaced a real divergence from that stated contract: Python's
``OnlineStat.zscore()`` returned a flat 0.0 whenever spread was near-zero
(e.g. a dead-flat baseline of identical nights), while Swift's returns a
large-magnitude signed z so an outlier against zero spread still reads as
unusual -- ``OnlineStatTests.testSingleSampleHasZeroSpread`` pins exactly
this case. Fixed at the source (``aria_core/biometrics/statistics.py``)
rather than worked around here, since every other ``OnlineStat`` caller
inherits the same fix.

Not ported: ``SleepDepthBaselineStore`` (UserDefaults persistence, iOS-only
-- same reasoning as ``QualityOfLifeLivingStore`` in ``quality_of_life.py``).
This module's own ``SleepDepthBaselines`` is a plain in-memory value; a
caller wanting durable storage supplies its own (e.g. DynamoDB, the way
every other ``aria_core`` module keeps storage coupling out of the pure
scoring logic).

Stdlib only (aside from the sibling ``aria_core.biometrics.statistics``
import). Deterministic. Pure -- no I/O.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .biometrics.statistics import OnlineStat

# --- Tunables ----------------------------------------------------------------
# Mirrors SleepDepthScorer's static lets (Swift L91-94).

COLD_START_NIGHTS = 5
FULL_PERSONAL_NIGHTS = 14
UNUSUAL_Z = 1.5
OBSERVED_KEY_CAP = 60


def _swift_round(value: float) -> int:
    """Swift's ``Double.rounded()`` default rule: round half away from
    zero, not Python's banker's-rounding ``round()``."""
    return int(value + 0.5) if value >= 0 else -int(-value + 0.5)


# --- Inputs ------------------------------------------------------------------
# Mirrors SleepNightMetrics (Swift L4-32).

@dataclass(frozen=True)
class SleepNightMetrics:
    """One night's numbers, stripped of HealthKit types so scoring is
    testable."""

    total_hours: float
    deep_minutes: float
    rem_minutes: float
    efficiency_percent: float
    wake_consistency: float


def efficiency_percent(asleep_hours: float, awake_minutes: float) -> float:
    """Asleep / (asleep + awake). Mirrors
    ``SleepNightMetrics.efficiencyPercent(asleepHours:awakeMinutes:)``
    (Swift L26-31)."""
    asleep = max(0.0, asleep_hours * 60)
    bed = asleep + max(0.0, awake_minutes)
    if bed <= 0:
        return 0.0
    return min(100.0, max(0.0, (asleep / bed) * 100))


@dataclass(frozen=True)
class SleepChronotypeTargets:
    """Mirrors SleepChronotypeTargets (Swift L34-44)."""

    target_hours: float
    deep_goal_minutes: float
    rem_goal_minutes: float


# --- Baselines -----------------------------------------------------------
# Mirrors SleepDepthBaselines (Swift L47-69): per-person running stats,
# cold start empty, `observe` fills them.

@dataclass
class SleepDepthBaselines:
    duration: OnlineStat = field(default_factory=OnlineStat)
    deep: OnlineStat = field(default_factory=OnlineStat)
    rem: OnlineStat = field(default_factory=OnlineStat)
    efficiency: OnlineStat = field(default_factory=OnlineStat)
    observed_night_keys: list[str] = field(default_factory=list)

    @property
    def sample_count(self) -> int:
        return self.duration.n


@dataclass(frozen=True)
class SleepDepthResult:
    """Mirrors SleepDepthResult (Swift L71-86)."""

    score: int
    # 0 = chronotype formula only, 1 = fully personal.
    personal_blend: float
    unusual_flags: list[str]
    source: str

    @property
    def headline(self) -> str | None:
        return self.unusual_flags[0] if self.unusual_flags else None


# --- Scoring -----------------------------------------------------------------
# Mirrors chronotypeScore/score (Swift L96-141).

def chronotype_score(metrics: SleepNightMetrics, targets: SleepChronotypeTargets) -> int:
    """Score against population chronotype targets alone -- what cold start
    falls back to, and what every score blends away from as the personal
    baseline fills in."""
    duration = min(100.0, (metrics.total_hours / max(0.1, targets.target_hours)) * 100)
    deep = min(100.0, (metrics.deep_minutes / max(1.0, targets.deep_goal_minutes)) * 100)
    rem = min(100.0, (metrics.rem_minutes / max(1.0, targets.rem_goal_minutes)) * 100)
    weighted = (
        duration * 0.35
        + deep * 0.25
        + rem * 0.20
        + min(100.0, max(0.0, metrics.efficiency_percent)) * 0.15
        + min(100.0, max(0.0, metrics.wake_consistency)) * 0.05
    )
    return min(100, max(0, _swift_round(weighted)))


def score(metrics: SleepNightMetrics, targets: SleepChronotypeTargets,
          baselines: SleepDepthBaselines) -> SleepDepthResult:
    chrono = float(chronotype_score(metrics, targets))
    n = baselines.sample_count
    if n < COLD_START_NIGHTS:
        blend = 0.0
    else:
        blend = min(1.0, (n - (COLD_START_NIGHTS - 1)) / (FULL_PERSONAL_NIGHTS - (COLD_START_NIGHTS - 1)))
    personal = _personal_score(metrics, baselines)
    mixed = chrono * (1 - blend) + personal * blend
    flags = _unusual_flags(metrics, baselines)
    if blend <= 0:
        source = "chronotype"
    elif blend >= 1:
        source = "personal"
    else:
        source = "blended"
    return SleepDepthResult(
        score=min(100, max(0, _swift_round(mixed))),
        personal_blend=blend,
        unusual_flags=flags,
        source=source,
    )


def observe(baselines: SleepDepthBaselines, metrics: SleepNightMetrics, night_key: str) -> None:
    """Fold a finished night into the baseline, in place. Same `night_key`
    is a no-op so HealthKit refreshes do not double-count."""
    key = night_key.strip()
    if not key:
        return
    if key in baselines.observed_night_keys:
        return
    baselines.duration.update(metrics.total_hours)
    baselines.deep.update(metrics.deep_minutes)
    baselines.rem.update(metrics.rem_minutes)
    baselines.efficiency.update(metrics.efficiency_percent)
    baselines.observed_night_keys.append(key)
    if len(baselines.observed_night_keys) > OBSERVED_KEY_CAP:
        extra = len(baselines.observed_night_keys) - OBSERVED_KEY_CAP
        del baselines.observed_night_keys[:extra]


def _personal_score(metrics: SleepNightMetrics, baselines: SleepDepthBaselines) -> float:
    duration = _component(metrics.total_hours, baselines.duration, higher_is_better=True)
    deep = _component(metrics.deep_minutes, baselines.deep, higher_is_better=True)
    rem = _component(metrics.rem_minutes, baselines.rem, higher_is_better=True)
    efficiency = _component(metrics.efficiency_percent, baselines.efficiency, higher_is_better=True)
    return (
        duration * 0.35
        + deep * 0.25
        + rem * 0.20
        + efficiency * 0.15
        + min(100.0, max(0.0, metrics.wake_consistency)) * 0.05
    )


def _component(value: float, stat: OnlineStat, higher_is_better: bool) -> float:
    """Mean maps to 80, +1 SD to 95, -1 SD to 65."""
    if stat.n < 2:
        return 80.0
    z = stat.zscore(value)
    signed = z if higher_is_better else -z
    return min(100.0, max(0.0, 80 + signed * 15))


def _unusual_flags(metrics: SleepNightMetrics, baselines: SleepDepthBaselines) -> list[str]:
    if baselines.sample_count < COLD_START_NIGHTS:
        return []
    flags: list[str] = []

    def note(stat: OnlineStat, value: float, low: str, high: str) -> None:
        z = stat.zscore(value)
        if z <= -UNUSUAL_Z:
            flags.append(low)
        elif z >= UNUSUAL_Z:
            flags.append(high)

    note(baselines.duration, metrics.total_hours,
         low="Shorter than your usual night", high="Longer than your usual night")
    note(baselines.deep, metrics.deep_minutes,
         low="Less deep sleep than you usually get", high="More deep sleep than is usual for you")
    note(baselines.rem, metrics.rem_minutes,
         low="Less REM than you usually get", high="More REM than is usual for you")
    note(baselines.efficiency, metrics.efficiency_percent,
         low="More time awake than is usual for you", high="You stayed asleep more steadily than usual")
    return flags
