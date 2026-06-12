"""Authoritative Strain / Recovery / Sleep daily scores (Bevel-class trilogy)."""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from data.seed_data import today_iso
from services import readiness, scoring
from services.cycle_context import cycle_training_modifier
from services.data_fusion import load_wellness_snapshot
from storage import dynamodb, keys


def _clamp(value: float, low: float = 0, high: float = 100) -> int:
    return int(max(low, min(high, round(value))))


def _strain_score(snapshot: dict[str, Any]) -> dict[str, Any]:
    today = snapshot.get("today") or {}
    load = snapshot.get("trainingLoad") or {}
    steps = float(today.get("steps") or 0)
    calories = float(today.get("activeCalories") or 0)
    current_load = float(load.get("current") or 0)
    previous_load = float(load.get("previous") or 0)

    baseline = max(previous_load, current_load * 0.85, 120)
    exertion = current_load + (steps / 250) + (calories / 25)
    pct = _clamp((exertion / baseline) * 55 if baseline else 0)

    trend = load.get("trend", "flat")
    return {
        "score": pct,
        "trend": trend,
        "baselineLoad": round(baseline),
        "todayLoad": round(exertion),
    }


def _recovery_score(snapshot: dict[str, Any]) -> dict[str, Any]:
    readiness_block = snapshot.get("readiness") or {}
    recovery = int(readiness_block.get("recoveryScore") or readiness_block.get("overall") or 0)
    hrv = float((snapshot.get("today") or {}).get("hrv") or 0)
    rollups = (snapshot.get("rollups") or {}).get("windows", {}).get("7", {})
    hrv_rollup = rollups.get("hrv") or {}
    if hrv_rollup.get("trend") == "falling":
        recovery = max(0, recovery - 8)
    elif hrv_rollup.get("trend") == "rising":
        recovery = min(100, recovery + 5)
    if hrv and hrv < 35:
        recovery = max(0, recovery - 10)
    return {
        "score": _clamp(recovery),
        "hrv": int(hrv) if hrv else None,
        "trend": hrv_rollup.get("trend", "unknown"),
    }


def _sleep_score(snapshot: dict[str, Any]) -> dict[str, Any]:
    today = snapshot.get("today") or {}
    sleep_score = int(today.get("sleepScore") or 0)
    total_sleep = int(today.get("totalSleep") or 0)
    target_minutes = 8 * 60
    sleep_need = max(0, target_minutes - total_sleep) if total_sleep else target_minutes
    if not sleep_score and total_sleep:
        sleep_score = _clamp((total_sleep / target_minutes) * 100)
    return {
        "score": _clamp(sleep_score),
        "sleepNeedMinutes": sleep_need,
        "totalSleepMinutes": total_sleep,
        "deepSleepMinutes": int(today.get("deepSleep") or 0),
    }


def _training_decision(
    *,
    strain: int,
    recovery: int,
    sleep: int,
    compound_flags: list[str],
    cycle_modifier: dict[str, Any],
) -> str:
    if "recovery-debt-under-load" in compound_flags or recovery < 45:
        return "recover"
    if strain >= 75 and recovery < 60:
        return "active_rest"
    if cycle_modifier.get("recommendRecovery"):
        return "recover"
    if recovery >= 70 and sleep >= 65 and strain < 80:
        return "train"
    if recovery >= 55:
        return "active_rest"
    return "recover"


def compute_daily_scores(
    user_id: str,
    *,
    date: str | None = None,
    compound_flags: list[str] | None = None,
) -> dict[str, Any]:
    """Compute and optionally persist authoritative daily trilogy scores."""
    target_date = date or today_iso()
    snapshot = load_wellness_snapshot(user_id, date=target_date)
    cycle = cycle_training_modifier(user_id)

    strain_block = _strain_score(snapshot)
    recovery_block = _recovery_score(snapshot)
    sleep_block = _sleep_score(snapshot)
    flags = compound_flags or []

    decision = _training_decision(
        strain=strain_block["score"],
        recovery=recovery_block["score"],
        sleep=sleep_block["score"],
        compound_flags=flags,
        cycle_modifier=cycle,
    )

    result = {
        "date": target_date,
        "strain": strain_block,
        "recovery": recovery_block,
        "sleep": sleep_block,
        "trainingDecision": decision,
        "cycleContext": cycle,
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }

    item = {**keys.daily_scores_key(user_id, target_date), **result}
    dynamodb.put_item(item)
    return result


def load_daily_scores(user_id: str, date: str | None = None) -> dict[str, Any] | None:
    target_date = date or today_iso()
    item = dynamodb.get_item(**keys.daily_scores_key(user_id, target_date))
    if not item:
        return None
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def get_or_compute_daily_scores(
    user_id: str,
    *,
    date: str | None = None,
    compound_flags: list[str] | None = None,
) -> dict[str, Any]:
    stored = load_daily_scores(user_id, date)
    if stored:
        return stored
    return compute_daily_scores(user_id, date=date, compound_flags=compound_flags)