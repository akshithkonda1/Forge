"""One coaching picture from the engines that already live in aria_core.

Python port of ForgeCore's ``AriaPersonalRead.swift``, store-free: callers
pass sleep-depth baselines, HRV baseline, QoL snapshot, swarm headline, and
companion line. UserDefaults stays on the phone.
"""

from __future__ import annotations

from dataclasses import dataclass

from . import sleep_depth_scorer as sds


@dataclass(frozen=True)
class PersonalRead:
    sleep_depth_score: int | None = None
    sleep_depth_headline: str | None = None
    sleep_weak: bool = False
    hrv_ms: float | None = None
    hrv_baseline_ms: float | None = None
    hrv_below_personal: bool = False
    keep_light: bool = False
    companion_line: str | None = None
    qol_line: str | None = None
    aging_line: str | None = None
    swarm_line: str | None = None
    swarm_protect: bool = False
    sleep_band: str = "unknown"

    @property
    def spoken_ground(self) -> str | None:
        if self.companion_line:
            return self.companion_line
        if self.sleep_depth_headline:
            return self.sleep_depth_headline
        if self.hrv_below_personal:
            return "HRV is under your own baseline — not a population cutoff."
        if self.swarm_protect and self.swarm_line:
            return self.swarm_line
        if self.qol_line:
            return self.qol_line
        return None

    def to_dict(self) -> dict:
        return {
            "sleepDepthScore": self.sleep_depth_score,
            "sleepDepthHeadline": self.sleep_depth_headline,
            "sleepWeak": self.sleep_weak,
            "hrvMs": self.hrv_ms,
            "hrvBaselineMs": self.hrv_baseline_ms,
            "hrvBelowPersonal": self.hrv_below_personal,
            "keepLight": self.keep_light,
            "companionLine": self.companion_line,
            "qolLine": self.qol_line,
            "agingLine": self.aging_line,
            "swarmLine": self.swarm_line,
            "swarmProtect": self.swarm_protect,
            "sleepBand": self.sleep_band,
            "spokenGround": self.spoken_ground,
        }


def evaluate(
    *,
    night_hours: float | None,
    deep_minutes: float | None = None,
    rem_minutes: float | None = None,
    awake_minutes: float | None = None,
    hrv_ms: float | None = None,
    hrv_baseline_ms: float | None = None,
    readiness: int = 0,
    qol_overall: int | None = None,
    qol_line: str | None = None,
    aging_line: str | None = None,
    swarm_line: str | None = None,
    swarm_stance: str | None = None,
    companion_line: str | None = None,
    sleep_baselines: sds.SleepDepthBaselines | None = None,
) -> PersonalRead:
    sleep_depth: sds.SleepDepthResult | None = None
    if night_hours is not None and night_hours > 0:
        metrics = sds.SleepNightMetrics(
            total_hours=night_hours,
            deep_minutes=deep_minutes or 0,
            rem_minutes=rem_minutes or 0,
            efficiency_percent=sds.efficiency_percent(night_hours, awake_minutes or 0),
            wake_consistency=80,
        )
        targets = sds.SleepChronotypeTargets(
            target_hours=8,
            deep_goal_minutes=90,
            rem_goal_minutes=90,
        )
        sleep_depth = sds.score(metrics, targets, sleep_baselines or sds.SleepDepthBaselines())

    hrv_below = False
    if hrv_ms is not None and hrv_baseline_ms is not None and hrv_baseline_ms > 0:
        hrv_below = hrv_ms < hrv_baseline_ms * 0.92

    sleep_weak = (night_hours if night_hours is not None else 9) < 6.5
    if sleep_depth is not None:
        sleep_weak = sleep_weak or sleep_depth.score < 55 or bool(sleep_depth.unusual_flags)

    qol_protect = (qol_overall if qol_overall is not None else 100) < 55
    swarm_protect = False
    if swarm_stance:
        lowered = swarm_stance.lower()
        swarm_protect = "protect" in lowered or "easy" in lowered

    keep_light = sleep_weak or hrv_below or qol_protect or swarm_protect or readiness < 55

    if sleep_weak:
        sleep_band = "weak"
    elif sleep_depth is not None:
        if sleep_depth.score >= 80:
            sleep_band = "strong"
        elif sleep_depth.score < 55:
            sleep_band = "weak"
        else:
            sleep_band = "ok"
    else:
        sleep_band = "unknown"

    return PersonalRead(
        sleep_depth_score=sleep_depth.score if sleep_depth else None,
        sleep_depth_headline=sleep_depth.headline if sleep_depth else None,
        sleep_weak=sleep_weak,
        hrv_ms=hrv_ms,
        hrv_baseline_ms=hrv_baseline_ms,
        hrv_below_personal=hrv_below,
        keep_light=keep_light,
        companion_line=companion_line,
        qol_line=None if qol_overall is None else qol_line,
        aging_line=aging_line,
        swarm_line=swarm_line,
        swarm_protect=swarm_protect,
        sleep_band=sleep_band,
    )
