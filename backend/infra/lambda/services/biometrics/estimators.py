"""Estimation layer — turn typed series into interpreted state and derived
metrics the body never reports directly.

Two kinds of estimator live here:

* **Statistical** — ``BaselineEstimator`` learns each metric's personal baseline
  (robust median/MAD), scores today's deviation, flags anomalies, and reads the
  trend. This is per-type and provider-blind.
* **Physiological** — closed-form estimates that *fuse signals across types*
  (mean arterial pressure from systolic+diastolic, VO2max from resting HR,
  autonomic stress and a fused recovery score from HRV+RHR+sleep). These are the
  cross-signal interactions the body model leans on.

Both satisfy the ``Estimator`` protocol, so a trained ML model can replace any
estimator without touching callers — the deterministic versions here are the
Phase-1 baseline, not the ceiling.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Protocol

from . import statistics as st
from .types import MetricType, spec


@dataclass
class Estimate:
    name: str
    value: float | None
    state: str            # normal | elevated | depressed | anomalous | rising | falling | ...
    confidence: float     # 0..1
    method: str           # "robust_baseline" | "formula:tanaka" | "model:<id>" ...
    detail: str = ""


class Estimator(Protocol):
    """Anything that turns a metric's series into an :class:`Estimate`.

    A future ML model is dropped in by implementing this one method.
    """

    def estimate(self, values: list[float]) -> Estimate: ...


# --- statistical, per-type ---------------------------------------------------


class BaselineEstimator:
    """Personal-baseline deviation + anomaly + trend for one metric type."""

    def __init__(self, metric: MetricType) -> None:
        self.metric = metric
        self._spec = spec(metric)

    def estimate(self, values: list[float]) -> Estimate:
        if not values:
            return Estimate(self.metric.value, None, "unknown", 0.0, "robust_baseline", "no samples")

        latest = values[-1]
        baseline = st.robust_baseline(values)
        trend = st.linear_trend(values)
        mz = baseline.modified_zscore(latest)

        if baseline.is_anomaly(latest):
            state = "anomalous"
        elif mz >= 1.0:
            state = "elevated"
        elif mz <= -1.0:
            state = "depressed"
        elif trend.direction != "flat":
            state = trend.direction
        else:
            state = "normal"

        # Confidence grows with sample count and shrinks with relative spread.
        n_factor = st.clamp(baseline.n / 14.0, 0.15, 1.0)
        cov = st.coefficient_of_variation(values)
        confidence = round(st.clamp(n_factor * (1.0 - st.clamp(cov, 0.0, 0.6)), 0.1, 0.95), 3)

        detail = (
            f"latest {latest:g} {self._spec.unit} vs baseline {baseline.median:g} "
            f"(robust z {mz:+.1f}, trend {trend.direction}, n={baseline.n})"
        )
        return Estimate(self.metric.value, round(latest, 3), state, confidence, "robust_baseline", detail)


def default_estimator(metric: MetricType) -> Estimator:
    """The estimator for a metric — a registered one (e.g. a model) or the
    statistical baseline. The body model calls this, so swapping in a trained
    model anywhere is a one-line registration, no caller changes."""
    return _REGISTRY.get(metric) or BaselineEstimator(metric)


# Mutable registry so a trained-model path can take over specific metrics at
# runtime without touching callers. See ``inference.enable_model_estimators``.
_REGISTRY: dict[MetricType, Estimator] = {}


def set_estimator(metric: MetricType, estimator: Estimator) -> None:
    _REGISTRY[metric] = estimator


def reset_estimators() -> None:
    _REGISTRY.clear()


# --- physiological, cross-signal ---------------------------------------------


def mean_arterial_pressure(systolic: float, diastolic: float) -> Estimate:
    """MAP ≈ DBP + (SBP − DBP)/3 — the perfusion-relevant average pressure."""
    value = round(diastolic + (systolic - diastolic) / 3.0, 1)
    state = "elevated" if value >= 100 else "low" if value < 70 else "normal"
    return Estimate("mean_arterial_pressure", value, state, 0.9, "formula:map", f"{value} mmHg")


def pulse_pressure(systolic: float, diastolic: float) -> Estimate:
    """SBP − DBP. A wide pulse pressure can signal arterial stiffness."""
    value = round(systolic - diastolic, 1)
    state = "wide" if value >= 60 else "narrow" if value < 25 else "normal"
    return Estimate("pulse_pressure", value, state, 0.9, "formula:pulse_pressure", f"{value} mmHg")


def estimate_max_hr(age_years: float) -> float:
    """Tanaka et al. (2001): HRmax = 208 − 0.7·age."""
    return 208.0 - 0.7 * age_years


def heart_rate_reserve(age_years: float, resting_hr: float) -> Estimate:
    """Karvonen reserve = HRmax − RHR — the trainable HR range."""
    hr_max = estimate_max_hr(age_years)
    value = round(hr_max - resting_hr, 0)
    state = "low" if value < 100 else "high" if value > 160 else "normal"
    return Estimate("heart_rate_reserve", value, state, 0.7, "formula:karvonen", f"{value} bpm reserve")


def estimate_vo2max_from_rhr(age_years: float, resting_hr: float) -> Estimate:
    """Uth–Sørensen–Overgaard–Pedersen: VO2max ≈ 15.3·(HRmax/RHR)."""
    if resting_hr <= 0:
        return Estimate("vo2_max_est", None, "unknown", 0.0, "formula:uth", "no resting HR")
    hr_max = estimate_max_hr(age_years)
    value = round(15.3 * (hr_max / resting_hr), 1)
    state = "high" if value >= 45 else "low" if value < 35 else "moderate"
    return Estimate("vo2_max_est", value, state, 0.6, "formula:uth", f"~{value} ml/kg/min from RHR")


def autonomic_stress_index(hrv_today: float, hrv_baseline: float) -> Estimate:
    """0–100 sympathetic-load proxy: HRV suppression vs personal baseline."""
    if hrv_baseline <= 0:
        return Estimate("autonomic_stress", None, "unknown", 0.0, "formula:hrv_ratio", "no HRV baseline")
    ratio = hrv_today / hrv_baseline
    index = round(st.clamp((1.0 - ratio) * 140.0 + 30.0, 0.0, 100.0), 0)
    state = "high" if index >= 65 else "low" if index <= 35 else "moderate"
    return Estimate("autonomic_stress", index, state, 0.7, "formula:hrv_ratio",
                    f"HRV {hrv_today:g} vs baseline {hrv_baseline:g} → stress {index:g}/100")


def estimate_recovery(
    *,
    hrv_today: float | None = None,
    hrv_baseline: float | None = None,
    rhr_today: float | None = None,
    rhr_baseline: float | None = None,
    sleep_minutes: float | None = None,
    sleep_efficiency: float | None = None,
) -> Estimate:
    """Fuse autonomic + cardiovascular + sleep signals into a 0–100 recovery score.

    Components are reweighted over whatever is present, so the score degrades
    gracefully instead of disappearing when a signal is missing. Confidence
    reflects how much of the picture we actually had.
    """
    components: list[tuple[float, float]] = []  # (subscore 0..100, weight)

    if hrv_today is not None and hrv_baseline and hrv_baseline > 0:
        ratio = hrv_today / hrv_baseline
        components.append((st.clamp(50.0 + (ratio - 1.0) * 160.0, 0.0, 100.0), 0.40))
    if rhr_today is not None and rhr_baseline and rhr_baseline > 0:
        # Elevated resting HR depresses recovery (~3 pts per bpm above baseline).
        delta = rhr_today - rhr_baseline
        components.append((st.clamp(75.0 - delta * 3.0, 0.0, 100.0), 0.25))
    if sleep_minutes is not None:
        components.append((st.clamp((sleep_minutes / 480.0) * 100.0, 0.0, 100.0), 0.20))
    if sleep_efficiency is not None:
        components.append((st.clamp(sleep_efficiency * 100.0, 0.0, 100.0), 0.15))

    if not components:
        return Estimate("recovery", None, "unknown", 0.0, "fusion:recovery", "no recovery inputs")

    total_weight = sum(w for _, w in components)
    score = round(sum(sub * w for sub, w in components) / total_weight, 0)
    state = "primed" if score >= 75 else "compromised" if score < 50 else "moderate"
    # Confidence tracks how much of the full 1.0 weight we could fill.
    confidence = round(st.clamp(total_weight, 0.2, 0.95), 2)
    return Estimate("recovery", score, state, confidence, "fusion:recovery",
                    f"{len(components)} signal(s) → recovery {score:g}/100")
