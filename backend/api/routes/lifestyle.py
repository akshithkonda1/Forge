from __future__ import annotations

import uuid
from typing import Any

from lifestyle_seed import DEFAULT_MACRO_TARGETS, default_habits, default_restaurants
from responses import RouteError, ok
from seed_data import default_daily_metrics, today_iso
from services import lifestyle_scoring
from storage import dynamodb, keys


def _strip(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def _query_date(event: dict) -> str:
    params = event.get("queryStringParameters") or {}
    return params.get("date") or today_iso()


def _load_meals(user_id: str, date: str) -> list[dict[str, Any]]:
    items = dynamodb.query_prefix(keys.user_pk(user_id), f"NUTRITION#MEAL#{date}#")
    return [_strip(i) for i in items]


def _load_water_ml(user_id: str, date: str) -> float:
    item = dynamodb.get_item(**keys.nutrition_water_key(user_id, date))
    return float(item.get("waterMl", 0)) if item else 0.0


def _summarize_nutrition(meals: list[dict[str, Any]], water_ml: float) -> dict[str, Any]:
    calories = sum(float(m.get("calories", 0)) for m in meals)
    protein = sum(float(m.get("protein", 0)) for m in meals)
    carbs = sum(float(m.get("carbs", 0)) for m in meals)
    fat = sum(float(m.get("fat", 0)) for m in meals)
    return {
        "calories": calories,
        "protein": protein,
        "carbs": carbs,
        "fat": fat,
        "waterMl": water_ml,
        "targets": DEFAULT_MACRO_TARGETS,
        "meals": meals,
    }


def _load_habits(user_id: str, date: str) -> tuple[list[dict[str, Any]], int]:
    state_item = dynamodb.get_item(**keys.habit_state_key(user_id, date))
    completed_ids = set(state_item.get("completedIds", [])) if state_item else set()
    habits = []
    for habit in default_habits():
        habits.append({**habit, "completed": habit["id"] in completed_ids})
    streak = int(state_item.get("streak", 7)) if state_item else 7
    return habits, streak


def _dashboard_signals(user_id: str) -> dict[str, Any]:
    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=1)
    latest_sleep = _strip(sleep_items[0]) if sleep_items else {}
    daily_metrics = default_daily_metrics()

    for metric_type, field in (
        ("steps", "steps"),
        ("active-calories", "activeCalories"),
        ("resting-heart-rate", "restingHR"),
        ("hrv", "hrv"),
    ):
        metric_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), f"METRIC#{metric_type}#", limit=1)
        if metric_items:
            daily_metrics[field] = metric_items[0].get("value", daily_metrics[field])

    return {
        "sleep_hours": float(latest_sleep.get("totalHours", 0) or 0),
        "steps": int(daily_metrics.get("steps", 0)),
        "active_calories": int(daily_metrics.get("activeCalories", 0)),
        "resting_hr": float(daily_metrics.get("restingHR", 0)),
        "hrv": float(daily_metrics.get("hrv", 0)),
    }


def handle_get_lifestyle_dashboard(user_id: str, event: dict) -> dict:
    date = _query_date(event)
    meals = _load_meals(user_id, date)
    water_ml = _load_water_ml(user_id, date)
    nutrition = _summarize_nutrition(meals, water_ml)
    signals = _dashboard_signals(user_id)

    metrics = lifestyle_scoring.compute_lifestyle_metrics(
        sleep_hours=signals["sleep_hours"],
        steps=signals["steps"],
        active_calories=signals["active_calories"],
        resting_hr=signals["resting_hr"],
        hrv=signals["hrv"],
        protein=nutrition["protein"],
        calories=nutrition["calories"],
        water_ml=nutrition["waterMl"],
    )
    habits, streak = _load_habits(user_id, date)

    return ok({
        "date": date,
        "metrics": metrics,
        "recommendations": lifestyle_scoring.build_recommendations(metrics, nutrition),
        "nutrition": nutrition,
        "habits": habits,
        "habitStreak": streak,
    })


def handle_get_nutrition_daily(user_id: str, event: dict) -> dict:
    date = _query_date(event)
    meals = _load_meals(user_id, date)
    water_ml = _load_water_ml(user_id, date)
    return ok({"date": date, **_summarize_nutrition(meals, water_ml)})


def handle_post_nutrition_meal(user_id: str, body: dict) -> dict:
    meal = body.get("meal")
    if not isinstance(meal, dict):
        raise RouteError(400, "Request body must include a 'meal' object.")

    date = meal.get("date") or today_iso()
    meal_id = meal.get("id") or str(uuid.uuid4())
    required = ("name", "calories", "protein", "carbs", "fat")
    for field in required:
        if meal.get(field) is None:
            raise RouteError(400, f"'meal.{field}' is required.")

    record = {
        "id": meal_id,
        "date": date,
        "name": meal["name"],
        "calories": float(meal["calories"]),
        "protein": float(meal["protein"]),
        "carbs": float(meal["carbs"]),
        "fat": float(meal["fat"]),
        "loggedAt": meal.get("loggedAt"),
    }
    dynamodb.put_item({**keys.nutrition_meal_key(user_id, date, meal_id), **record})
    return ok({"meal": record})


def handle_post_nutrition_water(user_id: str, body: dict) -> dict:
    water = body.get("water")
    if not isinstance(water, dict):
        raise RouteError(400, "Request body must include a 'water' object.")

    date = water.get("date") or today_iso()
    amount_ml = water.get("waterMl")
    if amount_ml is None:
        raise RouteError(400, "'water.waterMl' is required.")

    item = {
        **keys.nutrition_water_key(user_id, date),
        "date": date,
        "waterMl": float(amount_ml),
    }
    dynamodb.put_item(item)
    return ok({"date": date, "waterMl": float(amount_ml)})


def handle_get_restaurants(event: dict) -> dict:
    params = event.get("queryStringParameters") or {}
    category = (params.get("category") or "").strip()
    search = (params.get("search") or "").strip().lower()

    restaurants = default_restaurants()
    if category and category.lower() != "all":
        restaurants = [r for r in restaurants if r["category"].lower() == category.lower()]

    if search:
        restaurants = [
            r for r in restaurants
            if search in r["name"].lower()
            or any(search in item["name"].lower() for item in r.get("items", []))
        ]

    return ok({"restaurants": restaurants, "count": len(restaurants)})


def handle_get_wellbeing_habits(user_id: str, event: dict) -> dict:
    date = _query_date(event)
    habits, streak = _load_habits(user_id, date)
    return ok({"date": date, "habits": habits, "habitStreak": streak})


def handle_post_wellbeing_habit_complete(user_id: str, habit_id: str, body: dict) -> dict:
    date = body.get("date") or today_iso()
    habits, streak = _load_habits(user_id, date)
    valid_ids = {h["id"] for h in default_habits()}
    if habit_id not in valid_ids:
        raise RouteError(404, f"Habit '{habit_id}' was not found.")

    state_key = keys.habit_state_key(user_id, date)
    state_item = dynamodb.get_item(**state_key) or {**state_key}
    completed_ids = set(state_item.get("completedIds", []))
    completed = bool(body.get("completed", True))
    if completed:
        completed_ids.add(habit_id)
    else:
        completed_ids.discard(habit_id)

    state_item.update({
        "date": date,
        "completedIds": sorted(completed_ids),
        "streak": streak,
    })
    dynamodb.put_item(state_item)

    updated_habits = []
    for habit in habits:
        updated_habits.append({**habit, "completed": habit["id"] in completed_ids})

    return ok({"date": date, "habits": updated_habits, "habitStreak": streak})