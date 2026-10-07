"""How this person tends to work — Python port of ForgeCore UserWorkingModel.

Lifestyle framing only. Never a diagnosis, treatment, or clinical
mental-health claim. ARIA reads the tags and steering line.
"""

from __future__ import annotations

from dataclasses import dataclass
from typing import Any


OVERREACHER = "overreacher"
PROTECTOR = "protector"
WEEKEND_DROP = "weekend_drop"
REBUILDING = "rebuilding"
STEADY = "steady"
UNKNOWN = "unknown"

CAP_HEROICS = "cap_heroics"
HOLD_THE_LINE = "hold_the_line"
REBUILD_TRUST = "rebuild_trust"
KEEP_RHYTHM = "keep_rhythm"

AVAILABLE = "available"
MIXED = "mixed"
FLAT = "flat"


@dataclass
class WorkingInput:
    habit_streak_days: int = 0
    today_habit_completion: float | None = None
    weekly_mood_0_to_10: float | None = None
    acwr: float | None = None
    sleep_scores: list[int] | None = None
    readiness_today: int | None = None
    high_strain_low_recovery_days: int = 0
    weekday_sleep_avg: float | None = None
    weekend_sleep_avg: float | None = None


@dataclass
class Driver:
    title: str
    detail: str


@dataclass
class Snapshot:
    tendency: str
    stance: str
    predicted_feel: str
    confidence: str
    drivers: list[Driver]
    steering_line: str

    @property
    def aria_tags(self) -> list[str]:
        return [
            f"working:{self.tendency}:{self.stance}",
            f"working:feel:{self.predicted_feel}",
            f"working:confidence:{self.confidence}",
        ]

    @property
    def keep_light(self) -> bool:
        return self.stance == CAP_HEROICS

    def to_dict(self) -> dict[str, Any]:
        return {
            "tendency": self.tendency,
            "stance": self.stance,
            "predictedFeel": self.predicted_feel,
            "confidence": self.confidence,
            "steeringLine": self.steering_line,
            "ariaTags": self.aria_tags,
            "drivers": [{"title": d.title, "detail": d.detail} for d in self.drivers],
        }


def parse_tag(token: str) -> tuple[str, str] | None:
    parts = str(token or "").split(":")
    if len(parts) < 3 or parts[0] != "working":
        return None
    tendency, stance = parts[1], parts[2]
    if tendency not in (OVERREACHER, PROTECTOR, WEEKEND_DROP, REBUILDING, STEADY, UNKNOWN):
        return None
    if stance not in (CAP_HEROICS, HOLD_THE_LINE, REBUILD_TRUST, KEEP_RHYTHM):
        return None
    return tendency, stance


def snapshot(inp: WorkingInput, tomorrow_posture: str | None = None) -> Snapshot:
    drivers: list[Driver] = []
    known = 0
    total = 6
    streak = max(0, int(inp.habit_streak_days or 0))
    completion = inp.today_habit_completion
    if completion is not None:
        completion = max(0.0, min(1.0, float(completion)))
    mood = inp.weekly_mood_0_to_10
    if mood is not None:
        mood = max(0.0, min(10.0, float(mood)))

    if streak > 0 or completion is not None:
        known += 1
        if streak >= 4:
            drivers.append(Driver("Habit rhythm", f"{streak}-day streak holding"))
        elif streak <= 1:
            drivers.append(Driver("Habit rhythm", "Streak is thin — showing up small is the win"))

    if mood is not None:
        known += 1
        if mood <= 4:
            drivers.append(Driver("Week has felt heavy", f"Feel check-in {int(round(mood))}/10"))
        elif mood >= 7:
            drivers.append(Driver("Week has felt solid", f"Feel check-in {int(round(mood))}/10"))

    if inp.acwr is not None:
        known += 1
        if inp.acwr >= 1.5:
            drivers.append(Driver("Load spiking", f"This week is {inp.acwr:.1f}x your usual"))
        elif inp.acwr < 0.8:
            drivers.append(Driver("Load dip", f"This week is {inp.acwr:.1f}x your usual"))

    if inp.sleep_scores:
        known += 1
    if inp.readiness_today is not None:
        known += 1

    weekend_drop = False
    if inp.weekday_sleep_avg is not None or inp.weekend_sleep_avg is not None:
        known += 1
        if (
            inp.weekday_sleep_avg is not None
            and inp.weekend_sleep_avg is not None
            and inp.weekend_sleep_avg <= inp.weekday_sleep_avg - 12
        ):
            weekend_drop = True
            drivers.append(Driver("Weekend drop", "Weekdays hold; weekends run thinner"))
    else:
        total -= 1

    overreach_days = max(0, int(inp.high_strain_low_recovery_days or 0))
    if overreach_days >= 3:
        drivers.append(Driver("Pushing through", f"{overreach_days} heavy days on thin recovery"))

    tendency = _classify(inp, streak, completion, mood, weekend_drop, overreach_days)
    stance = _stance(tendency)
    feel = _feel(inp, mood, tendency, tomorrow_posture)
    coverage = known / max(1, total)
    if coverage >= 0.8:
        confidence = "high"
    elif coverage >= 0.45:
        confidence = "medium"
    else:
        confidence = "low"
    return Snapshot(
        tendency=tendency,
        stance=stance,
        predicted_feel=feel,
        confidence=confidence,
        drivers=drivers,
        steering_line=_steering(tendency, feel),
    )


def _classify(inp, streak, completion, mood, weekend_drop, overreach_days) -> str:
    if overreach_days >= 3 or (inp.acwr or 0) >= 1.5:
        return OVERREACHER
    if weekend_drop:
        return WEEKEND_DROP
    if streak <= 1 and ((completion if completion is not None else 1) < 0.4 or (mood if mood is not None else 10) <= 4):
        return REBUILDING
    if streak >= 5 and (inp.acwr if inp.acwr is not None else 1.0) < 0.8:
        return PROTECTOR
    if streak >= 4 and inp.acwr is not None and 0.8 <= inp.acwr < 1.4 and (mood if mood is not None else 6) >= 5:
        return STEADY
    if streak >= 4 and inp.acwr is None and (mood if mood is not None else 6) >= 5:
        return STEADY
    return UNKNOWN


def _stance(tendency: str) -> str:
    if tendency == OVERREACHER:
        return CAP_HEROICS
    if tendency == WEEKEND_DROP:
        return HOLD_THE_LINE
    if tendency == REBUILDING:
        return REBUILD_TRUST
    return KEEP_RHYTHM


def _feel(inp, mood, tendency, posture) -> str:
    if posture in ("rest", "protect"):
        return FLAT
    if (mood if mood is not None else 6) <= 4:
        return FLAT
    if tendency == OVERREACHER and (inp.acwr or 0) >= 1.3:
        return FLAT
    if posture == "push" and (mood if mood is not None else 6) >= 6:
        return AVAILABLE
    if (inp.readiness_today if inp.readiness_today is not None else 70) >= 80 and (
        mood if mood is not None else 6
    ) >= 6:
        return AVAILABLE
    return MIXED


def _steering(tendency: str, feel: str) -> str:
    if feel == AVAILABLE:
        feel_bit = "Tomorrow is likely to feel available."
    elif feel == MIXED:
        feel_bit = "Tomorrow is likely a mixed-energy day."
    else:
        feel_bit = "Tomorrow is likely to feel flatter — keep the win small."
    if tendency == OVERREACHER:
        tendency_bit = "This person tends to push through a heavy week — cap heroics."
    elif tendency == WEEKEND_DROP:
        tendency_bit = (
            "Weekdays hold and weekends slip — one tiny weekend anchor beats a Monday restart."
        )
    elif tendency == REBUILDING:
        tendency_bit = "They're finding the rhythm again — showing up small is the win."
    elif tendency == PROTECTOR:
        tendency_bit = "They already protect recovery — don't talk them out of the easy session."
    elif tendency == STEADY:
        tendency_bit = "Their rhythm is holding — don't over-coach it."
    else:
        tendency_bit = "Still learning how this person works — stay specific and small."
    return f"{tendency_bit} {feel_bit}"


def picture(forecast, working: Snapshot) -> dict[str, Any]:
    keep = bool(getattr(forecast, "posture", None) in ("protect", "rest") or working.keep_light)
    tags = list(getattr(forecast, "aria_tags", [])) + list(working.aria_tags)
    steering = f"{working.steering_line} {getattr(forecast, 'steering_line', '')}".strip()
    return {
        "keepLight": keep,
        "ariaTags": tags,
        "steeringLine": steering,
        "forecast": forecast.to_dict() if hasattr(forecast, "to_dict") else {},
        "working": working.to_dict(),
    }


_LEGACY_STANCE_MAP: dict[str, str] = {
    "protect": CAP_HEROICS,
    "proceed": KEEP_RHYTHM,
    "fuel": KEEP_RHYTHM,
    "clarify": HOLD_THE_LINE,
}


def normalize_stance(raw: str) -> str:
    """Map legacy contextual-learner stances to picture vocab.

    The Home picture surface and coach path both use the working-model
    family (cap_heroics / hold_the_line / rebuild_trust / keep_rhythm).
    Older subsystems still emit protect / proceed / fuel / clarify.
    This function collapses the two into one so tags are never mixed.
    """
    if raw in (CAP_HEROICS, HOLD_THE_LINE, REBUILD_TRUST, KEEP_RHYTHM):
        return raw
    return _LEGACY_STANCE_MAP.get(raw, KEEP_RHYTHM)
