"""Tomorrow-morning readiness forecast — Python port of ForgeCore's
ReadinessForecastEngine (ReadinessForecast.swift).

Numbers and copy stay lockstep with Swift so iOS, Watch, and the ARIA
engine steer from the same prediction. Lifestyle coach language only.
"""

from __future__ import annotations

import math
from dataclasses import dataclass, field
from typing import Any


def _swift_round(value: float) -> int:
    return int(math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5))


PUSH = "push"
STEADY = "steady"
PROTECT = "protect"
REST = "rest"

GLANCE_TITLE = {
    PUSH: "Green light",
    STEADY: "Steady",
    PROTECT: "Protect",
    REST: "Rest",
}


def keep_light(posture: str) -> bool:
    return posture in (PROTECT, REST)


@dataclass
class Driver:
    title: str
    detail: str
    impact: int
    icon: str


@dataclass
class Forecast:
    predicted_score: int
    confidence: str
    drivers: list[Driver]
    recommendation: str
    posture: str

    @property
    def aria_tags(self) -> list[str]:
        return [
            f"forecast:tomorrow:{self.predicted_score}:{self.posture}",
            f"forecast:confidence:{self.confidence}",
        ]

    @property
    def chat_prompt(self) -> str:
        return (
            f"Tomorrow's readiness looks like {self.predicted_score} with a "
            f"{self.posture} day. {self.recommendation} How should I train around that?"
        )

    @property
    def steering_line(self) -> str:
        if self.posture == PUSH:
            return "Tomorrow looks available — keep the hard session if they want it."
        if self.posture == STEADY:
            return "Tomorrow looks like a normal training day — keep the plan."
        if self.posture == PROTECT:
            return "Tomorrow looks like a cap-intensity day — protect the session, don't add load."
        return "Tomorrow looks like a rest day — showing up easy beats pushing through."

    @property
    def glance_line(self) -> str:
        return f"Tomorrow {self.predicted_score} · {GLANCE_TITLE.get(self.posture, self.posture)}"

    def to_dict(self) -> dict[str, Any]:
        return {
            "predictedScore": self.predicted_score,
            "confidence": self.confidence,
            "posture": self.posture,
            "recommendation": self.recommendation,
            "steeringLine": self.steering_line,
            "chatPrompt": self.chat_prompt,
            "ariaTags": self.aria_tags,
            "drivers": [
                {"title": d.title, "detail": d.detail, "impact": d.impact}
                for d in self.drivers[:3]
            ],
        }


@dataclass
class ForecastInput:
    current_readiness: int
    sleep_minutes: int
    sleep_need_minutes: int = 480
    hrv_ms: int = 0
    hrv_baseline_ms: int | None = None
    resting_hr: int = 0
    resting_hr_baseline: int | None = None
    today_strain: float = 0
    planned_strain: float = 0
    acwr: float | None = None
    stress_level: int = 30
    is_luteal_phase: bool | None = None


def _posture(predicted: int) -> str:
    if predicted >= 80:
        return PUSH
    if predicted >= 65:
        return STEADY
    if predicted >= 50:
        return PROTECT
    return REST


def _recommendation(posture: str, drivers: list[Driver], predicted: int, current: int) -> str:
    delta = predicted - current
    trend = "trending up" if delta >= 5 else ("dipping" if delta <= -5 else "holding steady")
    lead = f" — {drivers[0].title.lower()} is the biggest factor" if drivers else ""
    if posture == PUSH:
        return (
            f"Green light for tomorrow ({trend}{lead}). "
            "Good day for the hard session you've been holding."
        )
    if posture == STEADY:
        return f"Normal training day tomorrow ({trend}{lead}). Keep the plan as written."
    if posture == PROTECT:
        return (
            f"Cap intensity tomorrow ({trend}{lead}). "
            "Swap intervals for aerobic base or technique work."
        )
    return (
        f"Take the rest day tomorrow ({trend}{lead}). "
        "It pays back more than pushing through."
    )


def forecast(inp: ForecastInput) -> Forecast:
    score = float(inp.current_readiness)
    drivers: list[Driver] = []
    known = 0
    total = 0

    total += 1
    sleep_debt_hours = (inp.sleep_need_minutes - inp.sleep_minutes) / 60.0
    if sleep_debt_hours > 0.25:
        impact = -int(min(20, sleep_debt_hours * 8))
        score += impact
        drivers.append(Driver(
            "Sleep debt",
            f"{sleep_debt_hours:.1f}h under your need tonight",
            impact,
            "moon.zzz.fill",
        ))
        known += 1
    elif sleep_debt_hours < -0.5:
        impact = min(6, int(-sleep_debt_hours * 4))
        score += impact
        drivers.append(Driver("Sleep surplus", "Extra sleep banked tonight", impact, "moon.stars.fill"))
        known += 1
    else:
        known += 1

    total += 1
    if inp.hrv_baseline_ms and inp.hrv_baseline_ms > 0 and inp.hrv_ms > 0:
        deviation = (inp.hrv_ms - inp.hrv_baseline_ms) / float(inp.hrv_baseline_ms)
        impact = int(max(-15, min(12, deviation * 50)))
        if abs(impact) >= 2:
            score += impact
            drivers.append(Driver(
                "HRV suppressed" if impact < 0 else "HRV elevated",
                f"{int(deviation * 100)}% vs your baseline",
                impact,
                "waveform.path.ecg",
            ))
        known += 1

    total += 1
    if inp.resting_hr_baseline and inp.resting_hr_baseline > 0 and inp.resting_hr > 0:
        delta = inp.resting_hr - inp.resting_hr_baseline
        if delta >= 4:
            impact = -min(10, (delta - 3) * 2)
            score += impact
            drivers.append(Driver(
                "Resting HR elevated",
                f"+{delta} bpm vs baseline — recovery incomplete",
                impact,
                "heart.fill",
            ))
            known += 1
        else:
            known += 1

    total += 1
    combined = inp.today_strain + inp.planned_strain
    if combined >= 16:
        score -= 12
        drivers.append(Driver(
            "Heavy load today",
            f"Strain {combined:.1f} — expect residual fatigue",
            -12,
            "flame.fill",
        ))
    elif combined >= 10:
        score -= 6
        drivers.append(Driver(
            "Moderate load today",
            f"Strain {combined:.1f} — mild fatigue carryover",
            -6,
            "flame",
        ))
    elif combined < 4:
        score += 5
        drivers.append(Driver(
            "Recovery day",
            "Low strain lets adaptation catch up",
            5,
            "leaf.fill",
        ))
    known += 1

    total += 1
    if inp.acwr is not None:
        if inp.acwr > 1.5:
            score -= 10
            drivers.append(Driver(
                "Load spiking",
                f"This week is {inp.acwr:.1f}x your 4-week average — overreaching risk",
                -10,
                "exclamationmark.triangle.fill",
            ))
        elif inp.acwr < 0.8:
            score += 4
            drivers.append(Driver(
                "Load dip",
                f"This week is {inp.acwr:.1f}x your average — freshness building",
                4,
                "arrow.down.circle.fill",
            ))
        known += 1

    total += 1
    if inp.stress_level >= 70:
        score -= 6
        drivers.append(Driver("High stress", "Mental load taxes recovery too", -6, "brain.head.profile"))
    elif inp.stress_level <= 25:
        score += 3
        drivers.append(Driver("Low stress", "Recovery environment is clean", 3, "checkmark.circle.fill"))
    known += 1

    if inp.is_luteal_phase is True:
        score -= 4
        drivers.append(Driver(
            "Luteal phase",
            "Recovery runs ~5% slower — plan lighter",
            -4,
            "circle.dotted",
        ))

    predicted = max(5, min(98, _swift_round(score)))
    posture = _posture(predicted)
    coverage = known / max(1, total)
    if coverage >= 0.85:
        confidence = "high"
    elif coverage >= 0.6:
        confidence = "medium"
    else:
        confidence = "low"
    drivers.sort(key=lambda d: abs(d.impact), reverse=True)
    return Forecast(
        predicted_score=predicted,
        confidence=confidence,
        drivers=drivers,
        recommendation=_recommendation(posture, drivers, predicted, inp.current_readiness),
        posture=posture,
    )


def parse_tag(token: str) -> tuple[int, str] | None:
    parts = str(token or "").split(":")
    if len(parts) < 4 or parts[0] != "forecast" or parts[1] != "tomorrow":
        return None
    try:
        score = int(parts[2])
    except (TypeError, ValueError):
        return None
    posture = parts[3]
    if posture not in (PUSH, STEADY, PROTECT, REST):
        return None
    return score, posture
