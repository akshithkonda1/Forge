"""Body model — fuse typed observations into a picture of how the body is
functioning, over time and in real time.

This is where data from one signal interacts with another: HRV, resting HR, and
sleep combine into recovery; systolic and diastolic combine into mean arterial
pressure; resting HR and age estimate VO2max. The model keeps a per-type series
plus an O(1) online aggregate, so the same object serves a 30-day backfill
(``from_observations``) and a live stream (``ingest`` one sample at a time).

``snapshot()`` reports each physiological system's state, the derived
cross-signal estimates, and anomalies. ``to_aria_context()`` projects the model
onto the ARIA coaching context — permission-aware — so everything the engine
already does flows straight from real ingested data.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from typing import Any

from services import aria_engine

from . import estimators, statistics as st
from .estimators import Estimate
from .types import MetricType, Observation, System, metrics_for_system, spec, utcnow

# Which ARIA coaching domain each physiological system feeds (for permissions).
_SYSTEM_TO_DOMAIN = {
    System.SLEEP: "sleep",
    System.AUTONOMIC: "readiness",
    System.CARDIOVASCULAR: "readiness",
    System.ACTIVITY: "activity",
    System.BODY: "body",
    System.NUTRITION: "nutrition",
    System.METABOLIC: "readiness",
    System.RESPIRATORY: "readiness",
}


def redact_snapshot(snap: dict[str, Any], permissions: "aria_engine.DataPermissions") -> dict[str, Any]:
    """Redact denied domains from a snapshot dict so /ai/observe honors the same
    permissions the ARIA context does. Systems and anomalies each map to a
    coaching domain; the cross-signal derived estimates are dropped whenever
    anything is restricted, since they can fuse a denied signal."""
    if not permissions.restricted():
        return snap

    def _metric_domain(metric_value: str) -> str:
        try:
            return _SYSTEM_TO_DOMAIN.get(spec(MetricType(metric_value)).system, "")
        except (ValueError, KeyError):
            return ""

    def _keep_anomaly(a: dict[str, Any]) -> bool:
        domain = _metric_domain(str(a.get("metric", "")))
        return not domain or permissions.allows(domain)

    snap["systems"] = {
        name: state
        for name, state in snap.get("systems", {}).items()
        if permissions.allows(_SYSTEM_TO_DOMAIN.get(System(name), name))
    }
    snap["anomalies"] = [a for a in snap.get("anomalies", []) if _keep_anomaly(a)]
    snap["derived"] = {}
    return snap


@dataclass
class MetricState:
    metric: MetricType
    latest: float | None
    baseline: float | None
    n: int
    estimate: Estimate

    def to_dict(self) -> dict[str, Any]:
        return {
            "metric": self.metric.value,
            "latest": self.latest,
            "baseline": self.baseline,
            "n": self.n,
            "state": self.estimate.state,
            "confidence": self.estimate.confidence,
            "detail": self.estimate.detail,
        }


@dataclass
class SystemState:
    system: System
    status: str
    summary: str
    confidence: float
    metrics: dict[str, MetricState] = field(default_factory=dict)
    derived: dict[str, Estimate] = field(default_factory=dict)

    def to_dict(self) -> dict[str, Any]:
        return {
            "system": self.system.value,
            "status": self.status,
            "summary": self.summary,
            "confidence": round(self.confidence, 3),
            "metrics": {k: v.to_dict() for k, v in self.metrics.items()},
            "derived": {k: vars(v) for k, v in self.derived.items()},
        }


@dataclass
class BodySnapshot:
    generated_at: str
    systems: dict[str, SystemState]
    derived: dict[str, Estimate]
    anomalies: list[dict[str, Any]]
    confidence: float
    observation_count: int
    sources: list[str]

    def to_dict(self) -> dict[str, Any]:
        return {
            "generated_at": self.generated_at,
            "confidence": round(self.confidence, 3),
            "observation_count": self.observation_count,
            "sources": self.sources,
            "systems": {k: v.to_dict() for k, v in self.systems.items()},
            "derived": {k: vars(v) for k, v in self.derived.items()},
            "anomalies": self.anomalies,
        }


class BodyModel:
    def __init__(self, *, age_years: float | None = None) -> None:
        self.series: dict[MetricType, list[Observation]] = {}
        self.online: dict[MetricType, st.OnlineStat] = {}
        self.age_years = age_years
        self._sources: set[str] = set()
        self._count = 0

    # -- ingestion -------------------------------------------------------------

    def ingest(self, obs: Observation) -> "BodyModel":
        """Real-time path: O(1) online update as each sample streams in."""
        self.series.setdefault(obs.metric, []).append(obs)
        self.online.setdefault(obs.metric, st.OnlineStat()).update(obs.value)
        self._sources.add(obs.source)
        self._count += 1
        return self

    def ingest_many(self, observations: list[Observation]) -> "BodyModel":
        for obs in sorted(observations, key=lambda o: o.timestamp):
            self.ingest(obs)
        return self

    @classmethod
    def from_observations(cls, observations: list[Observation], *, age_years: float | None = None) -> "BodyModel":
        return cls(age_years=age_years).ingest_many(observations)

    # -- accessors -------------------------------------------------------------

    def values(self, metric: MetricType) -> list[float]:
        return [o.value for o in self.series.get(metric, [])]

    def latest(self, metric: MetricType) -> float | None:
        series = self.series.get(metric)
        return series[-1].value if series else None

    def baseline(self, metric: MetricType) -> float | None:
        values = self.values(metric)
        return st.robust_baseline(values).median if values else None

    def recent_mean(self, metric: MetricType, n: int = 3) -> float | None:
        values = self.values(metric)
        return st.mean(values[-n:]) if values else None

    # -- snapshot --------------------------------------------------------------

    def _metric_state(self, metric: MetricType) -> MetricState:
        values = self.values(metric)
        est = estimators.default_estimator(metric).estimate(values)
        return MetricState(metric, self.latest(metric), self.baseline(metric), len(values), est)

    def _derived(self) -> dict[str, Estimate]:
        derived: dict[str, Estimate] = {}
        sys_bp = self.latest(MetricType.BLOOD_PRESSURE_SYSTOLIC)
        dia_bp = self.latest(MetricType.BLOOD_PRESSURE_DIASTOLIC)
        if sys_bp is not None and dia_bp is not None:
            derived["mean_arterial_pressure"] = estimators.mean_arterial_pressure(sys_bp, dia_bp)
            derived["pulse_pressure"] = estimators.pulse_pressure(sys_bp, dia_bp)

        rhr = self.latest(MetricType.RESTING_HEART_RATE)
        if self.age_years is not None and rhr is not None:
            derived["vo2_max_est"] = estimators.estimate_vo2max_from_rhr(self.age_years, rhr)
            derived["heart_rate_reserve"] = estimators.heart_rate_reserve(self.age_years, rhr)

        hrv_vals = self.values(MetricType.HRV_SDNN)
        if hrv_vals:
            hrv_today = self.online[MetricType.HRV_SDNN].ewma
            hrv_base = st.robust_baseline(hrv_vals).median
            derived["autonomic_stress"] = estimators.autonomic_stress_index(hrv_today, hrv_base)

        recovery = self._recovery_estimate()
        if recovery.value is not None:
            derived["recovery"] = recovery
        return derived

    def _recovery_estimate(self) -> Estimate:
        hrv_vals = self.values(MetricType.HRV_SDNN)
        rhr_vals = self.values(MetricType.RESTING_HEART_RATE)
        return estimators.estimate_recovery(
            hrv_today=self.online[MetricType.HRV_SDNN].ewma if hrv_vals else None,
            hrv_baseline=st.robust_baseline(hrv_vals).median if hrv_vals else None,
            rhr_today=self.latest(MetricType.RESTING_HEART_RATE),
            rhr_baseline=st.robust_baseline(rhr_vals).median if rhr_vals else None,
            sleep_minutes=self._sleep_total_minutes(),
            sleep_efficiency=self.latest(MetricType.SLEEP_EFFICIENCY),
        )

    def _sleep_total_minutes(self) -> float | None:
        total = self.latest(MetricType.SLEEP_DURATION)
        if total is not None:
            return total
        stages = [self.latest(m) for m in (MetricType.SLEEP_DEEP, MetricType.SLEEP_REM, MetricType.SLEEP_LIGHT)]
        present = [s for s in stages if s is not None]
        return sum(present) if present else None

    def snapshot(self) -> BodySnapshot:
        systems: dict[str, SystemState] = {}
        all_states: list[MetricState] = []
        derived = self._derived()

        for system in System:
            present = [m for m in metrics_for_system(system) if self.series.get(m)]
            if not present:
                continue
            states = {m.value: self._metric_state(m) for m in present}
            all_states.extend(states.values())
            sys_derived = {k: v for k, v in derived.items() if _belongs_to(k, system)}
            status, summary, confidence = _system_status(system, states, sys_derived)
            systems[system.value] = SystemState(system, status, summary, confidence, states, sys_derived)

        anomalies = [
            {"metric": s.metric.value, "value": s.latest, "detail": s.estimate.detail}
            for s in all_states
            if s.estimate.state == "anomalous"
        ]
        sys_conf = [s.confidence for s in systems.values() if s.confidence > 0]
        overall = st.mean(sys_conf) if sys_conf else 0.0

        return BodySnapshot(
            generated_at=utcnow().isoformat(),
            systems=systems,
            derived=derived,
            anomalies=anomalies,
            confidence=round(overall, 3),
            observation_count=self._count,
            sources=sorted(self._sources),
        )

    # -- projection onto the ARIA coaching context ----------------------------

    def to_aria_context(self, permissions: "aria_engine.DataPermissions | None" = None) -> aria_engine.ARIAContext:
        """Project the model onto ARIAContext, skipping permission-denied domains."""
        perms = permissions or aria_engine.DataPermissions.allow_all()

        def allowed(domain: str) -> bool:
            return perms.allows(domain)

        ctx = aria_engine.ARIAContext(timestamp=utcnow().isoformat())

        if allowed("sleep"):
            ctx.sleep = aria_engine.SleepContext(
                duration_minutes=self._sleep_total_minutes(),
                efficiency=self.latest(MetricType.SLEEP_EFFICIENCY),
                rem_minutes=self.latest(MetricType.SLEEP_REM),
                deep_minutes=self.latest(MetricType.SLEEP_DEEP),
                hrv=self.latest(MetricType.HRV_SDNN),
                resting_hr=self.latest(MetricType.RESTING_HEART_RATE),
                nights_available=len(self.series.get(MetricType.SLEEP_DURATION, []))
                or len(self.series.get(MetricType.SLEEP_DEEP, [])) or None,
            )

        if allowed("readiness"):
            hrv_vals = self.values(MetricType.HRV_SDNN)
            trend_pct = None
            if hrv_vals:
                base = st.robust_baseline(hrv_vals).median
                if base > 0:
                    trend_pct = round((self.online[MetricType.HRV_SDNN].ewma - base) / base * 100.0, 1)
            recovery = self._recovery_estimate()
            ctx.readiness = aria_engine.ReadinessContext(
                hrv_7day_trend=trend_pct,
                hrv_30day_baseline=st.robust_baseline(hrv_vals).median if hrv_vals else None,
                recovery_score=recovery.value,
                hrv_days_available=len(hrv_vals) or None,
            )

        if allowed("activity"):
            ctx.activity = aria_engine.ActivityContext(
                steps_3day_avg=self.recent_mean(MetricType.STEPS, 3),
                active_calories_3day_avg=self.recent_mean(MetricType.ACTIVE_ENERGY, 3),
            )

        if allowed("body"):
            weight_vals = self.values(MetricType.BODY_MASS)
            weight_trend = None
            if len(weight_vals) >= 2:
                weight_trend = round(weight_vals[-1] - st.robust_baseline(weight_vals).median, 2)
            vo2 = self.latest(MetricType.VO2_MAX)
            if vo2 is None and self.age_years is not None and self.latest(MetricType.RESTING_HEART_RATE):
                vo2 = estimators.estimate_vo2max_from_rhr(
                    self.age_years, self.latest(MetricType.RESTING_HEART_RATE)
                ).value
            body_fat = self.latest(MetricType.BODY_FAT)
            ctx.body = aria_engine.BodyContext(
                weight_kg=self.latest(MetricType.BODY_MASS),
                weight_trend_kg=weight_trend,
                body_fat_pct=round(body_fat * 100, 1) if body_fat is not None else None,
                vo2_max=vo2,
            )

        if allowed("nutrition"):
            ctx.nutrition = aria_engine.NutritionContext(
                calories_in_3day_avg=self.recent_mean(MetricType.DIETARY_ENERGY, 3),
                protein_g_3day_avg=self.recent_mean(MetricType.DIETARY_PROTEIN, 3),
                hydration_ml_3day_avg=self.recent_mean(MetricType.WATER, 3),
                calorie_target=None,
            )

        return ctx


def _belongs_to(derived_key: str, system: System) -> bool:
    mapping = {
        System.CARDIOVASCULAR: {"mean_arterial_pressure", "pulse_pressure", "vo2_max_est", "heart_rate_reserve"},
        System.AUTONOMIC: {"autonomic_stress", "recovery"},
    }
    return derived_key in mapping.get(system, set())


def _system_status(
    system: System, states: dict[str, MetricState], derived: dict[str, Estimate]
) -> tuple[str, str, float]:
    confidences = [s.estimate.confidence for s in states.values()]
    confidence = st.mean(confidences) if confidences else 0.0

    if any(s.estimate.state == "anomalous" for s in states.values()):
        status = "attention"
    elif system == System.AUTONOMIC and "autonomic_stress" in derived:
        stress = derived["autonomic_stress"].state
        status = {"high": "strained", "low": "recovered", "moderate": "balanced"}.get(stress, "nominal")
    elif "recovery" in derived and derived["recovery"].value is not None:
        status = {"primed": "recovered", "compromised": "strained", "moderate": "balanced"}.get(
            derived["recovery"].state, "nominal"
        )
    else:
        status = "nominal"

    parts = [f"{s.metric.value} {s.estimate.state}" for s in states.values()]
    summary = "; ".join(parts) if parts else "no data"
    return status, summary, confidence
