"""How much Forge is worth showing in a glance / Smart Stack.

Python port of ForgeCore's ``SmartStackRelevance.swift``. WidgetKit conversion
stays on the client; this returns the numbers.
"""

from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime

LIVE_SESSION = 100.0
FLAGGED = 60.0
AMBIENT = 20.0
WIND_DOWN_WINDOW_MINUTES = 90.0


@dataclass(frozen=True)
class Relevance:
    score: float
    duration_seconds: float | None = None

    def to_dict(self) -> dict:
        payload = {"score": self.score}
        if self.duration_seconds is not None:
            payload["durationSeconds"] = self.duration_seconds
        return payload


def score(
    *,
    active_workout_phase: str | None = None,
    tonight_wind_down: datetime | None = None,
    recommended_practice: str | None = None,
    now: datetime | None = None,
) -> Relevance | None:
    """``active_workout_phase`` None or ``ended`` means no live session."""
    if now is None:
        now = datetime.now()

    if active_workout_phase is not None and active_workout_phase != "ended":
        return Relevance(score=LIVE_SESSION)

    if tonight_wind_down is not None:
        delta = abs((tonight_wind_down - now).total_seconds())
        if delta <= WIND_DOWN_WINDOW_MINUTES * 60:
            return Relevance(score=FLAGGED, duration_seconds=WIND_DOWN_WINDOW_MINUTES * 60)

    if recommended_practice is not None:
        return Relevance(score=FLAGGED * 0.7)

    return Relevance(score=AMBIENT)
