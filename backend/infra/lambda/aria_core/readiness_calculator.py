"""On-device readiness score — the Watch/Home glance, not the dashboard seed.

Python port of ForgeCore's ``ReadinessCalculator`` in ``Readiness.swift``.
``services/readiness.py`` builds its dashboard number from this same formula
over persisted sleep rows; this module is the shared formula both native
clients should call (or receive from ``shared_intelligence``) so iOS and
Android do not drift.

HRV and resting HR are scored against the person's own normal range, not a
population table and not a fixed ±% band: HRV as a z-score of ln(HRV) against
the personal ln-baseline (HRV is log-normal, so ±20% is not symmetric in ms),
resting HR as a z-score in bpm. When a baseline's spread is unknown, a typical
day-to-day spread stands in until enough history exists.

Missing components redistribute their weight and lower confidence instead
of dragging the score down — absence of data is not evidence of poor recovery.
"""

from __future__ import annotations

import math
from dataclasses import dataclass


def _clamp(value: float, lower: float, upper: float) -> float:
    return min(max(value, lower), upper)


def _swift_round(value: float) -> int:
    return int(math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5))


# Home band vocabulary — shared/readiness.json and ForgeCore's
# HomeReadinessTokens. Not Primed / Ready / Moderate / Recovery.
PEAK = "peak"
GOOD = "good"
FAIR = "fair"
LOW = "low"

BAND_MIN_SCORE = {PEAK: 85, GOOD: 70, FAIR: 50, LOW: 0}

BAND_LABEL = {
    PEAK: "Peak",
    GOOD: "Good",
    FAIR: "Fair",
    LOW: "Low",
}

BAND_DESCRIPTOR = {
    PEAK: "You're at Peak. A full session fits if you want it.",
    GOOD: "You're at Good. A solid session still makes you someone who trains.",
    FAIR: "You're at Fair. Train smart — a lighter win still counts.",
    LOW: "You're at Low. A lighter win still makes today count.",
}


def band_for_score(score: int) -> str:
    if score >= BAND_MIN_SCORE[PEAK]:
        return PEAK
    if score >= BAND_MIN_SCORE[GOOD]:
        return GOOD
    if score >= BAND_MIN_SCORE[FAIR]:
        return FAIR
    return LOW


# Typical day-to-day spread used until a personal one is known. ln(HRV)
# between-day SD on wrist SDNN/RMSSD sits around 0.2-0.3; resting HR around
# 2-4 bpm. Floors stop a suspiciously tight history from turning a 1 ms wobble
# into a five-sigma event; ceilings stop a noisy one from flattening every day.
DEFAULT_HRV_SD_LN = 0.25
HRV_SD_LN_FLOOR = 0.08
HRV_SD_LN_CEILING = 0.6
DEFAULT_RESTING_HR_SD = 3.0
RESTING_HR_SD_FLOOR = 1.5
RESTING_HR_SD_CEILING = 8.0

# Component centers and slopes. At your own normal (z = 0) HRV scores 75 and
# resting HR 80; each SD of HRV moves 20 points, each SD of resting HR 12.
HRV_CENTER = 75.0
HRV_POINTS_PER_SD = 20.0
RESTING_HR_CENTER = 80.0
RESTING_HR_POINTS_PER_SD = 12.0


@dataclass(frozen=True)
class PersonalBaseline:
    """A personal center and day-to-day spread.

    ``log_scaled`` baselines (HRV) keep ``mean`` in original units — the
    geometric mean, exp(mean of ln) — and ``spread`` in ln units. Linear ones
    (resting HR) keep both in original units.
    """

    mean: float
    spread: float
    days: int
    log_scaled: bool

    def z_score(self, value: float, *, floor: float, ceiling: float) -> float | None:
        if value <= 0 or self.mean <= 0:
            return None
        sd = _clamp(self.spread, floor, ceiling)
        if self.log_scaled:
            return (math.log(value) - math.log(self.mean)) / sd
        return (value - self.mean) / sd


def personal_baseline(
    daily_values: list[float],
    *,
    log_scaled: bool,
    minimum_days: int = 5,
) -> PersonalBaseline | None:
    """Baseline from one value per day (the caller aggregates within a day).

    Non-positive values are missing readings, not data. ``None`` until there
    are ``minimum_days`` real days — a baseline from three nights is a guess.
    """
    values = [float(v) for v in daily_values if isinstance(v, (int, float)) and not isinstance(v, bool) and v > 0]
    if len(values) < max(2, minimum_days):
        return None
    series = [math.log(v) for v in values] if log_scaled else values
    mu = sum(series) / len(series)
    var = sum((x - mu) ** 2 for x in series) / (len(series) - 1)
    return PersonalBaseline(
        mean=math.exp(mu) if log_scaled else mu,
        spread=math.sqrt(var),
        days=len(values),
        log_scaled=log_scaled,
    )


@dataclass
class ReadinessInputs:
    hrv_ms: float | None = None
    hrv_baseline_ms: float | None = None
    # SD of ln(HRV) across days. None → DEFAULT_HRV_SD_LN.
    hrv_baseline_sd_ln: float | None = None
    resting_hr: float | None = None
    resting_hr_baseline: float | None = None
    # SD of resting HR across days, bpm. None → DEFAULT_RESTING_HR_SD.
    resting_hr_baseline_sd: float | None = None
    sleep_minutes: float | None = None
    sleep_need_minutes: float = 8 * 60
    deep_sleep_minutes: float | None = None
    rem_sleep_minutes: float | None = None
    yesterday_strain: float | None = None


@dataclass(frozen=True)
class ReadinessScore:
    overall: int
    sleep_quality: int
    recovery: int
    confidence: float

    @property
    def band(self) -> str:
        return band_for_score(self.overall)

    def to_dict(self) -> dict:
        return {
            "overall": self.overall,
            "sleepQuality": self.sleep_quality,
            "recovery": self.recovery,
            "confidence": self.confidence,
            "band": self.band,
            "label": BAND_LABEL[self.band],
            "supportiveDescriptor": BAND_DESCRIPTOR[self.band],
        }


def _sleep_score(inputs: ReadinessInputs) -> float | None:
    if inputs.sleep_minutes is None or inputs.sleep_minutes <= 0:
        return None
    need = inputs.sleep_need_minutes if inputs.sleep_need_minutes > 0 else 8 * 60
    # Sleeping past your need earns no extra credit — long sleep is at best
    # neutral, and a sudden 10-hour night is as often illness as recovery.
    duration_score = _clamp(inputs.sleep_minutes / need, 0, 1.0) * 80
    architecture_bonus = 10.0
    if inputs.deep_sleep_minutes is not None:
        architecture_bonus = _clamp(inputs.deep_sleep_minutes / 60.0, 0, 1) * 12
    if inputs.rem_sleep_minutes is not None:
        architecture_bonus += _clamp(inputs.rem_sleep_minutes / 90.0, 0, 1) * 8
    else:
        architecture_bonus += 4
    return _clamp(duration_score + architecture_bonus, 0, 100)


def hrv_component(
    hrv_ms: float | None,
    baseline_ms: float | None,
    baseline_sd_ln: float | None = None,
) -> float | None:
    """HRV vs your own normal: 75 at baseline, ±20 per SD of ln(HRV)."""
    if hrv_ms is None or baseline_ms is None or hrv_ms <= 0 or baseline_ms <= 0:
        return None
    sd = baseline_sd_ln if baseline_sd_ln is not None and baseline_sd_ln > 0 else DEFAULT_HRV_SD_LN
    z = PersonalBaseline(mean=baseline_ms, spread=sd, days=0, log_scaled=True).z_score(
        hrv_ms, floor=HRV_SD_LN_FLOOR, ceiling=HRV_SD_LN_CEILING
    )
    if z is None:
        return None
    return _clamp(HRV_CENTER + HRV_POINTS_PER_SD * z, 0, 100)


def resting_hr_component(
    resting_hr: float | None,
    baseline: float | None,
    baseline_sd: float | None = None,
) -> float | None:
    """Resting HR vs your own normal: 80 at baseline, ∓12 per SD (bpm)."""
    if resting_hr is None or baseline is None or resting_hr <= 0 or baseline <= 0:
        return None
    sd = baseline_sd if baseline_sd is not None and baseline_sd > 0 else DEFAULT_RESTING_HR_SD
    z = PersonalBaseline(mean=baseline, spread=sd, days=0, log_scaled=False).z_score(
        resting_hr, floor=RESTING_HR_SD_FLOOR, ceiling=RESTING_HR_SD_CEILING
    )
    if z is None:
        return None
    return _clamp(RESTING_HR_CENTER - RESTING_HR_POINTS_PER_SD * z, 0, 100)


def score(inputs: ReadinessInputs) -> ReadinessScore:
    weighted: list[tuple[float, float]] = []

    sleep_component = _sleep_score(inputs)
    if sleep_component is not None:
        weighted.append((sleep_component, 0.45))

    hrv_value = hrv_component(inputs.hrv_ms, inputs.hrv_baseline_ms, inputs.hrv_baseline_sd_ln)
    if hrv_value is not None:
        weighted.append((hrv_value, 0.30))

    rhr_value = resting_hr_component(
        inputs.resting_hr, inputs.resting_hr_baseline, inputs.resting_hr_baseline_sd
    )
    if rhr_value is not None:
        weighted.append((rhr_value, 0.15))

    if inputs.yesterday_strain is not None:
        value = _clamp(90 - _clamp(inputs.yesterday_strain, 0, 1) * 45, 0, 100)
        weighted.append((value, 0.10))

    total_weight = sum(w for _, w in weighted)
    if total_weight <= 0:
        return ReadinessScore(overall=0, sleep_quality=0, recovery=0, confidence=0.0)

    overall = sum(v * w for v, w in weighted) / total_weight
    recovery_pairs = weighted[1:] if sleep_component is not None else weighted
    recovery_weight = sum(w for _, w in recovery_pairs)
    recovery = (
        sum(v * w for v, w in recovery_pairs) / recovery_weight
        if recovery_weight > 0
        else overall
    )
    return ReadinessScore(
        overall=_swift_round(overall),
        sleep_quality=_swift_round(sleep_component if sleep_component is not None else overall),
        recovery=_swift_round(recovery),
        confidence=_clamp(total_weight, 0, 1),
    )
