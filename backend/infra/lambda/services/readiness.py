from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from empty_state import empty_readiness


def compute_readiness(sleep_records: list[dict[str, Any]], hrv: float | None = None) -> dict[str, Any]:
    """Compute a readiness score from recent sleep and optional HRV."""
    if not sleep_records:
        # Nothing to score. Both callers guard against this already; returning an
        # invented mid-range score here is how the guard stops mattering the next
        # time someone adds a third caller.
        return empty_readiness()

    latest = sleep_records[0]
    sleep_score = float(latest.get("score", 75))

    # Weight last 3 nights for recovery trend.
    recent = sleep_records[:3]
    avg_score = sum(float(r.get("score", 75)) for r in recent) / len(recent)

    recovery_score = round(avg_score * 0.9 + (min(sleep_score, 100) * 0.1))

    hrv_bonus = 0.0
    if hrv is not None:
        # HRV above 45 ms is a positive signal; below 35 ms is a negative one.
        if hrv >= 45:
            hrv_bonus = min((hrv - 45) * 0.3, 10)
        elif hrv < 35:
            hrv_bonus = max((hrv - 35) * 0.5, -10)

    overall = round(min(100, max(0, recovery_score + hrv_bonus)))

    return {
        "overall": overall,
        "sleepQuality": round(sleep_score),
        "recoveryScore": round(recovery_score),
        "stressLevel": max(0, 100 - overall),
        "energyBank": round(overall * 0.92),
        "generatedAt": datetime.now(timezone.utc).isoformat(),
    }
