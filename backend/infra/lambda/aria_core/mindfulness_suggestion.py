"""Instant mindfulness suggestion for the wrist / Home glance.

Python port of ForgeCore's ``MindfulnessSuggestionEngine.swift``. Breathing
orb Canvas stays native; this returns practice id, duration, reason, trigger.
"""

from __future__ import annotations

from dataclasses import dataclass

from .readiness_calculator import BAND_DESCRIPTOR, band_for_score
from .watch_context import (
    SKIP_ALREADY_DID_ONE,
    SKIP_LATER_TODAY,
    SKIP_NOT_FEELING_IT,
    SKIP_TOO_BUSY,
    WatchContext,
)

PRACTICE_DISPLAY = {
    "physiologicalSigh": "Physiological Sigh",
    "boxBreathing": "Box Breathing",
    "focusReset": "Focus Reset",
    "bodyScan": "Body Scan",
    "windDown": "Wind-Down",
    "morningGrounding": "Morning Grounding",
    "stressRelease": "Stress Release",
}

_MODE_ASIDE = {
    "deskCoding": "I'll watch your focus blocks and only nudge when it genuinely helps.",
    "deepFocus": "I'll watch your focus blocks and only nudge when it genuinely helps.",
    "gym": "When you're ready, I'll meet you at the right effort.",
    "commute": "Use the transit time to arrive settled.",
    "homeRecovery": "Nothing to prove today.",
    "outdoor": "Being outside already counts.",
    "windDown": "Let's keep the evening soft.",
}


@dataclass(frozen=True)
class MindfulnessRecommendation:
    practice: str
    duration: float
    reason: str
    trigger: str

    @property
    def duration_label(self) -> str:
        if self.duration < 120:
            return f"{int(self.duration)}-second"
        return f"{int(self.duration / 60)}-minute"

    @property
    def display_name(self) -> str:
        return PRACTICE_DISPLAY.get(self.practice, self.practice)

    def to_dict(self) -> dict:
        return {
            "practice": self.practice,
            "duration": self.duration,
            "reason": self.reason,
            "trigger": self.trigger,
            "durationLabel": self.duration_label,
            "displayName": self.display_name,
        }


def _base_suggestion(context: WatchContext) -> MindfulnessRecommendation:
    confident = (context.readiness_confidence or 0) >= 0.4

    if context.just_finished_workout:
        return MindfulnessRecommendation(
            practice="bodyScan",
            duration=300,
            reason=(
                "A few minutes of body scan now helps the work you just did become recovery. "
                "Effort and ease belong in the same day."
            ),
            trigger="post-workout-reset",
        )

    if context.temperature_looks_high:
        return MindfulnessRecommendation(
            practice="bodyScan",
            duration=300,
            reason=(
                "Your Watch temperature is running a bit high versus your usual overnight reading. "
                "I'm not diagnosing anything — a clinician can — but ease today is the honest call."
            ),
            trigger="elevated-temperature",
        )

    if context.in_long_desk_block and context.hrv_is_dipping:
        return MindfulnessRecommendation(
            practice="physiologicalSigh",
            duration=90,
            reason=(
                "Long focus block and your HRV looks like it's dipping. A 90-second physiological "
                "sigh helps your nervous system recover without breaking flow."
            ),
            trigger="desk-block-hrv-dip",
        )

    if context.in_long_desk_block:
        return MindfulnessRecommendation(
            practice="focusReset",
            duration=90,
            reason=(
                "You've been locked in for a while — nice work. Ninety seconds of slow breathing "
                "keeps that focus sustainable instead of borrowed."
            ),
            trigger="desk-block-90m",
        )

    if context.is_evening:
        slept_poorly = (context.sleep_quality_score or 100) < 60
        return MindfulnessRecommendation(
            practice="windDown",
            duration=300 if slept_poorly else 240,
            reason=(
                "Last night ran short, so tonight's wind-down matters a little more. "
                "A few slow minutes now tilts the odds toward deeper sleep."
                if slept_poorly
                else (
                    "The day is winding down — this breath pattern tells your body it's safe to follow. "
                    "Rest is part of living well, not time away from it."
                )
            ),
            trigger="evening-wind-down",
        )

    if context.is_morning:
        low_readiness = (context.readiness_overall or 100) < 55 and confident
        return MindfulnessRecommendation(
            practice="morningGrounding",
            duration=180,
            reason=(
                "Your body is asking for a gentler start today, and that's completely fine. "
                "Three grounded minutes set the tone better than pushing would."
                if low_readiness
                else (
                    "A short grounding practice before the day accelerates is the highest-leverage "
                    "three minutes you'll spend. Start how you mean to continue."
                )
            ),
            trigger="low-readiness-morning" if low_readiness else "morning-grounding",
        )

    if context.hrv_is_dipping:
        return MindfulnessRecommendation(
            practice="stressRelease",
            duration=180,
            reason=(
                "Your HRV suggests some accumulated tension. Long exhales are the fastest honest "
                "way to let it go — no willpower required."
            ),
            trigger="hrv-dip",
        )

    if context.readiness_overall is not None and context.readiness_overall < 55 and confident:
        return MindfulnessRecommendation(
            practice="bodyScan",
            duration=300,
            reason=(
                "Recovery-day readiness doesn't mean the day is lost — it means ease pays more "
                "than effort today. This scan is the easy win."
            ),
            trigger="low-readiness",
        )

    return MindfulnessRecommendation(
        practice="focusReset",
        duration=180,
        reason=(
            "A three-minute reset between things keeps your best hours actually yours. "
            "You can live your best life and still be healthy."
        ),
        trigger="default-midday",
    )


def _personalize(rec: MindfulnessRecommendation, context: WatchContext) -> MindfulnessRecommendation:
    skip = context.recent_skip_reason
    if not skip:
        return rec
    if skip in (SKIP_TOO_BUSY, SKIP_LATER_TODAY):
        duration = min(rec.duration, 90)
        return MindfulnessRecommendation(
            practice="physiologicalSigh" if duration <= 90 else rec.practice,
            duration=duration,
            reason="Keeping this under two minutes so it fits the day you actually have. " + rec.reason,
            trigger=rec.trigger + "+short-after-skip",
        )
    if skip == SKIP_NOT_FEELING_IT:
        return MindfulnessRecommendation(
            practice="physiologicalSigh",
            duration=60,
            reason="No pressure — a single minute of slow breath is enough if anything at all feels right.",
            trigger=rec.trigger + "+soft-after-skip",
        )
    if skip == SKIP_ALREADY_DID_ONE:
        return MindfulnessRecommendation(
            practice="focusReset",
            duration=60,
            reason="You already showed up once today — that counts. This is optional, not overdue.",
            trigger=rec.trigger + "+ack-after-skip",
        )
    return rec


def suggest(context: WatchContext) -> MindfulnessRecommendation:
    return _personalize(_base_suggestion(context), context)


def greeting(context: WatchContext, user_name: str | None = None) -> str:
    name = user_name if user_name else context.user_name
    name_bit = f" {name}" if name else ""
    hour = context.hour_of_day
    if 5 <= hour < 12:
        opener = f"Morning{name_bit}."
    elif 12 <= hour < 17:
        opener = f"Afternoon{name_bit}."
    elif 17 <= hour < 21:
        opener = f"Evening{name_bit}."
    else:
        opener = f"Hey{name_bit}."

    if context.readiness_overall is None or not (context.readiness_confidence or 0) > 0:
        return (
            f"{opener} I'm still gathering today's signals — open Forge on your phone "
            "or wear your watch a bit longer and I'll catch up."
        )

    if context.temperature_looks_high:
        return (
            f"{opener} Wrist temperature is a bit high versus your usual overnight reading. "
            "I'm not diagnosing — take it easy, and a clinician is the source of truth if you feel off."
        )
    descriptor = BAND_DESCRIPTOR[band_for_score(context.readiness_overall)]
    if context.lifestyle_mode:
        aside = _MODE_ASIDE.get(context.lifestyle_mode, "")
        if aside:
            return f"{opener} {descriptor} {aside}"
    return f"{opener} {descriptor}"
