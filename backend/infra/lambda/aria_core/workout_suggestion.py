"""Workout suggestion + event/QoL training policy.

Python port of ForgeCore's ``WorkoutSuggestionEngine.swift`` (including
``EventTrainingPolicy`` and ``QualityOfLifeTrainingPolicy``). Native clients
render the session card; this decides type, zone, and volume.
"""

from __future__ import annotations

from dataclasses import dataclass

from .quality_of_life import band_for_score as qol_band
from .readiness_calculator import band_for_score
from .watch_context import WatchContext

RECOVERY = "recovery"
MODERATE = "moderate"
READY = "ready"
PRIMED = "primed"


@dataclass(frozen=True)
class WorkoutSuggestion:
    type: str
    target_zone: int
    reason: str
    trigger: str

    def to_dict(self) -> dict:
        return {
            "type": self.type,
            "targetZone": self.target_zone,
            "reason": self.reason,
            "trigger": self.trigger,
        }


def suggest(context: WatchContext) -> WorkoutSuggestion:
    confidence = context.readiness_confidence or 0
    if context.readiness_overall is None or confidence < 0.4:
        return WorkoutSuggestion(
            type="cardio",
            target_zone=2,
            reason=(
                "I don't have enough data yet to read your recovery, so easy Zone 2 is the honest call. "
                "Move how you feel - we'll calibrate as I learn you."
            ),
            trigger="low-confidence-default",
        )

    band = band_for_score(context.readiness_overall)
    if band == RECOVERY:
        return WorkoutSuggestion(
            type="mobility",
            target_zone=1,
            reason=(
                "Recovery-day readiness - gentle mobility keeps you moving while your body finishes "
                "rebuilding. Easy today is what makes hard possible later this week."
            ),
            trigger="recovery-band",
        )
    if band == MODERATE:
        return WorkoutSuggestion(
            type="cardio",
            target_zone=2,
            reason=(
                "Readiness is middling, so Zone 2 pays the most today - real fitness, low recovery cost. "
                "Save the intensity for a greener day."
            ),
            trigger="moderate-band",
        )
    if band == READY:
        return WorkoutSuggestion(
            type="strength",
            target_zone=3,
            reason="Solid recovery - a proper strength session will land well today. Steady effort, quality reps.",
            trigger="ready-band",
        )
    return WorkoutSuggestion(
        type="hiit",
        target_zone=4,
        reason=(
            "You're primed - today can absorb real intensity if you want it. Reach for it, or bank "
            "the readiness; both are winning."
        ),
        trigger="primed-band",
    )


@dataclass(frozen=True)
class EventTrainingPlan:
    kind: str
    days_until: int
    emphasis: tuple[str, ...]
    progressive: bool
    reduce_volume: bool
    keep_light: bool
    reason: str

    def to_dict(self) -> dict:
        return {
            "kind": self.kind,
            "daysUntil": self.days_until,
            "emphasis": list(self.emphasis),
            "progressive": self.progressive,
            "reduceVolume": self.reduce_volume,
            "keepLight": self.keep_light,
            "reason": self.reason,
        }


def parse_horizon(tags: list[str]) -> list[tuple[str, int]]:
    out: list[tuple[str, int]] = []
    prefix = "calendar:horizon:"
    for tag in tags:
        if not tag.startswith(prefix):
            continue
        rest = tag[len(prefix):]
        parts = rest.split(":")
        if len(parts) != 2:
            continue
        try:
            days = int(parts[1])
        except ValueError:
            continue
        out.append((parts[0], days))
    out.sort(key=lambda item: item[1])
    return out


def _days_word(days: int) -> str:
    return "day" if days == 1 else "days"


def travel_plan(kind: str, days_until: int) -> EventTrainingPlan:
    moving = days_until <= 1
    return EventTrainingPlan(
        kind=kind,
        days_until=days_until,
        emphasis=(),
        progressive=False,
        reduce_volume=True,
        keep_light=moving,
        reason=(
            "Travel day — keep the session able to move, skip the hero work."
            if moving
            else f"There's a trip in {days_until} {_days_word(days_until)} — I'll keep the session able to move."
        ),
    )


def game_plan(days_until: int) -> EventTrainingPlan:
    return EventTrainingPlan(
        kind="game",
        days_until=days_until,
        emphasis=(),
        progressive=False,
        reduce_volume=days_until <= 1,
        keep_light=False,
        reason=(
            "Game day — train around that window, not through it."
            if days_until <= 0
            else f"There's a game in {days_until} {_days_word(days_until)} — we'll train around that window."
        ),
    )


def wedding_plan(days_until: int) -> EventTrainingPlan:
    if days_until <= 0:
        return EventTrainingPlan(
            kind="wedding",
            days_until=days_until,
            emphasis=(),
            progressive=False,
            reduce_volume=True,
            keep_light=True,
            reason="Wedding day — protect the event, skip the hero session.",
        )
    return EventTrainingPlan(
        kind="wedding",
        days_until=days_until,
        emphasis=("chest", "arms", "abs"),
        progressive=True,
        reduce_volume=True,
        keep_light=days_until <= 7,
        reason=(
            f"Wedding in {days_until} {_days_word(days_until)} — progressive lighter loads, "
            "less volume, more recovery, chest/arms/abs so the suit sits right."
        ),
    )


def event_plan(tags: list[str]) -> EventTrainingPlan | None:
    horizon = parse_horizon(tags)
    for kind, days in horizon:
        if kind == "wedding":
            return wedding_plan(days)
    for kind, days in horizon:
        if kind in ("flight", "travel"):
            return travel_plan(kind, days)
    for kind, days in horizon:
        if kind == "game":
            return game_plan(days)
    return None


@dataclass(frozen=True)
class QualityOfLifeTrainingPlan:
    overall: int
    band: str
    keep_light: bool
    reduce_volume: bool
    max_duration: int
    reason: str

    def to_dict(self) -> dict:
        return {
            "overall": self.overall,
            "band": self.band,
            "keepLight": self.keep_light,
            "reduceVolume": self.reduce_volume,
            "maxDuration": self.max_duration,
            "reason": self.reason,
        }


def _parse_qol_overall(tags: list[str]) -> int | None:
    for tag in tags:
        lower = tag.lower()
        if not lower.startswith("qol:"):
            continue
        if lower.startswith(("qol:band:", "qol:driver:", "qol:missing:", "qol:pillar:", "qolconf:")):
            continue
        rest = lower[4:]
        token = rest.split(":", 1)[0]
        try:
            return max(0, min(100, int(token)))
        except ValueError:
            continue
    return None


def _parse_qol_band(tags: list[str]) -> str | None:
    for tag in tags:
        lower = tag.lower()
        if lower.startswith("qol:band:"):
            return lower[len("qol:band:"):]
    return None


def _parse_qol_pillar(tags: list[str], key: str) -> int | None:
    prefix = f"qol:pillar:{key.lower()}:"
    for tag in tags:
        lower = tag.lower()
        if lower.startswith(prefix):
            try:
                return max(0, min(100, int(lower[len(prefix):])))
            except ValueError:
                return None
    return None


def qol_training_plan(
    tags: list[str] | None = None,
    *,
    overall: int | None = None,
    band: str | None = None,
    mind_score: int | None = None,
    sleep_score: int | None = None,
) -> QualityOfLifeTrainingPlan | None:
    if overall is None:
        overall = _parse_qol_overall(tags or [])
    if overall is None:
        return None
    clamped = max(0, min(100, overall))
    resolved_band = band or _parse_qol_band(tags or []) or qol_band(clamped)
    mind = mind_score if mind_score is not None else _parse_qol_pillar(tags or [], "mind")
    sleep = sleep_score if sleep_score is not None else _parse_qol_pillar(tags or [], "sleep")

    if resolved_band == "depleted":
        return QualityOfLifeTrainingPlan(
            overall=clamped,
            band=resolved_band,
            keep_light=True,
            reduce_volume=True,
            max_duration=30,
            reason=f"Lifestyle QoL {clamped}/100 (depleted) — recovery-first session, keep it light.",
        )
    if resolved_band == "strained":
        weak_mind = (mind if mind is not None else 100) < 55
        weak_sleep = (sleep if sleep is not None else 100) < 55
        keep_light = weak_mind or weak_sleep or clamped < 60
        return QualityOfLifeTrainingPlan(
            overall=clamped,
            band=resolved_band,
            keep_light=keep_light,
            reduce_volume=True,
            max_duration=35 if keep_light else 40,
            reason=(
                f"Lifestyle QoL {clamped}/100 (strained) — mind/sleep asking for ease, lighter volume."
                if keep_light
                else f"Lifestyle QoL {clamped}/100 (strained) — trim volume, protect recovery."
            ),
        )
    return None
