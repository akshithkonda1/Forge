from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

_PROVIDER_MAP = {
    "APPLE": "apple-health",
    "APPLE_HEALTH": "apple-health",
    "OURA": "oura",
    "WHOOP": "whoop",
    "GARMIN": "garmin",
    "STRAVA": "strava",
    "FITBIT": "manual",
    "POLAR": "manual",
    "PELOTON": "manual",
    "FREESTYLELIBRE": "manual",
    "MYFITNESSPAL": "manual",
}

_DISPLAY_NAMES = {
    "apple-health": "Apple Health",
    "oura": "Oura Ring",
    "whoop": "WHOOP",
    "garmin": "Garmin",
    "strava": "Strava",
    "manual": "Connected Device",
}


def map_provider(provider: str | None) -> str:
    if not provider:
        return "manual"
    return _PROVIDER_MAP.get(provider.upper().replace("-", "_"), "manual")


def display_name(provider: str | None) -> str:
    return _DISPLAY_NAMES.get(map_provider(provider), provider or "Connected Device")


def _iso_or_now(value: str | None) -> str:
    if value:
        return value
    return datetime.now(timezone.utc).isoformat()


def _date_from_payload(payload: dict[str, Any]) -> str:
    metadata = payload.get("metadata") or {}
    for key in ("end_time", "start_time", "timestamp"):
        raw = metadata.get(key)
        if isinstance(raw, str) and len(raw) >= 10:
            return raw[:10]
    return datetime.now(timezone.utc).date().isoformat()


def normalize_sleep(payload: dict[str, Any]) -> dict[str, Any] | None:
    data = payload.get("data") or payload.get("sleep") or []
    if isinstance(data, dict):
        data = [data]
    if not data:
        return None

    session = data[-1]
    metadata = session.get("metadata") or {}
    provider = map_provider(metadata.get("upload_type") or payload.get("user", {}).get("provider"))
    sleep_durations = session.get("sleep_durations_data") or {}
    asleep = sleep_durations.get("asleep") or {}
    awake = sleep_durations.get("awake") or {}
    other = sleep_durations.get("other") or {}

    total_seconds = int(asleep.get("duration_asleep_state_seconds") or session.get("duration_asleep_state_seconds") or 0)
    deep_seconds = int(asleep.get("duration_deep_sleep_state_seconds") or 0)
    rem_seconds = int(asleep.get("duration_REM_sleep_state_seconds") or 0)
    light_seconds = int(asleep.get("duration_light_sleep_state_seconds") or 0)
    awake_seconds = int(awake.get("duration_awake_state_seconds") or 0)
    in_bed_seconds = int(other.get("duration_in_bed_seconds") or total_seconds + awake_seconds)

    total_minutes = max(total_seconds // 60, 0)
    score = int(session.get("sleep_score") or session.get("readiness_data", {}).get("readiness") or 75)

    return {
        "date": _date_from_payload({"metadata": metadata}),
        "totalHours": round(total_minutes / 60, 2),
        "deepMinutes": deep_seconds // 60,
        "remMinutes": rem_seconds // 60,
        "lightMinutes": light_seconds // 60,
        "awakeMinutes": awake_seconds // 60,
        "score": min(max(score, 0), 100),
        "sources": [provider],
        "source": provider,
        "middleware": "terra",
        "efficiency": round((total_seconds / in_bed_seconds) * 100, 1) if in_bed_seconds else None,
        "syncedAt": _iso_or_now(metadata.get("end_time")),
    }


def normalize_daily(payload: dict[str, Any]) -> list[dict[str, Any]]:
    data = payload.get("data") or payload.get("daily") or []
    if isinstance(data, dict):
        data = [data]
    metrics: list[dict[str, Any]] = []

    for day in data:
        metadata = day.get("metadata") or {}
        provider = map_provider(metadata.get("upload_type") or payload.get("user", {}).get("provider"))
        started_at = _iso_or_now(metadata.get("start_time"))

        distance = day.get("distance_data") or {}
        calories = day.get("calories_data") or {}
        heart_rate = day.get("heart_rate_data") or {}
        summary = heart_rate.get("summary") or {}

        steps = day.get("steps") or distance.get("steps")
        if steps is not None:
            metrics.append(
                {
                    "metricType": "steps",
                    "source": provider,
                    "startedAt": started_at,
                    "value": float(steps),
                    "unit": "count",
                    "middleware": "terra",
                }
            )

        active_calories = calories.get("total_burned_calories") or calories.get("net_activity_calories")
        if active_calories is not None:
            metrics.append(
                {
                    "metricType": "active-calories",
                    "source": provider,
                    "startedAt": started_at,
                    "value": float(active_calories),
                    "unit": "kcal",
                    "middleware": "terra",
                }
            )

        resting_hr = summary.get("resting_hr_bpm") or summary.get("resting_heart_rate")
        if resting_hr is not None:
            metrics.append(
                {
                    "metricType": "resting-heart-rate",
                    "source": provider,
                    "startedAt": started_at,
                    "value": float(resting_hr),
                    "unit": "bpm",
                    "middleware": "terra",
                }
            )

        hrv = summary.get("avg_hrv_sdnn") or summary.get("avg_hrv_rmssd")
        if hrv is not None:
            metrics.append(
                {
                    "metricType": "hrv",
                    "source": provider,
                    "startedAt": started_at,
                    "value": float(hrv),
                    "unit": "ms",
                    "middleware": "terra",
                }
            )

    return metrics


def normalize_activity(payload: dict[str, Any]) -> dict[str, Any] | None:
    data = payload.get("data") or payload.get("activity") or []
    if isinstance(data, dict):
        data = [data]
    if not data:
        return None

    activity = data[-1]
    metadata = activity.get("metadata") or {}
    provider = map_provider(metadata.get("upload_type") or payload.get("user", {}).get("provider"))
    started_at = _iso_or_now(metadata.get("start_time"))
    ended_at = metadata.get("end_time")
    duration_seconds = 0
    if started_at and ended_at:
        try:
            start_dt = datetime.fromisoformat(started_at.replace("Z", "+00:00"))
            end_dt = datetime.fromisoformat(str(ended_at).replace("Z", "+00:00"))
            duration_seconds = max(int((end_dt - start_dt).total_seconds()), 0)
        except ValueError:
            duration_seconds = int(activity.get("active_duration_seconds") or 0)

    distance = activity.get("distance_data") or {}
    calories = activity.get("calories_data") or {}
    name = activity.get("name") or metadata.get("name") or "Workout"

    return {
        "id": str(metadata.get("summary_id") or activity.get("id") or started_at),
        "date": started_at[:10],
        "name": name,
        "type": "cardio",
        "duration": max(duration_seconds // 60, 1),
        "volume": float(distance.get("distance_meters") or 0),
        "intensity": "moderate",
        "source": provider,
        "startedAt": started_at,
        "calories": float(calories.get("total_burned_calories") or 0),
        "middleware": "terra",
    }