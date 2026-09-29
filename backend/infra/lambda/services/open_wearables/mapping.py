"""Turn an Open Wearables webhook (or pull-API sample) into Forge ingest payloads.

This module does not call DynamoDB, Cognito, or Open Wearables. A later route
can take ``AdaptedIngest`` and POST it through the existing ``/health/batch``,
``/ai/observe``, ``/sleep/sessions``, and ``/workouts/logs`` handlers.
"""

from __future__ import annotations

from dataclasses import dataclass, field
from datetime import datetime, timezone
from typing import Any

from .vocabulary import ForgeMetricSpec, map_open_wearables_type, sleep_stage_spec

# Providers ``POST /health/batch`` already accepts. Others stay on /ai/observe.
_BATCH_SOURCES = {
    "apple-health",
    "oura",
    "whoop",
    "garmin",
    "strava",
    "manual",
    "ultrahuman",
    "withings",
    "inbody",
    "fitbit",
    "eight-sleep",
    "polar",
}

_PROVIDER_ALIASES = {
    "apple_health": "apple-health",
    "applehealth": "apple-health",
    "healthkit": "apple-health",
    "google_health": "google-health",
    "google_health_connect": "google-health-connect",
    "samsung_health": "samsung-health",
}


@dataclass(frozen=True)
class ForgeSample:
    metric_type: str
    value: float
    unit: str
    started_at: str
    source: str
    ended_at: str | None = None
    stage: str | None = None
    is_daily_total: bool | None = None
    device: str | None = None


@dataclass
class AdaptedIngest:
    """Mapped Open Wearables event ready for Forge routes."""

    cognito_sub: str
    external_user_id: str | None
    event_type: str
    health_batch: dict[str, Any]
    observe: dict[str, Any]
    sleep_session: dict[str, Any] | None = None
    workout: dict[str, Any] | None = None
    connection: dict[str, Any] | None = None
    rejected: list[dict[str, Any]] = field(default_factory=list)


def adapt_webhook(event: dict[str, Any], *, cognito_sub: str) -> AdaptedIngest:
    """Map one Open Wearables webhook envelope onto Forge ingest payloads.

    ``cognito_sub`` is required and becomes every payload's user key. The
    Open Wearables ``user_id`` is recorded as ``external_user_id`` only.
    """
    sub = (cognito_sub or "").strip()
    if not sub:
        raise ValueError("cognito_sub is required; Open Wearables user_id is not a Forge user key.")
    if not isinstance(event, dict):
        raise ValueError("event must be an object.")

    event_type = str(event.get("type") or "")
    data = event.get("data") if isinstance(event.get("data"), dict) else {}
    external = _external_user_id(event, data)
    source = normalize_provider(_provider(data))

    samples: list[ForgeSample] = []
    rejected: list[dict[str, Any]] = []
    sleep_session: dict[str, Any] | None = None
    workout: dict[str, Any] | None = None
    connection: dict[str, Any] | None = None

    if event_type.endswith(".created") and "samples" in data:
        mapped, rejects = _map_timeseries(data, source)
        samples.extend(mapped)
        rejected.extend(rejects)
    elif event_type == "sleep.created":
        sleep_session, extra, rejects = _map_sleep(data, source)
        samples.extend(extra)
        rejected.extend(rejects)
    elif event_type == "workout.created":
        workout, extra, rejects = _map_workout(data, source)
        samples.extend(extra)
        rejected.extend(rejects)
    elif event_type in {"connection.created", "connection.revoked"}:
        connection = _map_connection(data, event_type, source)
    elif event_type:
        rejected.append({"reason": f"unhandled event type '{event_type}'", "raw": event_type})
    else:
        rejected.append({"reason": "missing event type", "raw": None})

    return AdaptedIngest(
        cognito_sub=sub,
        external_user_id=external,
        event_type=event_type,
        health_batch=_to_health_batch(samples, source),
        observe=_to_observe(sub, samples),
        sleep_session=sleep_session,
        workout=workout,
        connection=connection,
        rejected=rejected,
    )


def normalize_provider(raw: str | None) -> str:
    key = (raw or "unknown").strip().lower().replace(" ", "_")
    if key in _PROVIDER_ALIASES:
        return _PROVIDER_ALIASES[key]
    return key.replace("_", "-")


def _external_user_id(event: dict[str, Any], data: dict[str, Any]) -> str | None:
    for blob in (data, event):
        value = blob.get("user_id") or blob.get("userId")
        if value:
            return str(value)
    return None


def _provider(data: dict[str, Any]) -> str:
    source = data.get("source")
    if isinstance(source, dict):
        return str(source.get("provider") or source.get("source") or "")
    if data.get("provider"):
        return str(data["provider"])
    return ""


def _map_timeseries(
    data: dict[str, Any], fallback_source: str
) -> tuple[list[ForgeSample], list[dict[str, Any]]]:
    samples: list[ForgeSample] = []
    rejected: list[dict[str, Any]] = []
    raw_samples = data.get("samples")
    if not isinstance(raw_samples, list):
        rejected.append({"reason": "timeseries event missing samples array", "raw": None})
        return samples, rejected
    for raw in raw_samples:
        if not isinstance(raw, dict):
            rejected.append({"reason": "sample is not an object", "raw": raw})
            continue
        ow_type = str(raw.get("type") or data.get("series_type") or "")
        spec = map_open_wearables_type(ow_type)
        if spec is None:
            rejected.append({"reason": f"unmapped type '{ow_type}'", "raw": ow_type})
            continue
        mapped = _sample_from_raw(raw, spec, fallback_source)
        if mapped is None:
            rejected.append({"reason": f"invalid value for '{ow_type}'", "raw": raw.get("value")})
            continue
        samples.append(mapped)
    return samples, rejected


def _map_sleep(
    data: dict[str, Any], source: str
) -> tuple[dict[str, Any], list[ForgeSample], list[dict[str, Any]]]:
    start = _iso(data.get("start_time") or data.get("startTime"))
    end = _iso(data.get("end_time") or data.get("endTime"))
    asleep_s = _as_float(data.get("sleep_duration_seconds"))
    in_bed_s = _as_float(data.get("duration_seconds"))
    stages = data.get("stages") if isinstance(data.get("stages"), dict) else {}
    date = (start or "")[:10]
    session = {
        "date": date,
        "source": source,
        "startedAt": start,
        "endedAt": end,
        "totalHours": round((asleep_s or in_bed_s or 0.0) / 3600.0, 4) if (asleep_s or in_bed_s) else None,
        "deepMinutes": stages.get("deep_minutes"),
        "remMinutes": stages.get("rem_minutes"),
        "lightMinutes": stages.get("light_minutes"),
        "awakeMinutes": stages.get("awake_minutes"),
        "score": data.get("efficiency_percent"),
        "externalId": data.get("id"),
        "isNap": bool(data.get("is_nap")),
    }
    extras: list[ForgeSample] = []
    rejected: list[dict[str, Any]] = []
    if asleep_s is not None:
        extras.append(
            ForgeSample(
                metric_type="sleep-duration",
                value=asleep_s,
                unit="s",
                started_at=start or _now(),
                source=source,
                ended_at=end,
            )
        )
    for stage_key, forge_stage in (
        ("deep_minutes", "deep"),
        ("rem_minutes", "rem"),
        ("light_minutes", "light"),
        ("awake_minutes", "awake"),
    ):
        minutes = _as_float(stages.get(stage_key))
        spec = sleep_stage_spec(forge_stage)
        if minutes is None or spec is None:
            continue
        extras.append(
            ForgeSample(
                metric_type=spec.name,
                value=minutes * 60.0,
                unit="s",
                started_at=start or _now(),
                source=source,
                ended_at=end,
                stage=forge_stage,
            )
        )
    intervals = data.get("sleep_stage_intervals")
    if isinstance(intervals, list):
        for raw in intervals:
            if not isinstance(raw, dict):
                rejected.append({"reason": "sleep interval is not an object", "raw": raw})
                continue
            stage = str(raw.get("stage") or "")
            spec = sleep_stage_spec(stage)
            interval_start = _iso(raw.get("start_time"))
            interval_end = _iso(raw.get("end_time"))
            seconds = _interval_seconds(interval_start, interval_end)
            if spec is None or seconds is None:
                rejected.append({"reason": f"unmapped sleep stage '{stage}'", "raw": stage})
                continue
            extras.append(
                ForgeSample(
                    metric_type=spec.name,
                    value=seconds,
                    unit="s",
                    started_at=interval_start or start or _now(),
                    source=source,
                    ended_at=interval_end,
                    stage=stage.strip().lower(),
                )
            )
    return session, extras, rejected


def _map_workout(
    data: dict[str, Any], source: str
) -> tuple[dict[str, Any], list[ForgeSample], list[dict[str, Any]]]:
    start = _iso(data.get("start_time") or data.get("startTime"))
    end = _iso(data.get("end_time") or data.get("endTime"))
    duration_s = _as_float(data.get("duration_seconds"))
    duration_min = round(duration_s / 60.0, 4) if duration_s is not None else None
    workout = {
        "startedAt": start,
        "endedAt": end,
        "duration": duration_min,
        "type": data.get("type") or "other",
        "source": source,
        "calories": data.get("calories_kcal"),
        "distance": data.get("distance_meters"),
        "avgHeartRate": data.get("avg_heart_rate_bpm"),
        "maxHeartRate": data.get("max_heart_rate_bpm"),
        "externalId": data.get("id"),
        "device": (data.get("source") or {}).get("device") if isinstance(data.get("source"), dict) else None,
    }
    extras: list[ForgeSample] = []
    rejected: list[dict[str, Any]] = []
    started = start or _now()
    kcal = _as_float(data.get("calories_kcal"))
    if kcal is not None:
        extras.append(
            ForgeSample(
                metric_type="active-energy",
                value=kcal,
                unit="kcal",
                started_at=started,
                source=source,
                ended_at=end,
            )
        )
    meters = _as_float(data.get("distance_meters"))
    if meters is not None:
        extras.append(
            ForgeSample(
                metric_type="distance",
                value=meters,
                unit="m",
                started_at=started,
                source=source,
                ended_at=end,
            )
        )
    return workout, extras, rejected


def _map_connection(data: dict[str, Any], event_type: str, source: str) -> dict[str, Any]:
    status = "connected" if event_type == "connection.created" else "needs-auth"
    return {
        "provider": source or normalize_provider(str(data.get("provider") or "")),
        "status": status,
        "externalConnectionId": data.get("connection_id"),
        "reason": data.get("reason"),
        "at": _iso(data.get("connected_at") or data.get("revoked_at")),
    }


def _sample_from_raw(
    raw: dict[str, Any], spec: ForgeMetricSpec, fallback_source: str
) -> ForgeSample | None:
    value = _as_float(raw.get("value"))
    if value is None:
        return None
    unit = str(raw.get("unit") or spec.unit)
    normalized = _to_canonical(spec, value, unit)
    if normalized is None:
        return None
    source_blob = raw.get("source") if isinstance(raw.get("source"), dict) else {}
    source = normalize_provider(str(source_blob.get("provider") or fallback_source))
    started = _iso(raw.get("timestamp") or raw.get("startedAt") or raw.get("start_time")) or _now()
    daily = raw.get("is_daily_total")
    return ForgeSample(
        metric_type=spec.name,
        value=normalized,
        unit=spec.unit,
        started_at=started,
        source=source,
        ended_at=_iso(raw.get("end_time") or raw.get("endedAt")),
        is_daily_total=daily if isinstance(daily, bool) else None,
        device=source_blob.get("device"),
    )


def _to_canonical(spec: ForgeMetricSpec, value: float, unit: str) -> float | None:
    unit_key = unit.strip().lower().replace("percent", "%")
    if spec.unit == "kg":
        factor = {"kg": 1.0, "g": 0.001, "lb": 0.453592, "lbs": 0.453592}.get(unit_key)
        return None if factor is None and unit_key not in {"", spec.unit} else value * (factor or 1.0)
    if spec.unit == "m":
        factor = {"m": 1.0, "meter": 1.0, "meters": 1.0, "km": 1000.0, "mi": 1609.34, "mile": 1609.34}.get(unit_key)
        return None if factor is None and unit_key not in {"", spec.unit} else value * (factor or 1.0)
    if spec.unit == "kcal":
        factor = {"kcal": 1.0, "cal": 1.0, "kj": 0.239006, "kilojoule": 0.239006}.get(unit_key)
        return None if factor is None and unit_key not in {"", spec.unit} else value * (factor or 1.0)
    if spec.unit == "ms":
        factor = {"ms": 1.0, "s": 1000.0, "sec": 1000.0}.get(unit_key)
        return None if factor is None and unit_key not in {"", spec.unit} else value * (factor or 1.0)
    if spec.unit == "s":
        factor = {"s": 1.0, "sec": 1.0, "min": 60.0, "minutes": 60.0, "h": 3600.0, "hr": 3600.0}.get(unit_key)
        return None if factor is None and unit_key not in {"", spec.unit} else value * (factor or 1.0)
    if spec.unit == "fraction":
        if unit_key in {"%", "pct"} or value > 1.5:
            return value / 100.0
        return value
    if spec.unit == "C":
        if unit_key in {"f", "fahrenheit", "degf"} or (unit_key in {"", spec.unit.lower()} and value > 50):
            return round((value - 32.0) * 5.0 / 9.0, 3)
        return value
    return value


def _to_health_batch(samples: list[ForgeSample], fallback_source: str) -> dict[str, Any]:
    metrics: list[dict[str, Any]] = []
    for sample in samples:
        spec = map_open_wearables_type(sample.metric_type.replace("-", "_"), stage=sample.stage)
        if spec is None:
            # Already a Forge kebab name.
            from .vocabulary import FORGE_METRICS

            spec = FORGE_METRICS.get(sample.metric_type)
        if spec is None or spec.batch_name is None:
            continue
        source = sample.source if sample.source in _BATCH_SOURCES else fallback_source
        if source not in _BATCH_SOURCES:
            continue
        item: dict[str, Any] = {
            "metricType": spec.batch_name,
            "value": _batch_value(spec, sample),
            "unit": spec.batch_unit or spec.unit,
            "startedAt": sample.started_at,
            "source": source,
        }
        if sample.ended_at:
            item["endedAt"] = sample.ended_at
        if spec.batch_name == "sleep-stage" and sample.stage:
            item["stage"] = sample.stage
        if sample.is_daily_total is not None:
            item["isDailyTotal"] = sample.is_daily_total
        metrics.append(item)
    return {"metrics": metrics}


def _batch_value(spec: ForgeMetricSpec, sample: ForgeSample) -> float:
    if spec.batch_name == "sleep-stage" and spec.unit == "s":
        return round(sample.value / 60.0, 4)
    if spec.batch_name == "distance" and spec.unit == "m":
        return sample.value
    return sample.value


def _to_observe(cognito_sub: str, samples: list[ForgeSample]) -> dict[str, Any]:
    payload_samples: list[dict[str, Any]] = []
    for sample in samples:
        metric_type = sample.metric_type
        # ARIA classify already understands sleep-stage + stage, not sleep-deep.
        if sample.stage and metric_type.startswith("sleep-") and metric_type != "sleep-duration":
            metric_type = "sleep-stage"
        item: dict[str, Any] = {
            "metricType": metric_type,
            "value": sample.value,
            "unit": sample.unit,
            "startedAt": sample.started_at,
            "source": sample.source,
        }
        if sample.ended_at:
            item["endedAt"] = sample.ended_at
        if sample.stage:
            item["stage"] = sample.stage
        if sample.device:
            item["device"] = sample.device
        payload_samples.append(item)
    return {"user_id": cognito_sub, "samples": payload_samples}


def _as_float(value: Any) -> float | None:
    if value is None or isinstance(value, bool):
        return None
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _iso(value: Any) -> str | None:
    if isinstance(value, datetime):
        dt = value if value.tzinfo else value.replace(tzinfo=timezone.utc)
        return dt.isoformat()
    if isinstance(value, str) and value.strip():
        try:
            dt = datetime.fromisoformat(value.replace("Z", "+00:00"))
        except ValueError:
            return value
        if dt.tzinfo is None:
            dt = dt.replace(tzinfo=timezone.utc)
        return dt.isoformat()
    return None


def _interval_seconds(start: str | None, end: str | None) -> float | None:
    if not start or not end:
        return None
    try:
        a = datetime.fromisoformat(start.replace("Z", "+00:00"))
        b = datetime.fromisoformat(end.replace("Z", "+00:00"))
    except ValueError:
        return None
    if a.tzinfo is None:
        a = a.replace(tzinfo=timezone.utc)
    if b.tzinfo is None:
        b = b.replace(tzinfo=timezone.utc)
    delta = (b - a).total_seconds()
    return delta if delta >= 0 else None


def _now() -> str:
    return datetime.now(timezone.utc).isoformat()
