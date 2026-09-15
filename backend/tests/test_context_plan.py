"""Raw-data supervision plan: evaluate, store as context, learn retroactively."""

from __future__ import annotations

import os
import unittest
from pathlib import Path

import _bootstrap  # noqa: F401

from services import aria_engine, context_plan, contextual_learner  # noqa: E402
from storage import dynamodb  # noqa: E402

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.tests.test_contextual_learner import _ctx  # noqa: E402


def _depleted(**kwargs):
    ctx = _ctx(recovery=40, sleep_minutes=5 * 60, **kwargs)
    ctx.readiness.hrv_7day_trend = -12
    ctx.sleep.resting_hr = 74
    return ctx


def _holding(**kwargs):
    ctx = _ctx(recovery=82, sleep_minutes=8 * 60, **kwargs)
    ctx.readiness.hrv_7day_trend = 8
    ctx.sleep.resting_hr = 54
    return ctx


class AgingEvaluationTests(unittest.TestCase):
    def test_depleted_body_is_aging_faster(self):
        read = context_plan.evaluate_aging(_depleted(), "should I train today?")
        self.assertEqual(read.pace, "faster")
        self.assertIn("hrv", read.signals)
        self.assertGreater(read.wear, 0.4)

    def test_holding_body_is_aging_slower(self):
        read = context_plan.evaluate_aging(_holding(), "feeling good")
        self.assertEqual(read.pace, "slower")

    def test_empty_context_is_unknown(self):
        read = context_plan.evaluate_aging(_ctx(), "hey")
        self.assertEqual(read.pace, "unknown")

    def test_conversation_used_to_recover_marks_faster(self):
        read = context_plan.evaluate_aging(_ctx(), "I don't recover like I used to recover")
        self.assertEqual(read.pace, "faster")
        self.assertIn("conversation", read.signals)


class SupervisionPlanTests(unittest.TestCase):
    def test_raw_data_becomes_a_stored_plan(self):
        state = contextual_learner.PersonaState()
        plan = context_plan.evaluate_and_store(
            state, "should I train today?", _depleted()
        )
        self.assertEqual(plan.aging_pace, "faster")
        self.assertIn(plan.choice, ("protect_load", "sleep_first"))
        self.assertTrue(plan.next_advice)
        self.assertTrue(plan.guide)
        self.assertEqual(state.last_plan_choice, plan.choice)
        self.assertEqual(state.last_plan["choice"], plan.choice)
        self.assertGreater(state.aging["faster"], 1.0)

    def test_wedding_still_leads_and_plan_protects(self):
        ctx = _ctx(
            tags=["calendar:kind:wedding", "calendar:evening:busy"],
            recovery=62,
            sleep_minutes=430,
        )
        state = contextual_learner.PersonaState()
        brief = contextual_learner.apply_chat_turn(
            state, message="what should I train today?", ctx=ctx
        )
        self.assertEqual(brief.prioritize[0], "lifestyle")
        self.assertEqual(brief.plan_choice, "protect_load")
        self.assertEqual(brief.event_bucket, "wedding")
        blob = brief.aria_instructions()
        self.assertIn("plan_choice", blob)
        self.assertIn("aging_pace", blob)
        self.assertNotIn("Ritz", blob)
        self.assertNotIn("Maya", blob)

    def test_wedding_plus_wear_still_leads_lifestyle(self):
        ctx = _depleted(
            tags=["calendar:kind:wedding", "calendar:evening:busy"],
        )
        brief = contextual_learner.adapt("what should I train today?", ctx)
        self.assertEqual(brief.prioritize[0], "lifestyle")
        self.assertEqual(brief.event_bucket, "wedding")
        self.assertEqual(brief.plan_choice, "protect_load")
        self.assertEqual(brief.aging_pace, "faster")

    def test_adapt_exposes_plan_as_context(self):
        brief = contextual_learner.adapt(
            "should I train today?", _depleted()
        )
        self.assertEqual(brief.aging_pace, "faster")
        self.assertIn(brief.plan_choice, ("protect_load", "sleep_first"))
        self.assertTrue(brief.next_advice)
        self.assertIn("supervision_plan", brief.as_dict())
        self.assertEqual(brief.as_dict()["supervision_plan"]["choice"], brief.plan_choice)

    def test_titles_never_enter_the_plan(self):
        ctx = _ctx(
            tags=["calendar:kind:wedding", "Maya's wedding at the Ritz"],
            recovery=40,
            sleep_minutes=5 * 60,
        )
        plan = context_plan.draft_plan("train today?", ctx, contextual_learner.PersonaState())
        blob = " ".join(
            [plan.next_advice, plan.guide, plan.aging_reason, str(plan.as_dict())]
        )
        self.assertNotIn("Ritz", blob)
        self.assertNotIn("Maya", blob)


class RetroactivePlanLearningTests(unittest.TestCase):
    def test_outcomes_credit_the_plan_choice(self):
        state = contextual_learner.PersonaState()
        ctx = _depleted()
        contextual_learner.apply_chat_turn(
            state, message="should I train today?", ctx=ctx
        )
        choice = state.last_plan_choice
        self.assertTrue(choice)
        before = context_plan._plan_q(state, "faster", choice)
        contextual_learner.apply_workout_outcome(
            state, completed=False, evening_busy=False
        )
        after = context_plan._plan_q(state, "faster", choice)
        self.assertGreater(after, before)
        self.assertEqual(state.last_plan_choice, choice)

    def test_persona_roundtrip_keeps_plan(self):
        dynamodb.clear_local_store()
        state = contextual_learner.PersonaState()
        context_plan.evaluate_and_store(state, "train?", _depleted())
        context_plan.credit_plan(state, 0.85)
        uid = "plan-roundtrip"
        contextual_learner.save(uid, state)
        loaded = contextual_learner.load(uid)
        self.assertEqual(loaded.last_plan_choice, state.last_plan_choice)
        self.assertEqual(loaded.last_aging_pace, "faster")
        self.assertTrue(loaded.last_plan)
        self.assertGreater(loaded.aging["faster"], 1.0)
        self.assertGreater(
            context_plan._plan_q(loaded, "faster", loaded.last_plan_choice),
            0.0,
        )

    def test_living_context_roundtrip_keeps_plan(self):
        from services.aria_context import UserContext

        plan = context_plan.draft_plan(
            "train?", _depleted(), contextual_learner.PersonaState()
        ).as_dict()
        ctx = UserContext(user_id="u-plan", supervision_plan=plan)
        restored = UserContext.from_dict(ctx.to_dict())
        self.assertEqual(restored.supervision_plan["choice"], plan["choice"])
        self.assertEqual(restored.supervision_plan["aging_pace"], plan["aging_pace"])


class DummyDoesNotOwnPlanTests(unittest.TestCase):
    _CLOUD = (
        "ENVIRONMENT",
        "AWS_LAMBDA_FUNCTION_NAME",
        "AWS_EXECUTION_ENV",
        "AWS_LAMBDA_RUNTIME_API",
        "K_SERVICE",
        "FUNCTION_TARGET",
        "WEBSITE_INSTANCE_ID",
    )

    def setUp(self):
        self._saved = {key: os.environ.get(key) for key in self._CLOUD}
        for key in self._CLOUD:
            os.environ.pop(key, None)

    def tearDown(self):
        for key, value in self._saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_dummy_source_never_imports_the_plan_engine(self):
        text = Path(dummy.__file__).read_text()
        self.assertNotIn("context_plan", text)
        self.assertNotIn("self_trainer", text)
        self.assertIn("services.contextual_learner", text)

    def test_dummy_sidecar_carries_the_plan(self):
        row = dummy.respond("What should I train today?", seed=42)
        self.assertEqual(row["orchestration"]["owner"], "live-backend")
        self.assertIn("plan", row["orchestration"]["learner_stages"])
        self.assertIn("plan_choice", row["contextualization"])
        self.assertIn("aging_pace", row["contextualization"])
        self.assertNotIn("Ritz", str(row["contextualization"]))

    def test_learning_law_mentions_the_plan(self):
        prompt = aria_engine.live_system_prompt()
        self.assertIn("supervision plan", prompt)
        self.assertIn("aging_pace", prompt)
        self.assertLess(prompt.index("LEARNING LAW"), prompt.index("SECURITY LAW"))


if __name__ == "__main__":
    unittest.main()
