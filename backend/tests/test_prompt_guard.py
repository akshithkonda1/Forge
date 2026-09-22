"""Per-prompt SimRunner gate — honesty and determinism, 70% floor."""

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
    def test_wording_may_move_when_facts_hold(self):
        a = {
            "response_type": "insight",
            "message": "You slept enough.",
            "recommendation": "Wind down earlier.",
        }
        b = {
            "response_type": "insight",
            "message": "you slept plenty — keep the same wind-down.",
            "recommendation": "Wind down earlier.",
        }
        self.assertTrue(prompt_guard.consistent(a, b))
        self.assertEqual(prompt_guard.determinism_score(a, b), 100.0)

    def test_different_recommendation_fails_determinism(self):
        a = {"response_type": "recommendation", "message": "Train.", "recommendation": "Go lift."}
        b = {"response_type": "recommendation", "message": "Train.", "recommendation": "Rest today."}
        self.assertFalse(prompt_guard.consistent(a, b))
        self.assertEqual(prompt_guard.determinism_score(a, b), 0.0)

    def test_card_action_counts_as_recommendation(self):
        a = {"message": "Go.", "card": {"action": "One quality session"}}
        b = {"message": "Go.", "recommendation": "One quality session"}
        self.assertTrue(prompt_guard.consistent(a, b))


class HonestyTests(unittest.TestCase):
    def test_explicit_score_below_floor_fails(self):
        row = {"message": "Go hard.", "recommendation": "Max", "epistemic_honesty": 40}
        self.assertEqual(prompt_guard.honesty_score(row), 40)
        self.assertFalse(prompt_guard.passes(row))

    def test_guessing_on_sparse_data_is_not_honest(self):
        row = {
            "message": "Do a heavy session.",
            "recommendation": "Heavy lower",
            "confidence": 0.9,
            "data_sparse": True,
        }
        self.assertLess(prompt_guard.honesty_score(row), prompt_guard.FLOOR)

    def test_asking_when_sparse_is_honest(self):
        row = {
            "message": "I don't have enough on you yet — how did last night go?",
            "recommendation": None,
            "confidence": 0.3,
            "data_sparse": True,
        }
        self.assertGreaterEqual(prompt_guard.honesty_score(row), prompt_guard.FLOOR)

    def test_refer_out_is_honest(self):
        row = {
            "message": "I'm not a doctor — talk to a clinician.",
            "guidance_band": "refer_out",
            "confidence": 1.0,
        }
        self.assertEqual(prompt_guard.honesty_score(row), 100.0)


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
    def test_stable_facts_return_first_even_if_wording_moves(self):
        calls = {"n": 0}

        def produce():
            calls["n"] += 1
            return {
                "message": f"same idea #{calls['n']}",
                "response_type": "insight",
                "recommendation": "Easy day",
                "confidence": 0.85,
            }

        row = prompt_guard.confirm(produce)
        self.assertEqual(row["recommendation"], "Easy day")
        self.assertEqual(calls["n"], 2)

    def test_wobbly_facts_raise_connection_line(self):
        calls = {"n": 0}

        def produce():
            calls["n"] += 1
            return {
                "message": "Train.",
                "response_type": "recommendation",
                "recommendation": "Lift" if calls["n"] == 1 else "Rest",
                "confidence": 0.85,
            }

        with self.assertRaises(prompt_guard.PromptInconsistent) as raised:
            prompt_guard.confirm(produce)
        self.assertEqual(str(raised.exception), prompt_guard.CONNECTION_FAILURE)
        self.assertEqual(raised.exception.reason, "determinism")

    def test_honesty_below_floor_raises_connection_line(self):
        def produce():
            return {
                "message": "Go hard.",
                "recommendation": "Max effort",
                "epistemic_honesty": 40,
                "confidence": 0.95,
            }

        with self.assertRaises(prompt_guard.PromptInconsistent) as raised:
            prompt_guard.confirm(produce)
        self.assertEqual(str(raised.exception), prompt_guard.CONNECTION_FAILURE)
        self.assertEqual(raised.exception.reason, "honesty")


class EngineReplayTests(unittest.TestCase):
    def test_generate_response_replays_the_same_facts(self):
        first = aria_engine.generate_response("Should I train today?", _ctx())
        second = aria_engine.generate_response("Should I train today?", _ctx())
        self.assertTrue(prompt_guard.passes(first, second))
        self.assertTrue(first.get("message") or first.get("prose_summary"))
        self.assertGreaterEqual(prompt_guard.honesty_score(first), prompt_guard.FLOOR)


class ChatRouteGuardTests(unittest.TestCase):
    def setUp(self):
        self._flag = os.environ.get("FORGE_PROMPT_GUARD")
        os.environ["FORGE_PROMPT_GUARD"] = "1"

    def tearDown(self):
        if self._flag is None:
            os.environ.pop("FORGE_PROMPT_GUARD", None)
        else:
            os.environ["FORGE_PROMPT_GUARD"] = self._flag

    def test_wording_wobble_still_speaks(self):
        calls = {"n": 0}
        real = aria_engine.generate_response

        def wobble(message, ctx, **kwargs):
            calls["n"] += 1
            row = dict(real(message, ctx, **kwargs))
            row["message"] = f"{row.get('message') or ''} #{calls['n']}"
            row["prose_summary"] = row["message"]
            return row

        with patch.object(aria_routes.aria_engine, "generate_response", side_effect=wobble):
            result = aria_routes.handle_post_ai_chat(
                {"message": "How did I sleep last night?", "user_id": "test-user-00000000"},
                user_id="test-user-00000000",
            )
        self.assertEqual(result.get("statusCode") or 200, 200)
        self.assertGreaterEqual(calls["n"], 2)

    def test_wobbly_facts_become_a_connection_failure(self):
        calls = {"n": 0}
        real = aria_engine.generate_response

        def wobble(message, ctx, **kwargs):
            calls["n"] += 1
            row = dict(real(message, ctx, **kwargs))
            row["recommendation"] = f"plan #{calls['n']}"
            if isinstance(row.get("card"), dict):
                row["card"] = dict(row["card"], action=row["recommendation"])
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
