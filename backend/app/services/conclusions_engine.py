"""Deterministic conclusions layer — algorithms produce facts, not coaching prose."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from services.data_fusion import load_wellness_snapshot


_COVERAGE_FIELDS = (
    "steps",
    "activeCalories",
    "hrv",
    "restingHR",
    "oxygenSaturation",
    "deepSleep",
    "totalSleep",
    "sleepScore",
)


def _coverage_pct(today: dict[str, Any]) -> float:
    present = 0
    for field in _COVERAGE_FIELDS:
        value = today.get(field)
        if value is not None and value != 0:
            present += 1
    return round(present / len(_COVERAGE_FIELDS), 2)


def _signal(
    *,
    id_: str,
    category: str,
    severity: str,
    metric: str,
    value: float | int | None,
    baseline: float | int | None,
    direction: str,
) -> dict[str, Any]:
    return {
        "id": id_,
        "category": category,
        "severity": severity,
        "metric": metric,
        "value": value,
        "baseline": baseline,
        "direction": direction,
    }


def _compound_flags(signals: list[dict[str, Any]], readiness: dict[str, Any]) -> list[str]:
    flags: list[str] = []
    ids = {s["id"] for s in signals}
    overall = int(readiness.get("overall", 0) or 0)

    if "sleep-debt" in ids and "load-spike" in ids:
        flags.append("recovery-debt-under-load")
    if "hrv-suppressed" in ids and overall < 60:
        flags.append("autonomic-stress")
    if "spo2-low" in ids and "sleep-debt" in ids:
        flags.append("sleep-respiratory-stress")
    if "steps-low" in ids and "load-spike" in ids:
        flags.append("high-training-low-movement")
    return flags


def _coaching_brief(
    *,
    readiness: dict[str, Any],
    signals: list[dict[str, Any]],
    compound_flags: list[str],
    training_load: dict[str, Any],
) -> str:
    overall = int(readiness.get("overall", 0) or 0)
    high = [s for s in signals if s["severity"] == "high"]
    parts = [f"Readiness {overall}/100."]

    if compound_flags:
        parts.append(f"Compound flags: {', '.join(compound_flags)}.")
    elif high:
        parts.append(f"Primary signal: {high[0]['metric']} ({high[0]['direction']}).")
    else:
        parts.append("No acute risk flags.")

    trend = training_load.get("trend", "flat")
    parts.append(f"Training load trend: {trend}.")
    return " ".join(parts)


def _offline_templates(
    *,
    readiness: dict[str, Any],
    signals: list[dict[str, Any]],
    compound_flags: list[str],
) -> dict[str, str]:
    overall = int(readiness.get("overall", 0) or 0)
    if "recovery-debt-under-load" in compound_flags:
        chat = "Recovery is lagging under rising load — prioritize sleep and reduce intensity today."
        dashboard = "Recovery debt detected — ease training load."
    elif overall >= 80:
        chat = "Metrics look strong — good day to push performance if planned."
        dashboard = "High readiness — training window open."
    elif overall >= 60:
        chat = "Readiness is moderate — train with controlled volume and monitor recovery."
        dashboard = "Moderate readiness — train smart, not maximal."
    else:
        chat = "Recovery signals are low — favor mobility, sleep, and nutrition today."
        dashboard = "Low readiness — recovery focus recommended."

    mood = "steady"
    if any(s["id"] == "hrv-suppressed" for s in signals):
        mood = "stressed"
    elif overall >= 80:
        mood = "energized"

    return {
        "chat": chat,
        "dashboard": dashboard,
        "mood": mood,
        "widget": f"Readiness {overall}",
    }


def build_data_conclusions(user_id: str, *, date: str | None = None) -> dict[str, Any]:
    """Compute DataConclusions from fused wellness data."""
    snapshot = load_wellness_snapshot(user_id, date=date)
    today = snapshot.get("today") or {}
    readiness_block = snapshot.get("readiness") or {}
    training_load = snapshot.get("trainingLoad") or {}
    rollups = (snapshot.get("rollups") or {}).get("windows", {}).get("7", {})

    signals: list[dict[str, Any]] = []

    hrv_rollup = rollups.get("hrv") or {}
    if hrv_rollup.get("avg") is not None and hrv_rollup.get("priorAvg") is not None:
        if float(hrv_rollup["avg"]) < float(hrv_rollup["priorAvg"]) * 0.9:
            signals.append(_signal(
                id_="hrv-suppressed",
                category="recovery",
                severity="high",
                metric="hrv",
                value=hrv_rollup["avg"],
                baseline=hrv_rollup["priorAvg"],
                direction="down",
            ))

    sleep_score = today.get("sleepScore")
    deep_sleep = today.get("deepSleep")
    if sleep_score is not None and int(sleep_score) < 70:
        signals.append(_signal(
            id_="sleep-debt",
            category="sleep",
            severity="high",
            metric="sleepScore",
            value=sleep_score,
            baseline=75,
            direction="down",
        ))
    elif deep_sleep is not None and int(deep_sleep) < 60:
        signals.append(_signal(
            id_="sleep-debt",
            category="sleep",
            severity="medium",
            metric="deepSleep",
            value=deep_sleep,
            baseline=90,
            direction="down",
        ))

    if training_load.get("trend") == "rising" and int(training_load.get("delta", 0) or 0) > 0:
        signals.append(_signal(
            id_="load-spike",
            category="training",
            severity="medium",
            metric="trainingLoad",
            value=training_load.get("current"),
            baseline=training_load.get("previous"),
            direction="up",
        ))

    spo2 = today.get("oxygenSaturation")
    if spo2 is not None and float(spo2) < 94:
        signals.append(_signal(
            id_="spo2-low",
            category="vitals",
            severity="high",
            metric="oxygenSaturation",
            value=spo2,
            baseline=97,
            direction="down",
        ))

    steps = today.get("steps")
    if steps is not None and int(steps) < 4000:
        signals.append(_signal(
            id_="steps-low",
            category="activity",
            severity="low",
            metric="steps",
            value=steps,
            baseline=8000,
            direction="down",
        ))

    compound_flags = _compound_flags(signals, readiness_block)
    coverage = _coverage_pct(today)

    return {
        "generatedAt": datetime.now(timezone.utc).isoformat(),
        "date": snapshot.get("date"),
        "coveragePct": coverage,
        "readiness": readiness_block,
        "signals": signals,
        "compoundFlags": compound_flags,
        "coachingBrief": _coaching_brief(
            readiness=readiness_block,
            signals=signals,
            compound_flags=compound_flags,
            training_load=training_load,
        ),
        "dashboardHints": {
            "readinessOverall": readiness_block.get("overall"),
            "primaryFlag": compound_flags[0] if compound_flags else (signals[0]["id"] if signals else None),
            "trainingLoadTrend": training_load.get("trend"),
        },
        "offlineTemplates": _offline_templates(
            readiness=readiness_block,
            signals=signals,
            compound_flags=compound_flags,
        ),
        "snapshot": {
            "today": today,
            "trainingLoad": training_load,
            "recoveryTrend": snapshot.get("recoveryTrend"),
        },
    }