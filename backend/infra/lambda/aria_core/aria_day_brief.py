"""One-line day brief for Watch Home + complications.

Python port of ForgeCore's ``AriaDayBrief.swift``.
"""

from __future__ import annotations

from .mindfulness_suggestion import MindfulnessRecommendation
from .readiness_calculator import BAND_LABEL, band_for_score
from .watch_context import WatchContext


def line(context: WatchContext, recommendation: MindfulnessRecommendation | None) -> str:
    if context.readiness_overall is not None and (context.readiness_confidence or 0) > 0:
        band = band_for_score(context.readiness_overall)
        readiness_bit = f"Readiness {context.readiness_overall} ({BAND_LABEL[band]})"
    else:
        readiness_bit = "Still gathering readiness"

    if context.sleep_quality_score is not None:
        quality = context.sleep_quality_score
        if quality < 60:
            sleep_bit = "sleep ran short"
        elif quality >= 80:
            sleep_bit = "sleep looked solid"
        else:
            sleep_bit = "sleep was okay"
    elif context.sleep_minutes and context.sleep_minutes > 0:
        hours = context.sleep_minutes / 60.0
        sleep_bit = f"slept {hours:.1f}h"
    else:
        sleep_bit = "sleep still syncing"

    if recommendation is not None:
        action_bit = f"Next: {recommendation.duration_label} {recommendation.display_name}"
    else:
        action_bit = "Next: a short reset when you want it"

    return f"{readiness_bit} · {sleep_bit}. {action_bit}."
