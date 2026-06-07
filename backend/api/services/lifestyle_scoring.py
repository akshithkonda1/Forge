from __future__ import annotations

from typing import Any

from lifestyle_seed import DEFAULT_MACRO_TARGETS


def _clamp(value: float, low: float = 0, high: float = 100) -> int:
    return int(max(low, min(high, value)))


def compute_nutrition_score(
    *,
    protein: float,
    calories: float,
    water_ml: float,
    targets: dict[str, float] | None = None,
) -> int:
    targets = targets or DEFAULT_MACRO_TARGETS
    protein_score = _clamp((protein / targets["protein"]) * 100) if targets["protein"] else 50
    calorie_score = _clamp((calories / targets["calories"]) * 100) if calories > 0 else 50
    hydration_score = _clamp((water_ml / targets["waterMl"]) * 100) if water_ml > 0 else 40
    return (protein_score + calorie_score + hydration_score) // 3


def compute_lifestyle_metrics(
    *,
    sleep_hours: float,
    steps: int,
    active_calories: int,
    resting_hr: float,
    hrv: float,
    protein: float,
    calories: float,
    water_ml: float,
) -> dict[str, Any]:
    sleep_quality = _clamp((sleep_hours / 8.0) * 100)
    nutrition_score = compute_nutrition_score(protein=protein, calories=calories, water_ml=water_ml)
    step_score = _clamp((steps / 10000.0) * 100)
    calorie_score = _clamp((active_calories / 600.0) * 100)
    hr_score = _clamp(100 - ((resting_hr - 60) * 2)) if resting_hr > 0 else 70
    physical_health = (step_score + calorie_score + hr_score) // 3

    mental_wellbeing = _clamp(hrv * 1.5) if hrv > 0 else 70
    if sleep_hours >= 7.5:
        mental_wellbeing = min(100, mental_wellbeing + 10)

    energy_levels = min(
        100,
        int(sleep_quality * 0.4 + nutrition_score * 0.3 + step_score * 0.3),
    )

    if hrv < 30:
        stress = "High"
    elif hrv < 50:
        stress = "Medium"
    else:
        stress = "Low"

    qol = (sleep_quality + nutrition_score + physical_health + mental_wellbeing + energy_levels) // 5

    return {
        "sleepAverage": round(sleep_hours, 1),
        "sleepTarget": 8.0,
        "nutritionQuality": round(nutrition_score / 100.0, 2),
        "dailySteps": steps,
        "stressLevel": stress,
        "qualityOfLifeScore": qol,
        "physicalHealth": physical_health,
        "mentalWellbeing": mental_wellbeing,
        "energyLevels": energy_levels,
        "sleepQuality": sleep_quality,
        "nutritionScore": nutrition_score,
    }


def build_recommendations(metrics: dict[str, Any], nutrition: dict[str, Any]) -> list[dict[str, Any]]:
    recs: list[dict[str, Any]] = []

    protein = float(nutrition.get("protein", 0))
    if protein < 150:
        deficit = int(DEFAULT_MACRO_TARGETS["protein"] - protein)
        recs.append({
            "id": "protein-boost",
            "title": f"Increase protein by {deficit}g",
            "description": (
                f"You've logged {int(protein)}g today. Add {deficit}g to hit your "
                f"{int(DEFAULT_MACRO_TARGETS['protein'])}g target."
            ),
            "impact": "High",
            "category": "Nutrition",
        })

    sleep_avg = float(metrics.get("sleepAverage", 0))
    if sleep_avg < 7.5:
        deficit = round(8.0 - sleep_avg, 1)
        recs.append({
            "id": "sleep-earlier",
            "title": f"Add {deficit} hours of sleep",
            "description": "Earlier bedtimes improve deep sleep and next-day training quality.",
            "impact": "High",
            "category": "Sleep",
        })

    if metrics.get("stressLevel") == "High":
        recs.append({
            "id": "recovery-priority",
            "title": "Priority: Recovery",
            "description": "Stress markers are elevated — prioritize mobility, hydration, and lighter training.",
            "impact": "High",
            "category": "Wellbeing",
        })

    steps = int(metrics.get("dailySteps", 0))
    if steps < 8000:
        recs.append({
            "id": "steps-boost",
            "title": f"Boost movement by {10000 - steps:,} steps",
            "description": "A 15-minute walk adds roughly 2,000 steps toward your daily target.",
            "impact": "Medium",
            "category": "Fitness",
        })

    if not recs:
        recs.append({
            "id": "stay-consistent",
            "title": "Stay consistent",
            "description": "Your lifestyle metrics look balanced. Keep protein, sleep, and steps on track.",
            "impact": "Low",
            "category": "Wellbeing",
        })

    return recs