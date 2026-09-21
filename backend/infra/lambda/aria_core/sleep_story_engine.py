"""Last night's story + tonight's plan as pure templates.

Python port of ForgeCore's ``SleepStoryEngine.swift``. Native UIs display
the string; this backend owns the copy so iOS and Android do not drift.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

from .wind_down_predictor import WindDownPlan

SLEEP_FACTOR_NOTES = {
    "lateCaffeine": "Caffeine after mid-afternoon tends to trim deep sleep — useful to know, not a verdict.",
    "stress": "A loaded day often shows up as lighter sleep. Naming it already helps.",
    "lateWorkout": "Late training runs the engine warm at lights-out. Worth pairing with a longer wind-down.",
    "screens": "Late screens push the body clock a little later. Small shifts add up.",
    "alcohol": "Alcohol usually costs some REM later in the night. Good context for today's energy.",
}


@dataclass(frozen=True)
class SleepNightStory:
    total_minutes: float
    deep_minutes: float = 0.0
    rem_minutes: float = 0.0
    awake_minutes: float = 0.0

    @property
    def duration_label(self) -> str:
        total = int(self.total_minutes)
        return f"{total // 60}h {total % 60}m"


def story(
    night: SleepNightStory | None,
    readiness_overall: int | None = None,
    factors: list[str] | None = None,
) -> str:
    if night is None or night.total_minutes <= 0:
        return (
            "No sleep data from last night yet — once your watch syncs, I'll tell you the story. "
            "Until then, pace by feel; you know yourself well."
        )

    hours = night.total_minutes / 60
    deep_share = night.deep_minutes / night.total_minutes if night.total_minutes > 0 else 0
    factor_note = ""
    if factors:
        note = SLEEP_FACTOR_NOTES.get(factors[0])
        if note:
            factor_note = f" {note}"

    if hours < 6:
        if readiness_overall is not None:
            readiness_link = (
                f" Today's readiness ({readiness_overall}) reflects it — "
                "a lighter-touch day still counts fully."
            )
        else:
            readiness_link = " A lighter-touch day still counts fully."
        return (
            f"A short night at {night.duration_label} — your body kept what mattered most."
            f"{readiness_link}{factor_note}"
        )

    if deep_share >= 0.18:
        return (
            f"{night.duration_label} with strong deep sleep ({int(night.deep_minutes)} min) — "
            "that's the physical recharge doing its job. Spend it on whatever matters most today."
            f"{factor_note}"
        )

    if night.awake_minutes > 45:
        return (
            f"{night.duration_label} total, but with some wakeful stretches — "
            "the kind of night that feels longer than it restores. Be a little generous with yourself today."
            f"{factor_note}"
        )

    return (
        f"A solid {night.duration_label} — steady architecture, nothing to fix. "
        f"Consistency like this is quietly the whole game.{factor_note}"
    )


def _clock_label(when: datetime) -> str:
    hour = when.hour % 12 or 12
    minute = when.minute
    suffix = "PM" if when.hour >= 12 else "AM"
    return f"{hour}:{minute:02d} {suffix}"


def tonight_plan(
    plan: WindDownPlan | None,
    night: SleepNightStory | None = None,
    high_cognitive_load_day: bool = False,
) -> str:
    if plan is None:
        return (
            "I'm still learning your sleep rhythm — a few more nights and I'll suggest a personal "
            "wind-down time. Tonight, aim for the bedtime that usually feels right."
        )

    wind_down_time = _clock_label(plan.wind_down_start)
    slept_short = (night.total_minutes if night is not None else 480) < 6 * 60
    if high_cognitive_load_day:
        return (
            f"Heavy thinking day — a 4-minute wind-down around {wind_down_time} "
            "gives your mind a runway and tilts tonight toward deep sleep."
        )
    if slept_short:
        return (
            f"After last night, tonight is the easy win: start winding down around "
            f"{wind_down_time} and let the window do the work."
        )
    return (
        f"Your rhythm points to winding down around {wind_down_time}. "
        "A few slow breaths then keeps a good streak of nights going."
    )
