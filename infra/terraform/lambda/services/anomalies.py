"""Quiet anomaly layer — pattern, not diagnosis."""

from __future__ import annotations

from typing import Any

from services import ledger
from services.source_map import COACH_NAME


def detect(user_id: str) -> list[dict[str, Any]]:
    nights = ledger.load_sleep(user_id, days=10)
    metrics = ledger.load_metrics(user_id, limit=120)
    found: list[dict[str, Any]] = []

    scores = [float(n.get("score") or 0) for n in nights[:6] if n.get("score") is not None]
    if len(scores) >= 4 and scores[0] < 65 and sum(scores[:3]) / 3 + 12 < sum(scores[3:6]) / max(len(scores[3:6]), 1):
        found.append(
            {
                "id": "sleep-drop",
                "kind": "sleep",
                "line": "Sleep scores have slipped for three nights. Pattern, not a diagnosis.",
            }
        )

    hrv = [float(m.get("value")) for m in metrics if m.get("metricType") == "hrv"]
    if len(hrv) >= 6 and sum(hrv[:3]) / 3 < sum(hrv[3:6]) / 3 * 0.8:
        found.append(
            {
                "id": "hrv-drop",
                "kind": "recovery",
                "line": "HRV is down versus the prior stretch. ARIA will keep today conservative.",
            }
        )

    rhr = [float(m.get("value")) for m in metrics if m.get("metricType") == "resting-heart-rate"]
    if len(rhr) >= 6 and sum(rhr[:3]) / 3 > sum(rhr[3:6]) / 3 + 4:
        found.append(
            {
                "id": "rhr-rise",
                "kind": "recovery",
                "line": "Resting heart rate is running higher than the days before it.",
            }
        )

    water = [float(m.get("value")) for m in metrics if m.get("metricType") == "dietary-water"]
    if len(water) >= 4 and sum(water[:2]) < sum(water[2:4]) * 0.5:
        found.append(
            {
                "id": "water-drop",
                "kind": "hydration",
                "line": "Water intake is about half of the stretch before it.",
            }
        )

    for item in found:
        item["coach"] = COACH_NAME
        item["claim"] = "pattern"
    return found[:4]
