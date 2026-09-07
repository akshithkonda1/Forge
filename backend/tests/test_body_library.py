"""Body-region libraries + next-session suggestion."""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from services import body_library as B  # noqa: E402
from services import aria_engine  # noqa: E402


class LibraryTests(unittest.TestCase):
    def test_every_region_has_a_library(self):
        for region in B.REGIONS:
            rows = B.library(region, experience="beginner", limit=8)
            self.assertGreaterEqual(len(rows), 3, region)
            self.assertTrue(all(isinstance(m.name, str) and m.name for m in rows))

    def test_beginner_library_skips_advanced_moves(self):
        names = [m.name for m in B.library("core", experience="beginner", limit=8)]
        self.assertNotIn("Ab Wheel Rollout", names)

    def test_infer_region_from_name_and_type(self):
        self.assertEqual(B.infer_region("Tuesday Leg Day"), "legs")
        self.assertEqual(B.infer_region("Bench + overhead"), "push")
        self.assertEqual(B.infer_region("easy run", "cardio"), "conditioning")
        self.assertEqual(B.infer_region("full-body circuit"), "conditioning")
        self.assertIsNone(B.infer_region("how did I sleep"))


class SuggestionTests(unittest.TestCase):
    def test_tuesday_legs_wednesday_is_chest_and_abs(self):
        s = B.suggest_session(
            last_region="legs",
            last_label="leg day",
            hours_since=20,
            weekday=2,  # Wednesday
            experience="intermediate",
            readiness=72,
        )
        self.assertIn("push", s.combo)
        self.assertIn("core", s.combo)
        self.assertEqual(s.avoided, "legs")
        names = [m.name.lower() for m in s.exercises]
        self.assertTrue(any("bench" in n or "push-up" in n or "press" in n for n in names))
        self.assertTrue(any("plank" in n or "crunch" in n or "raise" in n for n in names))
        self.assertNotIn("Back Squat", [m.name for m in s.exercises])
        spoken = s.spoken()
        self.assertNotRegex(spoken, r"\d")
        self.assertIn("leg", spoken.lower())

    def test_same_region_ask_is_redirected_while_fresh(self):
        s = B.suggest_session(
            last_region="legs",
            last_label="squats",
            hours_since=12,
            asked_region="legs",
            experience="intermediate",
            readiness=80,
        )
        self.assertEqual(s.avoided, "legs")
        self.assertNotEqual(s.region, "legs")

    def test_asked_chest_is_honored_when_fresh_is_legs(self):
        s = B.suggest_session(
            last_region="legs",
            hours_since=20,
            asked_region="push",
            experience="intermediate",
        )
        self.assertEqual(s.region, "push")
        self.assertTrue(s.exercises)

    def test_beginner_prefers_full_body_after_a_gap(self):
        s = B.suggest_session(
            last_region=None,
            hours_since=80,
            experience="beginner",
            readiness=70,
        )
        self.assertEqual(s.region, "full_body")
        regions = {m.muscles[0] for m in s.exercises}
        self.assertGreaterEqual(len(regions), 2)

    def test_low_readiness_keeps_it_to_easy_core(self):
        s = B.suggest_session(
            last_region="push",
            hours_since=30,
            readiness=40,
            experience="advanced",
        )
        self.assertEqual(s.region, "core")
        self.assertIn("care", s.reason.lower())

    def test_maybe_suggest_ignores_sleep_questions(self):
        self.assertIsNone(B.maybe_suggest("How did I sleep last night?"))

    def test_maybe_suggest_uses_last_workout_name(self):
        s = B.maybe_suggest(
            "What should I train today?",
            last_workout_name="Lower Body Strength",
            last_workout_type="strength",
            hours_since=22,
            experience="intermediate",
            readiness=74,
        )
        self.assertIsNotNone(s)
        self.assertEqual(s.avoided, "legs")
        self.assertIn("push", s.combo)


class EngineWiringTests(unittest.TestCase):
    def test_recommendation_carries_a_body_session(self):
        ctx = aria_engine.ARIAContext.from_payload({
            "user_id": "u",
            "context": {
                "training": {
                    "lastWorkoutType": "strength",
                    "lastWorkoutName": "Tuesday Leg Day",
                    "hoursSinceLastWorkout": 20,
                },
                "profile": {"experienceLevel": "intermediate"},
                "readiness": {"recoveryScore": 72},
                "sleep": {"durationMinutes": 450, "nightsAvailable": 7},
            },
        })
        r = aria_engine.generate_response("What should I train today?", ctx)
        self.assertEqual(r["response_type"], "recommendation")
        session = r.get("session")
        self.assertIsInstance(session, dict)
        self.assertTrue(session["exercises"])
        self.assertNotEqual(session.get("avoided"), None)

    def test_sleep_question_does_not_grow_a_session(self):
        ctx = aria_engine.ARIAContext.from_payload({"user_id": "u"})
        r = aria_engine.generate_response("How did I sleep last night?", ctx)
        self.assertNotIn("session", r)


if __name__ == "__main__":
    unittest.main()
