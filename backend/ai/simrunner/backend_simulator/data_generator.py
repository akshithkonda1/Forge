"""Data generator — turn a 30-day stream into the ARIAContext ARIA receives.

``build_context`` can snapshot any day in the stream, so SimRunner can probe
ARIA at Day 7, 14, 21, 29 and catch failures that only emerge once a pattern
(rising load, accumulating debt, a regime change) has developed.

Mirrors (in spirit, not code — SimRunner stays stdlib-only and must not import
the Lambda package) the missing-data design already shipped in the real
backend's own ``services/aria_engine.py``: presence-based ``has_*`` gates and a
``confidence_ceiling`` that only ever tightens, one reason per missing signal.
Right-sized for this flatter, single-snapshot context — the real engine's 11
domains collapse to one sleep/HRV/resting-HR cluster here, since that's all a
day's ``DailyRecord`` actually has to go missing.
"""

from __future__ import annotations

from dataclasses import dataclass, field

from .behavior_engine import DailyRecord

_CHRONO_SLEEP_TARGET = {"bear": 8.0, "lion": 7.5, "wolf": 7.5, "dolphin": 6.5}
_CHRONO_WAKE_HOUR = {"bear": 7.0, "lion": 6.0, "wolf": 8.5, "dolphin": 6.5}


@dataclass
class ARIAContext:
    # User identity
    user_name: str
    chronotype: str
    experience_level: str
    coaching_style: str
    occupation: str
    life_season: str

    # Today's snapshot
    today: DailyRecord

    # Recent trend (last 7 days)
    hrv_7d_avg: float
    hrv_7d_trend: str            # "rising" | "falling" | "stable"
    sleep_debt_7d_hours: float
    readiness_7d_avg: float
    readiness_trend: str         # "rising" | "falling" | "stable"

    # Training load
    acwr: float
    training_streak: int
    days_since_last_workout: int

    # Chronotype targets
    target_sleep_hours: float
    target_wake_hour: float

    # Flags
    is_overtrained: bool
    is_sleep_deprived: bool
    has_notable_event: bool
    notable_event_note: str | None

    # Raw history (last 14 days)
    history: list[DailyRecord]

    # Missing-data awareness (today's snapshot + 7-day window). Defaults
    # assume nothing is missing, so ARIAContext fixtures hand-built in tests
    # (not going through build_context()) keep working unmodified;
    # build_context() always overrides these with real computed values.
    has_sleep: bool = True
    has_sleep_stages: bool = True
    has_hrv: bool = True
    has_resting_hr: bool = True
    is_data_sparse: bool = False
    hrv_days_available_7d: int = 7
    sleep_nights_available_7d: int = 7
    missing_fields: list[str] = field(default_factory=list)


def _mean(values: list[float]) -> float:
    return sum(values) / len(values) if values else 0.0


def _trend(values: list[float], threshold: float) -> str:
    """Compare the early half of the window to the late half."""
    if len(values) < 4:
        return "stable"
    half = len(values) // 2
    delta = _mean(values[half:]) - _mean(values[:half])
    if delta > threshold:
        return "rising"
    if delta < -threshold:
        return "falling"
    return "stable"


def build_context(stream: list[DailyRecord], profile: dict, day_index: int = 29) -> ARIAContext:
    if not stream:
        raise ValueError("stream is empty")
    day_index = max(0, min(day_index, len(stream) - 1))
    today = stream[day_index]

    window7 = stream[max(0, day_index - 6): day_index + 1]
    chrono = profile.get("chronotype", "bear")
    target_sleep = _CHRONO_SLEEP_TARGET.get(chrono, 8.0)

    hrv_7d = [r.hrv for r in window7 if r.hrv is not None]
    readiness_7d = [r.readiness_score for r in window7]
    # A day with no sleep reading contributes zero debt either way — neutral,
    # not alarmist, consistent with not inventing a worst-case default for
    # data that's simply absent.
    sleep_debt = sum(
        max(0.0, target_sleep - r.total_sleep_hours) for r in window7 if r.total_sleep_hours is not None
    )

    # Training streak + recency.
    streak = 0
    for record in reversed(stream[: day_index + 1]):
        if record.workout_logged:
            streak += 1
        else:
            break
    days_since = 0
    for record in reversed(stream[: day_index + 1]):
        if record.workout_logged:
            break
        days_since += 1

    has_sleep = today.total_sleep_hours is not None
    has_sleep_stages = today.deep_sleep_minutes is not None and today.rem_sleep_minutes is not None
    has_hrv = today.hrv is not None
    has_resting_hr = today.resting_hr is not None
    # Unusable only when *none* of today's signal-bearing fields are present —
    # mirrors the real backend's own OR-based "usable" gate, right-sized for
    # this context's one sleep/HRV/resting-HR cluster.
    is_data_sparse = not (has_sleep or has_hrv or has_resting_hr)
    hrv_days_available_7d = sum(1 for r in window7 if r.hrv is not None)
    sleep_nights_available_7d = sum(1 for r in window7 if r.total_sleep_hours is not None)
    missing_fields = [
        name for name, value in (
            ("today.total_sleep_hours", today.total_sleep_hours),
            ("today.deep_sleep_minutes", today.deep_sleep_minutes),
            ("today.rem_sleep_minutes", today.rem_sleep_minutes),
            ("today.sleep_score", today.sleep_score),
            ("today.hrv", today.hrv),
            ("today.resting_hr", today.resting_hr),
        ) if value is None
    ]

    return ARIAContext(
        user_name=str(profile.get("occupation", "user")).title().split("→")[0],
        chronotype=chrono,
        experience_level=profile.get("experience_level", "intermediate"),
        coaching_style=profile.get("coaching_style", "balanced"),
        occupation=profile.get("occupation", "unknown"),
        life_season=profile.get("season", "maintenance"),
        today=today,
        hrv_7d_avg=round(_mean(hrv_7d), 1),
        hrv_7d_trend=_trend(hrv_7d, threshold=2.0),
        sleep_debt_7d_hours=round(sleep_debt, 1),
        readiness_7d_avg=round(_mean(readiness_7d), 1),
        readiness_trend=_trend(readiness_7d, threshold=3.0),
        acwr=today.acwr,
        training_streak=streak,
        days_since_last_workout=days_since,
        target_sleep_hours=target_sleep,
        target_wake_hour=_CHRONO_WAKE_HOUR.get(chrono, 7.0),
        is_overtrained=today.acwr > 1.4,
        is_sleep_deprived=sleep_debt > 4.0,
        has_notable_event=today.notes is not None,
        notable_event_note=today.notes,
        history=stream[max(0, day_index - 13): day_index + 1],
        has_sleep=has_sleep,
        has_sleep_stages=has_sleep_stages,
        has_hrv=has_hrv,
        has_resting_hr=has_resting_hr,
        is_data_sparse=is_data_sparse,
        hrv_days_available_7d=hrv_days_available_7d,
        sleep_nights_available_7d=sleep_nights_available_7d,
        missing_fields=missing_fields,
    )


def confidence_ceiling(context: ARIAContext) -> tuple[float, list[str]]:
    """Hard cap on reported confidence given how much raw signal actually
    reached this context. Mirrors backend/infra/lambda/services/aria_engine.py's
    ``_calibrate_confidence`` ceiling mechanic: starts unrestricted, only ever
    tightens, applied last so nothing upstream can breach it, one
    human-readable reason per missing signal. SimRunner has no permission
    system, so every reason here is a "missing," never a "restricted" — the
    real engine's other distinction doesn't apply here."""
    ceiling = 1.0
    reasons: list[str] = []
    if not context.has_sleep:
        ceiling = min(ceiling, 0.55)
        reasons.append("no sleep data")
    elif not context.has_sleep_stages:
        ceiling = min(ceiling, 0.85)
        reasons.append("sleep stages unavailable (duration only)")
    if not context.has_hrv:
        ceiling = min(ceiling, 0.65)
        reasons.append("no HRV — readiness scoring degraded, using sleep proxies")
    elif context.hrv_days_available_7d < 3:
        ceiling = min(ceiling, 0.5)
        reasons.append(f"only {context.hrv_days_available_7d} day(s) of HRV this week")
    return round(ceiling, 2), reasons
