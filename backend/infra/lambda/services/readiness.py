from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from aria_core import readiness_calculator as rc
from empty_state import empty_readiness


def _positive(value: Any) -> float | None:
    if isinstance(value, bool) or not isinstance(value, (int, float)):
        return None
    return float(value) if value > 0 else None


def compute_readiness(
    sleep_records: list[dict[str, Any]],
    hrv: float | None = None,
    resting_hr: float | None = None,
) -> dict[str, Any]:
    """Dashboard readiness from persisted sleep rows (newest first).

    Same formula as the Watch/Home glance (``aria_core.readiness_calculator``):
    last night's duration and stages, with HRV and resting HR read against
    this person's own earlier nights — never a population cutoff, and never a
    stand-in score for a night that has no data.
    """
    if not sleep_records:
        return empty_readiness()

    latest = sleep_records[0]
    hours = _positive(latest.get("totalHours"))
    hrv_today = _positive(hrv) or _positive(latest.get("hrv"))
    rhr_today = _positive(resting_hr) or _positive(latest.get("restingHR"))

    earlier = sleep_records[1:]
    hrv_base = rc.personal_baseline([r.get("hrv") for r in earlier], log_scaled=True)
    rhr_base = rc.personal_baseline([r.get("restingHR") for r in earlier], log_scaled=False)

    glance = rc.score(rc.ReadinessInputs(
        sleep_minutes=hours * 60 if hours else None,
        deep_sleep_minutes=_positive(latest.get("deepMinutes")),
        rem_sleep_minutes=_positive(latest.get("remMinutes")),
        hrv_ms=hrv_today,
        hrv_baseline_ms=hrv_base.mean if hrv_base else None,
        hrv_baseline_sd_ln=hrv_base.spread if hrv_base else None,
        resting_hr=rhr_today,
        resting_hr_baseline=rhr_base.mean if rhr_base else None,
        resting_hr_baseline_sd=rhr_base.spread if rhr_base else None,
    ))
    if glance.confidence <= 0:
        # Rows exist but none of them says anything measurable about last
        # night (manual stubs, a null score). Unmeasured is not mid-range.
        return empty_readiness()

    has_physiology = (
        rc.hrv_component(hrv_today, hrv_base.mean if hrv_base else None) is not None
        or rc.resting_hr_component(rhr_today, rhr_base.mean if rhr_base else None) is not None
    )
    return {
        "overall": glance.overall,
        "sleepQuality": glance.sleep_quality,
        "recoveryScore": glance.recovery,
        # Physiological load as the inverse of HRV/resting-HR recovery — the
        # same definition the iOS client uses. Only when those signals exist.
        "stressLevel": max(0, 100 - glance.recovery) if has_physiology else None,
        "energyBank": glance.overall,
        "confidence": glance.confidence,
        "band": glance.band,
        "available": True,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }
