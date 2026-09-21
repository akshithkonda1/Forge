"""Shared intelligence sidecar: native iOS and Android decode this JSON.

Covers the aggregator, POST /intelligence/today, POST /intelligence/workout-cue,
and generate_response attachment. Engines themselves are tested in their own files.
"""

from __future__ import annotations

import json
import os
import unittest
from datetime import datetime, timezone

import _bootstrap  # noqa: F401

from aria_core import shared_intelligence as si  # noqa: E402
from handler import handler  # noqa: E402
from services import aria_engine  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402


def event(method, path, body=None):
    payload = {
        "requestContext": {"http": {"method": method, "path": path}},
        "queryStringParameters": {},
        "headers": {},
    }
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def body_of(response):
    return json.loads(response["body"])


class SharedIntelligenceComputeTests(unittest.TestCase):
    def test_empty_inputs_do_not_invent_vitals(self):
        now = datetime(2026, 9, 20, 10, 0, tzinfo=timezone.utc)
        payload = si.compute(now=now)
        self.assertEqual(payload["schemaVersion"], 1)
        self.assertEqual(payload["glanceReadiness"]["confidence"], 0)
        self.assertIsNone(payload["habits"])
        self.assertIsNone(payload["hydration"])
        self.assertIsNone(payload["metabolicWatch"])
        self.assertIsNone(payload["habitStreak"])
        self.assertIn("still gathering", payload["greeting"].lower())

    def test_desk_block_reaches_the_sidecar(self):
        payload = si.from_payload({
            "timestamp": "2026-09-20T14:00:00+00:00",
            "readinessOverall": 75,
            "readinessConfidence": 0.9,
            "lifestyleMode": "deskCoding",
            "minutesInCurrentMode": 95,
            "hrvTrendMs": -8,
        })
        self.assertEqual(payload["mindfulness"]["trigger"], "desk-block-hrv-dip")
        self.assertTrue(payload["contextRules"]["deskBlockNudgeDue"])
        self.assertTrue(payload["contextRules"]["hrvIsDipping"])

    def test_habit_streak_from_payload(self):
        payload = si.from_payload({
            "timestamp": "2026-09-20T15:00:00+00:00",
            "habits": {
                "completed": 4,
                "total": 6,
                "qualifyingDays": ["2026-09-18", "2026-09-19"],
            },
        })
        streak = payload["habitStreak"]
        self.assertTrue(streak["todayQualifies"])
        self.assertEqual(streak["length"], 3)

    def test_guidance_needles_surface_on_the_sidecar(self):
        payload = si.from_payload({"message": "I have chest pain after intervals"})
        self.assertEqual(payload["guidance"]["band"], "referOut")

    def test_sensor_copy_is_os_neutral(self):
        payload = si.compute(
            resting_hr=58,
            hrv_ms=52,
            sleep_hours=7.2,
            now=datetime(2026, 9, 20, 10, tzinfo=timezone.utc),
        )
        blob = json.dumps(payload)
        self.assertNotIn("Apple Watch", blob)
        self.assertIsNotNone(payload["metabolicWatch"])

    def test_from_dashboard_uses_sleep_hours_not_minutes_as_hours(self):
        payload = si.from_dashboard(
            profile={"name": "Sam"},
            readiness={"overall": 82, "sleepQuality": 88},
            daily_metrics={"totalSleep": 432, "deepSleep": 102, "hrv": 52, "restingHR": 58, "steps": 8000},
            recent_sleep=[{"totalHours": 7.2, "deepMinutes": 102, "remMinutes": 95, "awakeMinutes": 20, "score": 88}],
            now=datetime(2026, 9, 20, 9, tzinfo=timezone.utc),
        )
        self.assertIn("Sam", payload["greeting"])
        self.assertGreater(payload["glanceReadiness"]["confidence"], 0)
        self.assertIn("7h", payload["sleepStory"])


class GenerateResponseSidecarTests(unittest.TestCase):
    def test_chat_envelope_carries_shared_intelligence(self):
        ctx = aria_engine.ARIAContext.from_payload({
            "context": {
                "sleep": {"durationMinutes": 440, "hrv": 58, "deepMinutes": 70, "remMinutes": 95},
                "readiness": {"recoveryScore": 72, "hrv30DayBaseline": 55},
            }
        })
        resp = aria_engine.generate_response("should I train today?", ctx)
        sidecar = resp["sharedIntelligence"]
        self.assertEqual(sidecar["schemaVersion"], 1)
        self.assertIn("mindfulness", sidecar)
        self.assertIn("workoutSuggestion", sidecar)

    def test_guardrail_path_still_attaches_the_sidecar(self):
        ctx = aria_engine.ARIAContext.from_payload({"context": {}})
        resp = aria_engine.generate_response("how do I do CPR", ctx)
        self.assertIn("guidance_band", resp)
        self.assertIn("sharedIntelligence", resp)


class IntelligenceRouteTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        os.environ["ENVIRONMENT"] = "test"
        os.environ["FORGE_ALLOW_ANON_TEST_USER"] = "true"

    def test_post_intelligence_today(self):
        response = handler(
            event(
                "POST",
                "/intelligence/today",
                {
                    "timestamp": "2026-09-20T09:00:00+00:00",
                    "readinessOverall": 72,
                    "readinessConfidence": 0.9,
                    "sleepMinutes": 480,
                    "sleepQualityScore": 82,
                },
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = body_of(response)
        self.assertEqual(payload["schemaVersion"], 1)
        self.assertIn("Readiness 72", payload["dayBrief"])

    def test_post_workout_cue_requires_bpm(self):
        response = handler(event("POST", "/intelligence/workout-cue", {}), None)
        self.assertEqual(response["statusCode"], 400)

    def test_post_workout_cue_happy_path(self):
        response = handler(
            event(
                "POST",
                "/intelligence/workout-cue",
                {
                    "bpm": 175,
                    "previousZone": 3,
                    "targetZone": 3,
                    "lastCueAt": "1970-01-01T00:00:00+00:00",
                    "now": "2026-09-20T12:00:00+00:00",
                },
            ),
            None,
        )
        self.assertEqual(response["statusCode"], 200)
        payload = body_of(response)
        self.assertEqual(payload["zone"], 5)
        self.assertIn("Your call", payload["cue"])


if __name__ == "__main__":
    unittest.main()
