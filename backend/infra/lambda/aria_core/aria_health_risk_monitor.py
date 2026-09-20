"""AriaHealthRiskMonitor — on-device literacy for Watch/HealthKit vitals,
never a diagnosis.

Python port of ForgeCore's ``AriaHealthRiskMonitor.swift``
(``ForgeSwift/ForgeCore/Sources/ForgeCore/Intelligence/AriaHealthRiskMonitor.swift``),
kept numerically/textually identical to it. Every threshold and copy string
below is carried over line for line and word for word, since the exact
wording is the safety contract here, not just the numbers: ARIA may notice
"this looks high versus typical" and suggest a clinician; it must never
name a disease.

Apple Watch wrist temperature is typically an overnight deviation from the
wearer's baseline (``appleSleepingWristTemperature``), not a clinical
thermometer. Body temperature in HealthKit is whatever the user or another
app logged. Every finding here is framed as a sensor hint, never a
diagnosis -- verified by this port's own tests (mirroring the Swift
suite's own diagnosis-language assertions) as well as by direct string
inspection of the copy itself.

Ported: ``AriaHealthRiskKind``/``AriaHealthRiskSeverity`` (as their exact
Swift rawValue strings, not reformatted -- see the constants below --
since ``AriaHealthRiskCooldown.storage_key()``'s output text is a
serialization detail, not just an internal label), ``AriaVitalReading``,
``AriaHealthRiskFinding`` (including its ``rank`` property), ``evaluate()``,
``primary()``, ``should_surface_in_chat()``, and ``AriaHealthRiskCooldown``
(genuinely pure -- ``should_notify()``/``storage_key()`` take/return plain
values with no UserDefaults access of their own, unlike every "Store"
excluded from earlier ports in this package).

Not ported: ``WatchVitalsPayload``/``WatchVitalsInbox`` (a separate file,
not named in this task) -- UserDefaults-backed inbox persistence for
Watch-sourced vitals, the same reasoning every earlier "Store" exclusion
was made for.

Stdlib only. Deterministic (given `now`). Pure -- no I/O.
"""

from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime

# --- Kind / Severity -----------------------------------------------------
# Mirrors AriaHealthRiskKind/AriaHealthRiskSeverity (Swift L10-22). Values
# are the exact Swift rawValue strings (implicit from the case names),
# not reformatted, since AriaHealthRiskCooldown.storage_key()'s output
# text is a serialization detail.

ELEVATED_TEMPERATURE = "elevatedTemperature"
WRIST_TEMPERATURE_RISE = "wristTemperatureRise"
RESTING_HEART_RATE_SPIKE = "restingHeartRateSpike"
HRV_DROP = "hrvDrop"

# A bit high versus typical. Worth noticing; not an emergency line.
WATCH = "watch"
# More clearly elevated. Still not a diagnosis -- point at a clinician.
CONCERN = "concern"


def _swift_round(value: float) -> int:
    """Swift's ``Double.rounded()`` default rule: round half away from
    zero, not Python's banker's-rounding ``round()``."""
    return math.floor(value + 0.5) if value >= 0 else math.ceil(value - 0.5)


# --- Inputs ------------------------------------------------------------------
# Mirrors AriaVitalReading (Swift L24-53).

@dataclass(frozen=True)
class AriaVitalReading:
    sampled_at: datetime
    body_temperature_f: float | None = None
    wrist_temperature_deviation_c: float | None = None
    resting_heart_rate: float | None = None
    resting_heart_rate_baseline: float | None = None
    hrv_ms: float | None = None
    hrv_baseline_ms: float | None = None
    hours_since_last_workout: float | None = None


# --- Findings ----------------------------------------------------------
# Mirrors AriaHealthRiskFinding (Swift L55-94).

_RANK: dict[tuple[str, str], int] = {
    (CONCERN, ELEVATED_TEMPERATURE): 40,
    (CONCERN, WRIST_TEMPERATURE_RISE): 36,
    (CONCERN, RESTING_HEART_RATE_SPIKE): 32,
    (CONCERN, HRV_DROP): 28,
    (WATCH, ELEVATED_TEMPERATURE): 24,
    (WATCH, WRIST_TEMPERATURE_RISE): 20,
    (WATCH, RESTING_HEART_RATE_SPIKE): 16,
    (WATCH, HRV_DROP): 12,
}


@dataclass(frozen=True)
class AriaHealthRiskFinding:
    kind: str
    severity: str
    title: str
    # Lock-screen safe. Never a diagnosis, never a cycle phase.
    body: str
    # Prefills ARIA chat when the human taps the notification.
    chat_opener: str
    # On-device coaching line when they are already talking to ARIA.
    coach_line: str

    @property
    def rank(self) -> int:
        return _RANK[(self.severity, self.kind)]


# --- Monitor -----------------------------------------------------------
# Mirrors AriaHealthRiskMonitor (Swift L96-212).

SLIGHTLY_HIGH_BODY_TEMP_F = 99.5
FEVER_RANGE_BODY_TEMP_F = 100.4
WRIST_RISE_WATCH_C = 0.5
WRIST_RISE_CONCERN_C = 0.8
RHR_DELTA_WATCH = 8.0
RHR_DELTA_CONCERN = 12.0
HRV_DROP_FRACTION = 0.25
HRV_DROP_ABSOLUTE = 15.0
# Ignore stale samples so a last-week reading cannot fire tonight.
SAMPLE_MAX_AGE_SECONDS = 16 * 3600
# Gym sessions raise skin temp; do not treat that as a health check.
WORKOUT_IGNORE_HOURS = 1.5


def evaluate(reading: AriaVitalReading, now: datetime | None = None) -> list[AriaHealthRiskFinding]:
    if now is None:
        now = datetime.now()
    if (now - reading.sampled_at).total_seconds() > SAMPLE_MAX_AGE_SECONDS:
        return []

    findings: list[AriaHealthRiskFinding] = []
    hours_since_workout = (
        reading.hours_since_last_workout if reading.hours_since_last_workout is not None else math.inf
    )
    recently_worked_out = hours_since_workout < WORKOUT_IGNORE_HOURS

    if (reading.body_temperature_f is not None and reading.body_temperature_f >= SLIGHTLY_HIGH_BODY_TEMP_F
            and not recently_worked_out):
        temp = reading.body_temperature_f
        concern = temp >= FEVER_RANGE_BODY_TEMP_F
        rounded = f"{temp:.1f}"
        findings.append(AriaHealthRiskFinding(
            kind=ELEVATED_TEMPERATURE,
            severity=CONCERN if concern else WATCH,
            title="Temperature looks high" if concern else "Temperature a bit high",
            body=(
                f"A recent reading is {rounded}°F — higher than typical. I'm not diagnosing. "
                f"If you feel unwell, a clinician is the right call."
                if concern else
                f"A recent reading is {rounded}°F, a little above typical. Worth noticing and taking it "
                f"easy — a clinician can tell you more."
            ),
            chat_opener=f"My temperature is reading {rounded}°F. What should I actually do with that?",
            coach_line=(
                f"Your latest temperature is {rounded}°F, which is in the range people often call a fever. "
                f"I can't diagnose. Ease off training, hydrate, and talk to a clinician if it holds or you "
                f"feel worse."
                if concern else
                f"Your latest temperature is {rounded}°F — a bit high versus typical. Not a diagnosis. "
                f"I'd keep today easy and watch how you feel."
            ),
        ))

    if reading.wrist_temperature_deviation_c is not None and reading.wrist_temperature_deviation_c >= WRIST_RISE_WATCH_C:
        delta = reading.wrist_temperature_deviation_c
        concern = delta >= WRIST_RISE_CONCERN_C
        rounded = f"{delta:.2f}"
        findings.append(AriaHealthRiskFinding(
            kind=WRIST_TEMPERATURE_RISE,
            severity=CONCERN if concern else WATCH,
            title="Wrist temperature is up",
            body=(
                f"Overnight wrist temperature is about {rounded}°C above your baseline. That's a Watch "
                f"sleeping reading, not a medical thermometer — still worth a clinician if you feel off."
                if concern else
                f"Overnight wrist temperature is about {rounded}°C above your baseline. A small rise "
                f"happens; if you feel unwell, treat a clinician as the source of truth."
            ),
            chat_opener=f"My Apple Watch wrist temperature is {rounded}°C above baseline. What does that mean for today?",
            coach_line=(
                f"Your Watch sleeping wrist temperature is {rounded}°C above your usual overnight "
                f"baseline. That's a sensor hint, not a diagnosis. I'd make today recovery-shaped and "
                f"check in with a clinician if you feel sick."
                if concern else
                f"Watch says overnight wrist temperature is {rounded}°C above your baseline. Small "
                f"drifts happen. If you feel fine, note it; if you don't, a clinician beats my guess."
            ),
        ))

    if (reading.resting_heart_rate is not None and reading.resting_heart_rate_baseline is not None
            and reading.resting_heart_rate_baseline > 0):
        rhr = reading.resting_heart_rate
        base = reading.resting_heart_rate_baseline
        delta = rhr - base
        if delta >= RHR_DELTA_WATCH:
            concern = delta >= RHR_DELTA_CONCERN
            findings.append(AriaHealthRiskFinding(
                kind=RESTING_HEART_RATE_SPIKE,
                severity=CONCERN if concern else WATCH,
                title="Resting heart rate is up" if concern else "Resting heart rate a bit high",
                body=(f"Resting heart rate is {_swift_round(rhr)} vs a usual {_swift_round(base)}. "
                      f"Load, heat, or being run-down can do that — I can't name which."),
                chat_opener=(f"My resting heart rate is {_swift_round(rhr)} versus a usual "
                             f"{_swift_round(base)}. How should I train?"),
                coach_line=(
                    f"Resting HR is {_swift_round(rhr)} against a baseline near {_swift_round(base)}. "
                    f"That's a real gap. I'd skip intensity and see how sleep and how you feel look tonight."
                    if concern else
                    "Resting HR is a bit high versus your usual. Easy movement is fine; I'd keep the "
                    "hard work for a better signal."
                ),
            ))

    if reading.hrv_ms is not None and reading.hrv_baseline_ms is not None and reading.hrv_baseline_ms > 0:
        hrv = reading.hrv_ms
        base = reading.hrv_baseline_ms
        drop = base - hrv
        if drop >= HRV_DROP_ABSOLUTE or hrv <= base * (1 - HRV_DROP_FRACTION):
            concern = drop >= HRV_DROP_ABSOLUTE * 1.4 or hrv <= base * 0.65
            findings.append(AriaHealthRiskFinding(
                kind=HRV_DROP,
                severity=CONCERN if concern else WATCH,
                title="HRV looks low",
                body=(f"HRV is {_swift_round(hrv)} ms versus a usual {_swift_round(base)} ms. "
                      f"That's a recovery hint, not a diagnosis."),
                chat_opener=(f"My HRV dropped to {_swift_round(hrv)} ms from about {_swift_round(base)} ms. "
                             f"What should today look like?"),
                coach_line=(
                    f"HRV is well below your baseline ({_swift_round(hrv)} vs {_swift_round(base)} ms). "
                    f"I'd treat today as restore: walk, food, earlier night — not a PR."
                    if concern else
                    "HRV is softer than your usual. A lighter day protects tomorrow better than pushing through."
                ),
            ))

    return sorted(findings, key=lambda f: f.rank, reverse=True)


def primary(findings: list[AriaHealthRiskFinding]) -> AriaHealthRiskFinding | None:
    return findings[0] if findings else None


_CHAT_NEEDLES = (
    "temp", "fever", "hot", "chills", "sick", "unwell", "ill",
    "hrv", "resting heart", "heart rate", "recovery", "readiness",
    "why am i tired", "feel off", "feel awful", "don't feel", "dont feel",
    "wrist", "watch say", "apple watch",
)


def should_surface_in_chat(text: str) -> bool:
    """Surface a finding in chat when the human is asking about how they
    feel, temperature, or recovery -- not on "what's for dinner"."""
    lower = text.lower()
    return any(needle in lower for needle in _CHAT_NEEDLES)


# --- Cooldown ------------------------------------------------------------
# Mirrors AriaHealthRiskCooldown (Swift L214-225). Genuinely pure: the
# caller supplies lastNotified and persists it themselves, unlike a
# "Store" module.

COOLDOWN_INTERVAL_SECONDS = 8 * 3600


def should_notify(last_notified: datetime | None, now: datetime | None = None) -> bool:
    if now is None:
        now = datetime.now()
    if last_notified is None:
        return True
    return (now - last_notified).total_seconds() >= COOLDOWN_INTERVAL_SECONDS


def storage_key(kind: str) -> str:
    return f"forge.aria.risk.lastNotified.{kind}"
