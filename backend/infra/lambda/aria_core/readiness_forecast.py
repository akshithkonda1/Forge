"""Tomorrow-morning readiness forecast — Python port of ForgeCore's
ReadinessForecastEngine (ReadinessForecast.swift).

Numbers and copy stay lockstep with Swift so iOS, Watch, and the ARIA
engine steer from the same prediction. Lifestyle coach language only.

Model: today's readiness already contains last night's sleep, HRV, and
resting HR, so the forecast never re-applies them. It starts from today and
lets part of today's distance from your usual carry into tomorrow
(``CARRY_OVER``), then adds only what happens between now and tomorrow
morning: today's and planned training load, the acute:chronic load ratio,
self-reported stress, and cycle phase. Unknown inputs (0 sleep minutes,
0 readiness, no stress report) are missing — never zero sleep or a 0 score.
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


# Share of today's distance from your usual that is still there tomorrow
# morning. Day-to-day autocorrelation of recovery markers (ln HRV, resting HR)
# in free-living adults sits around 0.4-0.6; 0.5 is the middle of that range.
CARRY_OVER = 0.5

# Stand-in for "your usual" until a personal readiness baseline is supplied:
# a person at their own HRV/resting-HR norm after a typical night lands here.
DEFAULT_READINESS_BASELINE = 75


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
    # Today's readiness, 0-100. 0 or less means not measured yet.
    current_readiness: int
    # Last night's sleep, minutes. 0 or less means unknown (not zero sleep).
    sleep_minutes: int
    sleep_need_minutes: int = 480
    hrv_ms: int = 0
    hrv_baseline_ms: int | None = None
    resting_hr: int = 0
    resting_hr_baseline: int | None = None
    today_strain: float = 0
    planned_strain: float = 0
    acwr: float | None = None
    # Self-reported stress, 0-100. None when the person has not said.
    stress_level: int | None = None
    is_luteal_phase: bool | None = None
    # Personal typical readiness (e.g. a 14-day mean). None → default.
    readiness_baseline: int | None = None


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


def _dip_cause(inp: ForecastInput) -> str | None:
    """Name the signal most behind a low day, for the bounce-back detail.

    Explanation only — today's score already carries these signals, so they
    never add points of their own here.
    """
    candidates: list[tuple[float, str]] = []
    if inp.sleep_minutes > 0:
        debt_hours = (inp.sleep_need_minutes - inp.sleep_minutes) / 60.0
        if debt_hours >= 0.75:
            candidates.append((debt_hours / 2.0, "short sleep"))
    if inp.hrv_ms > 0 and inp.hrv_baseline_ms and inp.hrv_baseline_ms > 0:
        deviation = (inp.hrv_ms - inp.hrv_baseline_ms) / float(inp.hrv_baseline_ms)
        if deviation <= -0.10:
            candidates.append((-deviation / 0.30, "low HRV"))
    if inp.resting_hr > 0 and inp.resting_hr_baseline and inp.resting_hr_baseline > 0:
        delta = inp.resting_hr - inp.resting_hr_baseline
        if delta >= 3:
            candidates.append((delta / 8.0, "raised resting HR"))
    if not candidates:
        return None
    return max(candidates, key=lambda c: c[0])[1]


def forecast(inp: ForecastInput) -> Forecast:
    baseline = (
        inp.readiness_baseline
        if inp.readiness_baseline is not None and inp.readiness_baseline > 0
        else DEFAULT_READINESS_BASELINE
    )
    knows_today = inp.current_readiness > 0
    current = inp.current_readiness if knows_today else baseline
    score = float(current)
    drivers: list[Driver] = []

    # --- Carry-over: part of today's distance from your usual persists ---
    if knows_today:
        impact = _swift_round(-(1.0 - CARRY_OVER) * (current - baseline))
        if abs(impact) >= 2:
            score += impact
            if impact > 0:
                cause = _dip_cause(inp)
                detail = (
                    f"Today's dip from {cause} eases about halfway by morning"
                    if cause
                    else "Today's dip eases about halfway by morning"
                )
                drivers.append(Driver("Bounce-back", detail, impact, "arrow.uturn.up.circle.fill"))
            else:
                drivers.append(Driver(
                    "Easing to your usual",
                    "Today's high eases about halfway back toward your norm",
                    impact,
                    "arrow.down.right.circle",
                ))

    # --- Today's + planned strain (not yet in today's score) ---
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
    elif combined < 4 and knows_today:
        # With no reading of today at all, an empty log is not evidence of
        # a rest day — it is evidence of nothing.
        score += 5
        drivers.append(Driver(
            "Recovery day",
            "Low strain lets adaptation catch up",
            5,
            "leaf.fill",
        ))

    # --- Acute:chronic workload ratio ---
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

    # --- Self-reported stress (only when the person said) ---
    if inp.stress_level is not None:
        if inp.stress_level >= 70:
            score -= 6
            drivers.append(Driver("High stress", "Mental load taxes recovery too", -6, "brain.head.profile"))
        elif inp.stress_level <= 25:
            score += 3
            drivers.append(Driver("Low stress", "Recovery environment is clean", 3, "checkmark.circle.fill"))

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
    if not knows_today:
        # Green light and rest day are both confident calls; without today's
        # reading the forecast can lean, not commit.
        if posture == PUSH:
            posture = STEADY
        elif posture == REST:
            posture = PROTECT

    # What the forecast actually knows. Load is always "known" (no session is
    # a real 0), so it does not count toward coverage.
    signals = [
        knows_today,
        inp.readiness_baseline is not None and inp.readiness_baseline > 0,
        inp.sleep_minutes > 0,
        bool(inp.hrv_ms > 0 and inp.hrv_baseline_ms and inp.hrv_baseline_ms > 0),
        bool(inp.resting_hr > 0 and inp.resting_hr_baseline and inp.resting_hr_baseline > 0),
        inp.acwr is not None,
        inp.stress_level is not None,
    ]
    coverage = sum(1 for known in signals if known) / len(signals)
    if not knows_today:
        confidence = "low"
    elif coverage >= 0.85:
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
        recommendation=_recommendation(posture, drivers, predicted, current),
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
