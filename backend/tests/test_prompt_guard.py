"""Per-prompt offline checker — same inputs must replay, or the turn dies."""

from __future__ import annotations

import os
import unittest
from unittest.mock import patch

import _bootstrap  # noqa: F401

from aria_core import prompt_guard
from responses import RouteError
from routes import aria as aria_routes
from services import aria_engine


def _ctx():
    return aria_engine.ARIAContext(
        sleep=aria_engine.SleepContext(
            duration_minutes=450,
            deep_minutes=90,
            rem_minutes=100,
            efficiency=0.9,
            hrv=58,
            resting_hr=58,
            nights_available=7,
        ),
        readiness=aria_engine.ReadinessContext(
            hrv_7day_trend=0.0,
            hrv_30day_baseline=60,
            recovery_score=74,
            hrv_days_available=7,
        ),
        training=aria_engine.TrainingContext(
            last_workout_type="strength",
            hours_since_last_workout=36,
        ),
        lifestyle=aria_engine.LifestyleContext(tags=["founder"]),
        profile=aria_engine.ProfileContext(
            primary_goal="general-fitness",
            experience_level="intermediate",
            coaching_style="balanced",
        ),
        progress=aria_engine.ProgressContext(),
    )


class FingerprintTests(unittest.TestCase):
    def test_same_facts_match(self):
        a = {
            "response_type": "insight",
            "message": "You slept enough.",
            "recommendation": "Wind down earlier.",
        }
        b = {
            "response_type": "insight",
            "message": "you  slept enough.",
            "recommendation": "Wind down earlier.",
        }
        self.assertTrue(prompt_guard.consistent(a, b))

    def test_different_recommendation_fails(self):
        a = {"response_type": "recommendation", "message": "Train.", "recommendation": "Go lift."}
        b = {"response_type": "recommendation", "message": "Train.", "recommendation": "Rest today."}
        self.assertFalse(prompt_guard.consistent(a, b))

    def test_card_action_counts_as_recommendation(self):
        a = {"message": "Go.", "card": {"action": "One quality session"}}
        b = {"message": "Go.", "recommendation": "One quality session"}
        self.assertTrue(prompt_guard.consistent(a, b))


class GuardSwitchTests(unittest.TestCase):
    def setUp(self):
        self._flag = os.environ.get("FORGE_PROMPT_GUARD")

    def tearDown(self):
        if self._flag is None:
            os.environ.pop("FORGE_PROMPT_GUARD", None)
        else:
            os.environ["FORGE_PROMPT_GUARD"] = self._flag

    def test_disabled_guard_runs_once(self):
        os.environ["FORGE_PROMPT_GUARD"] = "0"
        calls = {"n": 0}

        def produce():
            calls["n"] += 1
            return {"message": f"take {calls['n']}", "response_type": "insight"}

        row = prompt_guard.checked(produce)
        self.assertEqual(calls["n"], 1)
        self.assertEqual(row["message"], "take 1")


class ConfirmTests(unittest.TestCase):
    def test_stable_producer_returns_first(self):
        calls = {"n": 0}

        def produce():
            calls["n"] += 1
            return {"message": "same", "response_type": "insight"}

        row = prompt_guard.confirm(produce)
        self.assertEqual(row["message"], "same")
        self.assertEqual(calls["n"], 2)

    def test_wobbly_producer_raises_connection_line(self):
        calls = {"n": 0}

        def produce():
            calls["n"] += 1
            return {"message": f"take {calls['n']}", "response_type": "insight"}

        with self.assertRaises(prompt_guard.PromptInconsistent) as raised:
            prompt_guard.confirm(produce)
        self.assertEqual(str(raised.exception), prompt_guard.CONNECTION_FAILURE)
        self.assertEqual(raised.exception.public_message, prompt_guard.CONNECTION_FAILURE)


class EngineReplayTests(unittest.TestCase):
    def test_generate_response_replays_the_same_envelope(self):
        first = aria_engine.generate_response("Should I train today?", _ctx())
        second = aria_engine.generate_response("Should I train today?", _ctx())
        self.assertTrue(prompt_guard.consistent(first, second))
        self.assertTrue(first.get("message") or first.get("prose_summary"))


class ChatRouteGuardTests(unittest.TestCase):
    def setUp(self):
        self._flag = os.environ.get("FORGE_PROMPT_GUARD")
        os.environ["FORGE_PROMPT_GUARD"] = "1"

    def tearDown(self):
        if self._flag is None:
            os.environ.pop("FORGE_PROMPT_GUARD", None)
        else:
            os.environ["FORGE_PROMPT_GUARD"] = self._flag

    def test_wobbly_chat_becomes_a_connection_failure(self):
        calls = {"n": 0}
        real = aria_engine.generate_response

        def wobble(message, ctx, **kwargs):
            calls["n"] += 1
            row = dict(real(message, ctx, **kwargs))
            row["message"] = f"{row.get('message') or ''} #{calls['n']}"
            row["prose_summary"] = row["message"]
            return row

        with patch.object(aria_routes.aria_engine, "generate_response", side_effect=wobble):
            with self.assertRaises(RouteError) as raised:
                aria_routes.handle_post_ai_chat(
                    {"message": "How did I sleep last night?", "user_id": "test-user-00000000"},
                    user_id="test-user-00000000",
                )
        self.assertEqual(raised.exception.status_code, 503)
        self.assertEqual(raised.exception.message, prompt_guard.CONNECTION_FAILURE)
        self.assertEqual(raised.exception.code, prompt_guard.CONNECTION_CODE)


if __name__ == "__main__":
    unittest.main()
