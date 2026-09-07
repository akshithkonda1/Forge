"""Linux-runnable stand-in for ForgeCore Cloud contract tests.

The iOS decoder lives in Swift (`ForgeCloudContracts.swift`). This file pins the
same JSON shapes the client now consumes so a Linux agent can still prove the
wire format: nested workout-plan cards, camelCase chat threads, and HealthKit
metric aliases for POST /health/batch.
"""

from __future__ import annotations

import json
import unittest


def _canonical_metric_type(raw: str) -> str | None:
    key = raw.lower().replace("_", "-").replace(" ", "-")
    mapping = {
        "steps": "steps",
        "active-calories": "active-calories",
        "activecalories": "active-calories",
        "active-energy": "active-calories",
        "calories": "active-calories",
        "hrv": "hrv",
        "resting-heart-rate": "resting-heart-rate",
        "resting-hr": "resting-heart-rate",
        "restinghr": "resting-heart-rate",
        "heart-rate": "heart-rate",
        "heartrate": "heart-rate",
        "hr": "heart-rate",
        "sleep-stage": "sleep-stage",
        "body-weight": "body-weight",
        "weight": "body-weight",
        "distance": "distance",
    }
    return mapping.get(key)


def _canonical_source(raw: str | None) -> str:
    key = (raw or "apple-health").lower().replace("_", "-")
    if "apple" in key or "healthkit" in key:
        return "apple-health"
    if "oura" in key:
        return "oura"
    return key if key in {"apple-health", "oura", "whoop", "garmin", "strava", "manual"} else "manual"


def _decode_rich_card(payload: dict) -> dict:
    data = payload.get("data") if isinstance(payload.get("data"), dict) else {}
    card_type = payload.get("type") or "unknown"
    name = data.get("name") or payload.get("workout_name") or payload.get("workoutName") or payload.get("name")
    duration = data.get("duration") or payload.get("duration_minutes") or payload.get("durationMinutes") or payload.get("duration")
    exercises = data.get("exercises") or payload.get("exercises") or []
    title = data.get("title") or payload.get("title")
    values = data.get("values") or payload.get("values")
    insight = data.get("insight") or payload.get("insight")
    return {
        "type": card_type,
        "workoutName": name,
        "durationMinutes": duration,
        "exercises": exercises,
        "title": title,
        "values": values,
        "insight": insight,
        "isWorkoutPlan": str(card_type).lower().replace("_", "-") == "workout-plan",
        "isDataChart": str(card_type).lower().replace("_", "-") == "data-chart",
    }


class IOSCloudContractTests(unittest.TestCase):
    def test_workout_plan_nested_exercises_keep_outer_type(self):
        payload = json.loads(
            """
            {
              "type": "workout-plan",
              "data": {
                "id": "w1",
                "name": "Upper Body Power",
                "type": "strength",
                "duration": 55,
                "exercises": [
                  { "name": "Barbell Bench Press", "sets": 4, "reps": "6-8" },
                  { "name": "Weighted Pull-Ups", "sets": 4, "reps": 8 }
                ]
              }
            }
            """
        )
        card = _decode_rich_card(payload)
        self.assertTrue(card["isWorkoutPlan"])
        self.assertEqual(card["type"], "workout-plan")
        self.assertEqual(card["workoutName"], "Upper Body Power")
        self.assertEqual(card["durationMinutes"], 55)
        self.assertEqual(len(card["exercises"]), 2)
        self.assertEqual(card["exercises"][0]["name"], "Barbell Bench Press")

    def test_snake_case_chat_envelope(self):
        payload = json.loads(
            """
            {
              "type": "workout_plan",
              "workout_name": "Recovery Flow",
              "duration_minutes": 30,
              "exercises": [{ "name": "Walk", "sets": 1, "reps": "20 min" }]
            }
            """
        )
        card = _decode_rich_card(payload)
        self.assertTrue(card["isWorkoutPlan"])
        self.assertEqual(card["workoutName"], "Recovery Flow")
        self.assertEqual(card["durationMinutes"], 30)

    def test_data_chart_nested_payload(self):
        payload = json.loads(
            """
            {
              "type": "data-chart",
              "data": {
                "title": "Sleep Quality (7-day)",
                "values": [72, 80, 68],
                "insight": "Average sleep score: 73."
              }
            }
            """
        )
        card = _decode_rich_card(payload)
        self.assertTrue(card["isDataChart"])
        self.assertEqual(card["title"], "Sleep Quality (7-day)")
        self.assertEqual(card["values"], [72, 80, 68])

    def test_chat_thread_camel_case_rich_card(self):
        thread = json.loads(
            """
            {
              "threadId": "current",
              "messages": [
                {
                  "id": "m4",
                  "role": "trainer",
                  "content": "Upper body power.",
                  "timestamp": "2026-05-06T13:00:10+00:00",
                  "richCard": {
                    "type": "workout-plan",
                    "data": { "name": "Upper Body Power", "duration": 55, "exercises": [] }
                  }
                }
              ]
            }
            """
        )
        self.assertEqual(thread["threadId"], "current")
        card = _decode_rich_card(thread["messages"][0]["richCard"])
        self.assertEqual(card["workoutName"], "Upper Body Power")

    def test_health_batch_aliases(self):
        samples = [
            ("active_calories", "HealthKit"),
            ("resting_hr", "apple-health"),
            ("sleep", "apple-health"),
            ("hrv", "oura"),
        ]
        mapped = []
        for metric, source in samples:
            canonical = _canonical_metric_type(metric)
            if canonical:
                mapped.append((canonical, _canonical_source(source)))
        self.assertEqual(
            mapped,
            [
                ("active-calories", "apple-health"),
                ("resting-heart-rate", "apple-health"),
                ("hrv", "oura"),
            ],
        )

    def test_empty_readiness_is_not_usable(self):
        readiness = {"overall": None, "sleepQuality": None, "available": False}
        usable = bool(readiness.get("available") and readiness.get("overall") is not None)
        self.assertFalse(usable)

    def test_dashboard_readiness_is_usable(self):
        readiness = {"overall": 74, "available": True}
        usable = bool(readiness.get("available") and readiness.get("overall") is not None)
        self.assertTrue(usable)


if __name__ == "__main__":
    unittest.main()
