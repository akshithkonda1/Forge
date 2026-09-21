"""Apple Watch-derived metabolic hints when no CGM is connected.

Python port of ForgeCore's ``MetabolicWatchSignals.swift``. Honesty contract:
every line names its source, and interpreting lines say "estimate". Never a
score, never a diagnosis.
"""

from __future__ import annotations

from dataclasses import dataclass


@dataclass(frozen=True)
class MetabolicWatchInputs:
    resting_hr_bpm: float = 0.0
    hrv_ms: float = 0.0
    hrv_baseline_ms: float = 0.0
    vo2_max: float = 0.0
    active_calories: float = 0.0
    exercise_minutes: float = 0.0
    sleep_hours: float = 0.0
    sleep_baseline_hours: float = 0.0


@dataclass(frozen=True)
class MetabolicWatchSignal:
    id: str
    title: str
    line: str

    def to_dict(self) -> dict:
        return {"id": self.id, "title": self.title, "line": self.line}


@dataclass(frozen=True)
class MetabolicWatchEstimate:
    signals: tuple[MetabolicWatchSignal, ...]
    summary_line: str

    @property
    def has_signals(self) -> bool:
        return bool(self.signals)

    def to_dict(self) -> dict:
        return {
            "signals": [s.to_dict() for s in self.signals],
            "summaryLine": self.summary_line,
            "hasSignals": self.has_signals,
            "displayLines": [s.line for s in self.signals],
        }


EMPTY = MetabolicWatchEstimate(signals=(), summary_line="")


def _plausible(value: float, lo: float, hi: float) -> float | None:
    if value <= 0 or value < lo or value > hi:
        return None
    return value


def _swift_round(value: float) -> int:
    return int(value + 0.5) if value >= 0 else -int(-value + 0.5)


def evaluate(
    inputs: MetabolicWatchInputs,
    *,
    source: str = "Apple Watch",
) -> MetabolicWatchEstimate:
    """``source`` names the sensor. Swift callers keep ``Apple Watch``; the
    shared sidecar uses ``wearable`` so Android is not told a lie."""
    label = (source or "Apple Watch").strip() or "Apple Watch"
    signals: list[MetabolicWatchSignal] = []

    vo2 = _plausible(inputs.vo2_max, 15, 80)
    if vo2 is not None:
        signals.append(MetabolicWatchSignal(
            id="cardio-fitness",
            title="Cardio fitness",
            line=f"≈ {_swift_round(vo2)} — estimated by {label}",
        ))

    rhr = _plausible(inputs.resting_hr_bpm, 25, 120)
    if rhr is not None:
        signals.append(MetabolicWatchSignal(
            id="resting-hr",
            title="Resting heart rate",
            line=f"{_swift_round(rhr)} bpm today — {label}",
        ))

    hrv = _plausible(inputs.hrv_ms, 5, 300)
    if hrv is not None:
        base = _plausible(inputs.hrv_baseline_ms, 5, 300)
        if base is not None:
            line = f"{_swift_round(hrv)} ms vs your recent {_swift_round(base)} ms — {label} estimate"
        else:
            line = f"{_swift_round(hrv)} ms today — {label}"
        signals.append(MetabolicWatchSignal(id="hrv", title="Heart rate variability", line=line))

    calories = _swift_round(inputs.active_calories) if inputs.active_calories > 0 else None
    minutes = _swift_round(inputs.exercise_minutes) if inputs.exercise_minutes > 0 else None
    if calories is not None or minutes is not None:
        bits = []
        if calories is not None:
            bits.append(f"{calories} active calories")
        if minutes is not None:
            bits.append(f"{minutes} exercise minutes")
        signals.append(MetabolicWatchSignal(
            id="movement",
            title="Movement",
            line=f"{' · '.join(bits)} today — {label}",
        ))

    sleep = _plausible(inputs.sleep_hours, 0.5, 16)
    if sleep is not None:
        usual = _plausible(inputs.sleep_baseline_hours, 0.5, 16)
        if usual is not None:
            line = f"{sleep:.1f} h vs your usual {usual:.1f} h — {label} estimate"
        else:
            line = f"{sleep:.1f} h last night — {label}"
        signals.append(MetabolicWatchSignal(id="sleep", title="Sleep", line=line))

    if len(signals) < 2:
        return EMPTY

    return MetabolicWatchEstimate(
        signals=tuple(signals),
        summary_line=(
            f"No glucose sensor connected. These are estimates from {label} "
            "trends — not measurements, and not medical advice."
        ),
    )
