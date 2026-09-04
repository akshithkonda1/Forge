from __future__ import annotations

from typing import Any, Optional

# Deterministic debrief tier for the Watch app's "deeper coaching" call
# (`POST /watch/aria/suggest`). Mirrors the on-device
# MindfulnessSuggestionEngine's voice contract exactly: two sentences,
# supportive, pattern-focused, never guilt. This function is the
# guaranteed fallback the watch renders even if a future Bedrock upgrade
# layer (see aria_engine.bedrock_enabled()) fails or times out.

_PRACTICE_LABELS = {
    "physiologicalSigh": "physiological sigh",
    "boxBreathing": "box breathing",
    "focusReset": "focus reset",
    "bodyScan": "body scan",
    "windDown": "wind-down",
    "morningGrounding": "morning grounding",
    "stressRelease": "stress release",
}

_DESK_MODES = {"deskCoding", "deepFocus"}
_SLEEP_DISRUPTORS = {"lateCaffeine", "stress", "screens", "alcohol", "lateWorkout"}


def _readiness_band(overall: Optional[float], confidence: Optional[float]) -> Optional[str]:
    """None when there isn't enough signal to trust a band — epistemic
    honesty carries over from the on-device engine."""
    if overall is None or confidence is None or confidence < 0.4:
        return None
    if overall >= 85:
        return "primed"
    if overall >= 70:
        return "ready"
    if overall >= 55:
        return "moderate"
    return "recovery"


def _biofeedback_line(bpm_settle: Optional[float]) -> Optional[str]:
    """Only ever reports a clear, positive-or-neutral shift — never a
    negative verdict, matching the watch's own biofeedback framing."""
    if bpm_settle is None:
        return None
    if bpm_settle >= 3:
        return f"Heart rate settled about {round(bpm_settle)} bpm over the session — a real downshift."
    if bpm_settle >= 1:
        return "Heart rate eased slightly — the direction that matters."
    return None


def generate_debrief(
    context: dict[str, Any],
    practice: str,
    minutes: float,
    heart_rate_settle_bpm: Optional[float],
) -> dict[str, str]:
    label = _PRACTICE_LABELS.get(practice, "reset")
    mode = context.get("lifestyleMode")
    sleep_factors = set(context.get("sleepFactors") or [])
    hours_since_workout = context.get("hoursSinceLastWorkout")
    band = _readiness_band(context.get("readinessOverall"), context.get("readinessConfidence"))

    if practice == "bodyScan" and hours_since_workout is not None and hours_since_workout <= 1.0:
        base = f"That {label} just turned today's training into recovery, not just effort."
        trigger = "post-workout-debrief"
    elif mode in _DESK_MODES:
        base = f"That {label} is exactly what keeps a long focus block sustainable."
        trigger = "desk-block-debrief"
    elif band == "recovery":
        base = f"On a lighter-touch day, choosing this {label} was the strong move, not the easy one."
        trigger = "recovery-day-debrief"
    elif sleep_factors & _SLEEP_DISRUPTORS:
        base = f"Given what shaped last night, this {label} is a good counterweight."
        trigger = "sleep-factor-debrief"
    else:
        base = f"That {label} counts fully, whatever else today looks like."
        trigger = "default-debrief"

    closer = _biofeedback_line(heart_rate_settle_bpm)
    if not closer:
        closer = "You can live your best life and still be healthy — this is exactly that, in practice."

    return {"message": f"{base} {closer}", "trigger": trigger}
