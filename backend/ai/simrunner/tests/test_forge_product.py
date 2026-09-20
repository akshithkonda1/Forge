"""Forge product contracts: iOS agents, Health pack, dummy scoring, first bond."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner import fake_health_pack as pack  # noqa: E402
from backend.ai.simrunner.aria_simrunner import first_bond  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_evaluator import evaluate  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import build_context  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402


class AgentLockstepTests(unittest.TestCase):
    def test_dummy_kinds_match_ios_coach_agents(self):
        self.assertEqual(set(dummy._KINDS), set(first_bond.IOS_AGENT_KINDS))


class FakeHealthPackTests(unittest.TestCase):
    def test_thirty_oldest_first_days_with_debt(self):
        body = pack.generate(seed=7)
        self.assertEqual(len(body["days"]), 30)
        dates = [d["isoDate"] for d in body["days"]]
        self.assertEqual(dates, sorted(dates))
        today = pack.today_day(body)
        self.assertIn("hrvMs", today)
        self.assertIn("sleepDebtHours", today)
        self.assertGreater(today["night"]["totalMinutes"], 0)

    def test_dummy_default_body_is_the_pack(self):
        row = dummy.respond("How did I sleep last night?", seed=42, use_pack=True, engine="stub")
        self.assertTrue(row["test_ready"])
        self.assertEqual(row["user_id"], "test-user-00000000")
        self.assertEqual(row["orchestration"]["day_index"], 29)


class DummySafetyTests(unittest.TestCase):
    def test_high_sleep_debt_recovery_protects_sleep(self):
        model = reg.get_models_by_tier(1)[0]
        stream = generate_stream(model["behavioral_profile"], seed=42)
        ctx = build_context(stream, model["behavioral_profile"], 29)
        # Set the underlying per-night hours, not just the derived summary
        # field: the "stub" engine reads ctx.sleep_debt_7d_hours directly, but
        # the "lambda" engine (DummyARIAEngine, below) fuses real per-night
        # samples through BodyModel, which recomputes its own 7-day debt from
        # ctx.history -- patching only the summary field left that path
        # looking at a stream of ordinary, healthy nights and correctly (not
        # a bug) computing near-zero debt from them.
        for record in ctx.history[-7:]:
            record.total_sleep_hours = 6.33  # ~11.7h debt over 7 nights vs 8h target
        ctx.sleep_debt_7d_hours = 11.7
        row = dummy.respond("How's my recovery looking?", seed=1, context=ctx, engine="stub")
        text = (row["message"] + " " + (row.get("prose_summary") or "")).lower()
        self.assertTrue(
            "protect sleep" in text or "protect tonight" in text or "sleep" in text,
            text,
        )
        engine = dummy.DummyARIAEngine()
        resp = engine.respond("How's my recovery looking?", ctx, seed=1)
        result = evaluate(0, "How's my recovery looking?", 1, ctx, resp)
        self.assertFalse(
            any("did not prioritize sleep" in f for f in result.failures),
            result.failures,
        )


class FirstBondTests(unittest.TestCase):
    def test_yes_no_sequence_teaches_what_aria_is(self):
        turn = first_bond.start(name="Ada", has_health=True, goal="Build muscle", cycle=False)
        self.assertIn("Ada", turn.message)
        self.assertIn("Apple Health", turn.message)
        self.assertEqual(turn.next, "opening")

        turn = first_bond.advance("opening", "I'm here.")
        self.assertIn("not a doctor", turn.message)
        self.assertEqual(turn.replies, first_bond.YES_NO)

        turn = first_bond.advance("notDoctor", "No.")
        self.assertIn("won't diagnose", turn.message.lower().replace("’", "'"))
        self.assertIn("Apple Health", turn.message)

        turn = first_bond.advance("notGame", "Yes.", cycle=False)
        self.assertIn("Cycle stays out", turn.message)

        turn = first_bond.advance("invite", "How did I sleep?")
        self.assertTrue(turn.finishes)

    def test_device_hub_tester_id(self):
        row = dummy.respond("What should I train today?", seed=0)
        self.assertEqual(row["user_id"], "test-user-00000000")
        self.assertTrue(row["test_ready"])
        self.assertIn(row["reasoning_source"], (dummy.REASONING_SOURCE, dummy.LAMBDA_REASONING_SOURCE))
