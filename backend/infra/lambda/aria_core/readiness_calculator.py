"""On-device readiness score — the Watch/Home glance, not the dashboard seed.

Python port of ForgeCore's ``ReadinessCalculator`` in ``Readiness.swift``.
``services/readiness.py`` remains the dashboard blend over persisted sleep
rows; this module is the shared formula both native clients should call
(or receive from ``shared_intelligence``) so iOS and Android do not drift.

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


PRIMED = "primed"
READY = "ready"
MODERATE = "moderate"
RECOVERY = "recovery"

BAND_LABEL = {
    PRIMED: "Primed",
    READY: "Ready",
    MODERATE: "Moderate",
    RECOVERY: "Recovery",
}

BAND_DESCRIPTOR = {
    PRIMED: "Your body is primed — a great day to reach.",
    READY: "Solid foundation today. Steady effort will feel good.",
    MODERATE: "A lighter-touch day. Small wins still count fully.",
    RECOVERY: "Your body is asking for ease today — honoring that is progress.",
}


def band_for_score(score: int) -> str:
    if score >= 85:
        return PRIMED
    if score >= 70:
        return READY
    if score >= 55:
        return MODERATE
    return RECOVERY


@dataclass
class ReadinessInputs:
    hrv_ms: float | None = None
    hrv_baseline_ms: float | None = None
    resting_hr: float | None = None
    resting_hr_baseline: float | None = None
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
    duration_score = _clamp(inputs.sleep_minutes / inputs.sleep_need_minutes, 0, 1.1) * 80
    architecture_bonus = 10.0
    if inputs.deep_sleep_minutes is not None:
        architecture_bonus = _clamp(inputs.deep_sleep_minutes / 60.0, 0, 1) * 12
    if inputs.rem_sleep_minutes is not None:
        architecture_bonus += _clamp(inputs.rem_sleep_minutes / 90.0, 0, 1) * 8
    else:
        architecture_bonus += 4
    return _clamp(duration_score + architecture_bonus, 0, 100)


def score(inputs: ReadinessInputs) -> ReadinessScore:
    weighted: list[tuple[float, float]] = []

    sleep_component = _sleep_score(inputs)
    if sleep_component is not None:
        weighted.append((sleep_component, 0.45))

    if (
        inputs.hrv_ms is not None
        and inputs.hrv_baseline_ms is not None
        and inputs.hrv_baseline_ms > 0
    ):
        ratio = inputs.hrv_ms / inputs.hrv_baseline_ms
        value = _clamp(75 + (ratio - 1.0) / 0.30 * 25, 0, 100)
        weighted.append((value, 0.30))

    if (
        inputs.resting_hr is not None
        and inputs.resting_hr_baseline is not None
        and inputs.resting_hr_baseline > 0
    ):
        delta = (inputs.resting_hr - inputs.resting_hr_baseline) / inputs.resting_hr_baseline
        value = _clamp(80 - delta / 0.15 * 30, 0, 100)
        weighted.append((value, 0.15))

    if inputs.yesterday_strain is not None:
        value = _clamp(90 - inputs.yesterday_strain * 45, 0, 100)
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
