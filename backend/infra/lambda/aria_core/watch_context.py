"""WatchARIAContext — lightweight wrist payload, JSON-friendly.

Python port of ForgeCore's ``WatchARIAContext.swift`` (signals only, no
HealthKit). Field names keep the iOS camelCase on the wire so Swift and
Kotlin decode the same object.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from .aria_health_risk_monitor import SLIGHTLY_HIGH_BODY_TEMP_F, WRIST_RISE_WATCH_C

SKIP_TOO_BUSY = "tooBusy"
SKIP_NOT_FEELING_IT = "notFeelingIt"
SKIP_ALREADY_DID_ONE = "alreadyDidOne"
SKIP_LATER_TODAY = "laterToday"


def _num(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _int(value: Any) -> int | None:
    number = _num(value)
    if number is None:
        return None
    return int(number)


@dataclass
class WatchContext:
    timestamp: datetime = field(default_factory=lambda: datetime.now(timezone.utc))
    readiness_overall: int | None = None
    readiness_confidence: float | None = None
    hrv_recent_ms: float | None = None
    hrv_trend_ms: float | None = None
    sleep_minutes: float | None = None
    deep_sleep_minutes: float | None = None
    rem_sleep_minutes: float | None = None
    sleep_quality_score: int | None = None
    lifestyle_mode: str | None = None
    minutes_in_current_mode: float | None = None
    hours_since_last_workout: float | None = None
    last_workout_type: str | None = None
    mindful_minutes_today: float | None = None
    sessions_completed_today: int | None = None
    recent_skip_reason: str | None = None
    sleep_factors: list[str] = field(default_factory=list)
    body_temperature_f: float | None = None
    wrist_temperature_deviation_c: float | None = None
    user_name: str | None = None

    @property
    def hour_of_day(self) -> int:
        return self.timestamp.hour

    @property
    def is_morning(self) -> bool:
        return 5 <= self.hour_of_day < 11

    @property
    def is_evening(self) -> bool:
        return self.hour_of_day >= 20 or self.hour_of_day < 4

    @property
    def hrv_is_dipping(self) -> bool:
        if self.hrv_trend_ms is None:
            return False
        return self.hrv_trend_ms <= -5

    @property
    def in_long_desk_block(self) -> bool:
        if self.lifestyle_mode not in ("deskCoding", "deepFocus"):
            return False
        if self.minutes_in_current_mode is None:
            return False
        return self.minutes_in_current_mode >= 90

    @property
    def just_finished_workout(self) -> bool:
        if self.hours_since_last_workout is None:
            return False
        return self.hours_since_last_workout <= 0.75

    @property
    def temperature_looks_high(self) -> bool:
        if self.body_temperature_f is not None and self.body_temperature_f >= SLIGHTLY_HIGH_BODY_TEMP_F:
            return True
        if (
            self.wrist_temperature_deviation_c is not None
            and self.wrist_temperature_deviation_c >= WRIST_RISE_WATCH_C
        ):
            return True
        return False

    @classmethod
    def from_payload(cls, payload: dict[str, Any] | None) -> WatchContext:
        raw = payload if isinstance(payload, dict) else {}
        stamp = raw.get("timestamp")
        if isinstance(stamp, str):
            try:
                timestamp = datetime.fromisoformat(stamp.replace("Z", "+00:00"))
            except ValueError:
                timestamp = datetime.now(timezone.utc)
        elif isinstance(stamp, datetime):
            timestamp = stamp
        else:
            timestamp = datetime.now(timezone.utc)
        hour = _int(raw.get("hourOfDay"))
        if hour is not None and raw.get("timestamp") is None:
            timestamp = timestamp.replace(hour=max(0, min(23, hour)), minute=0, second=0, microsecond=0)
        factors = raw.get("sleepFactors") or []
        if not isinstance(factors, list):
            factors = []
        return cls(
            timestamp=timestamp,
            readiness_overall=_int(raw.get("readinessOverall")),
            readiness_confidence=_num(raw.get("readinessConfidence")),
            hrv_recent_ms=_num(raw.get("hrvRecentMs")),
            hrv_trend_ms=_num(raw.get("hrvTrendMs")),
            sleep_minutes=_num(raw.get("sleepMinutes")),
            deep_sleep_minutes=_num(raw.get("deepSleepMinutes")),
            rem_sleep_minutes=_num(raw.get("remSleepMinutes")),
            sleep_quality_score=_int(raw.get("sleepQualityScore")),
            lifestyle_mode=str(raw["lifestyleMode"]) if raw.get("lifestyleMode") else None,
            minutes_in_current_mode=_num(raw.get("minutesInCurrentMode")),
            hours_since_last_workout=_num(raw.get("hoursSinceLastWorkout")),
            last_workout_type=str(raw["lastWorkoutType"]) if raw.get("lastWorkoutType") else None,
            mindful_minutes_today=_num(raw.get("mindfulMinutesToday")),
            sessions_completed_today=_int(raw.get("sessionsCompletedToday")),
            recent_skip_reason=str(raw["recentSkipReason"]) if raw.get("recentSkipReason") else None,
            sleep_factors=[str(item) for item in factors],
            body_temperature_f=_num(raw.get("bodyTemperatureF")),
            wrist_temperature_deviation_c=_num(raw.get("wristTemperatureDeviationC")),
            user_name=str(raw["userName"]).strip() if raw.get("userName") else None,
        )
