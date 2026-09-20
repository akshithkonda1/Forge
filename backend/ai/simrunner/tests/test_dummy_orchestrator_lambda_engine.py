"""Regression tests for the DummyARIAEngine -> real engine wiring (P0-6):

- DummyARIAEngine.respond() used to hardcode engine="stub" even though
  dummy_orchestrator.respond()'s own default is engine="lambda" (real
  fuse_turn + generate_response) -- meaning SimRunner's ship/hold gate
  (lifetime_suite.py's `--test-ready --gate`) graded the synthetic stub
  every single run, never the shipped engine.
- sim_context_to_chat_payload (the bridge _respond_via_lambda uses) was
  silently dropping sleepDebt7dHours/targetHours entirely, and mapping
  ACWR into the wrong field (weeklyLoadScore instead of acwr) -- so even
  with the engine flipped, production's directional-safety checks that
  depend on those fields never saw real data from any SimRunner-driven run.
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import build_context  # noqa: E402


def _ctx(seed: int = 42, day_index: int = 29):
    model = reg.get_models_by_tier(1)[0]
    stream = generate_stream(model["behavioral_profile"], seed=seed)
    return build_context(stream, model["behavioral_profile"], day_index), model


class SimContextToChatPayloadTests(unittest.TestCase):
    def test_carries_7d_sleep_debt_and_target(self):
        ctx, _ = _ctx()
        ctx.sleep_debt_7d_hours = 4.4
        ctx.target_sleep_hours = 7.5
        payload = dummy.sim_context_to_chat_payload(ctx)
        self.assertEqual(payload["context"]["sleep"]["sleepDebt7dHours"], 4.4)
        self.assertEqual(payload["context"]["sleep"]["targetHours"], 7.5)

    def test_acwr_lands_on_the_acwr_key_not_weekly_load_score(self):
        ctx, _ = _ctx()
        ctx.today.acwr = 1.42
        ctx.acwr = 1.42
        payload = dummy.sim_context_to_chat_payload(ctx)
        self.assertEqual(payload["context"]["training"]["acwr"], 1.42)
        self.assertNotIn("weeklyLoadScore", payload["context"]["training"])

    def test_carries_is_overtrained(self):
        ctx, _ = _ctx()
        ctx.is_overtrained = True
        payload = dummy.sim_context_to_chat_payload(ctx)
        self.assertTrue(payload["context"]["training"]["isOvertrained"])

    def test_carries_chronotype_sleep_onset_derived_from_wake_and_target(self):
        ctx, _ = _ctx()
        ctx.target_wake_hour = 7.0
        ctx.target_sleep_hours = 8.0
        payload = dummy.sim_context_to_chat_payload(ctx)
        self.assertEqual(payload["context"]["chronotype"]["typicalWakeTime"], "07:00")
        self.assertEqual(payload["context"]["chronotype"]["typicalSleepOnset"], "23:00")


class DummyARIAEngineUsesLambdaTests(unittest.TestCase):
    def test_respond_calls_the_real_engine_not_the_scripted_stub(self):
        ctx, _ = _ctx()
        engine = dummy.DummyARIAEngine()
        resp = engine.respond("Should I train today?", ctx, seed=1)
        # The scripted stub's scenarios (sparse_clarify, capitulation, etc.)
        # never appear on the lambda path; the row's own "engine" tag does.
        self.assertNotEqual(engine.detect_model(), dummy.STUB_MODEL)
        self.assertEqual(engine.detect_model(), dummy.LAMBDA_MODEL)
        self.assertIsNotNone(resp.prose_summary)

    def test_recommendation_responses_carry_a_real_recommendation(self):
        """card.get("action") must reach ARIAResponse.recommendation -- the
        lambda row previously had no top-level "recommendation" key at all,
        so every lambda-engine response silently scored recommendation=None
        regardless of response_type. A high sleep-debt week reliably
        resolves to the "recommendation" response_type via the sleep_debt
        evidence pattern (see test_sleep_debt_gaps.py for the underlying
        stance/pattern fixes this relies on)."""
        ctx, _ = _ctx()
        for record in ctx.history[-7:]:
            record.total_sleep_hours = 6.33
        ctx.sleep_debt_7d_hours = 11.7
        engine = dummy.DummyARIAEngine()
        resp = engine.respond("Should I train today?", ctx, seed=1)
        self.assertIsInstance(resp.recommendation, str)
        self.assertTrue(resp.recommendation)
        self.assertIn("sleep", resp.recommendation.lower())


if __name__ == "__main__":
    unittest.main()
