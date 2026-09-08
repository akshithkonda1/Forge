"""ARIA self-training critic — lives with the live learner, never the dummy."""

from __future__ import annotations

import os
import unittest
from pathlib import Path

import _bootstrap  # noqa: F401

from services import aria_engine, contextual_learner, self_trainer  # noqa: E402
from storage import dynamodb  # noqa: E402

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.tests.test_contextual_learner import _ctx  # noqa: E402


class ConversationLabelTests(unittest.TestCase):
    def test_didnt_help_is_wrong(self):
        self.assertEqual(self_trainer.conversation_reward("that didn't help"), -0.65)

    def test_that_helped_is_right(self):
        self.assertEqual(self_trainer.conversation_reward("that helped a lot"), 0.65)

    def test_ordinary_chat_is_not_a_verdict(self):
        self.assertIsNone(self_trainer.conversation_reward("should I train today?"))

    def test_tie_is_not_a_verdict(self):
        self.assertIsNone(
            self_trainer.conversation_reward("you're right but that didn't help")
        )


class JudgeTests(unittest.TestCase):
    def test_weak_prediction_uses_sign_of_actual(self):
        self.assertEqual(self_trainer.judge(0.0, 0.7), "right")
        self.assertEqual(self_trainer.judge(0.0, -0.65), "wrong")

    def test_small_actual_is_mixed(self):
        self.assertEqual(self_trainer.judge(0.4, 0.02), "mixed")

    def test_sign_mismatch_is_wrong(self):
        self.assertEqual(self_trainer.judge(0.4, -0.7), "wrong")
        self.assertEqual(self_trainer.judge(-0.4, 0.7), "wrong")

    def test_same_sign_is_right(self):
        self.assertEqual(self_trainer.judge(0.4, 0.7), "right")


class LearnerSelfTrainTests(unittest.TestCase):
    def test_conversation_after_commit_marks_wrong(self):
        state = contextual_learner.PersonaState()
        ctx = _ctx(recovery=80, sleep_minutes=480)
        contextual_learner.apply_chat_turn(
            state, message="should I train today?", ctx=ctx
        )
        self.assertTrue(state.last_stance)
        contextual_learner.apply_chat_turn(
            state, message="that didn't help", ctx=ctx
        )
        self.assertGreaterEqual(state.n_wrong, 1)
        self.assertEqual(state.last_verdict, "wrong")
        self.assertGreaterEqual(state.n_self_train, 1)

    def test_complete_after_proceed_marks_right(self):
        state = contextual_learner.PersonaState()
        key = contextual_learner.bucket(
            {
                "evening_busy": 0.0,
                "headline": 0.0,
                "low_recovery": 0.0,
                "high_recovery": 1.0,
                "short_sleep": 0.0,
            }
        )
        contextual_learner.commit_action(state, key, "proceed", ("workout",))
        contextual_learner.apply_workout_outcome(state, completed=True)
        self.assertGreaterEqual(state.n_right, 1)
        self.assertEqual(state.last_verdict, "right")

    def test_same_sign_td_errors_raise_alpha(self):
        state = contextual_learner.PersonaState()
        key = contextual_learner.bucket(
            {
                "evening_busy": 1.0,
                "headline": 0.0,
                "low_recovery": 0.0,
                "high_recovery": 1.0,
                "short_sleep": 0.0,
            }
        )
        start = contextual_learner.TD_ALPHA
        for _ in range(6):
            contextual_learner.commit_action(
                state,
                key,
                "proceed",
                ("workout",),
                event_bucket_key="evening_busy",
                priority=["training", "lifestyle"],
            )
            contextual_learner.apply_workout_outcome(
                state, completed=False, evening_busy=True
            )
        self.assertGreater(state.td_alpha, start)
        raised = state.td_alpha
        contextual_learner.apply_workout_outcome(
            state, completed=True, evening_busy=True
        )
        self.assertLess(state.td_alpha, raised)

    def test_persona_roundtrip_keeps_critic(self):
        dynamodb.clear_local_store()
        state = contextual_learner.PersonaState()
        contextual_learner.commit_action(
            state,
            "evening_busy|mixed",
            "protect",
            ("lifestyle",),
            event_bucket_key="evening_busy",
            priority=["lifestyle", "sleep"],
            stance_p=0.7,
            sources=("event", "conversation"),
        )
        contextual_learner.reinforce(state, 0.85)
        state.source_w["event"] = 1.16
        uid = "self-trainer-roundtrip"
        contextual_learner.save(uid, state)
        loaded = contextual_learner.load(uid)
        self.assertEqual(loaded.td_alpha, state.td_alpha)
        self.assertEqual(loaded.n_right, state.n_right)
        self.assertEqual(loaded.n_wrong, state.n_wrong)
        self.assertEqual(loaded.calibration, state.calibration)
        self.assertEqual(loaded.source_w["event"], 1.16)
        self.assertEqual(loaded.last_verdict, state.last_verdict)
        self.assertEqual(loaded.last_sources, ("event", "conversation"))

    def test_titles_never_leak_in_verdict_or_instructions(self):
        ctx = _ctx(
            tags=[
                "calendar:kind:wedding",
                "Maya's wedding at the Ritz",
                "calendar:title:secret",
            ]
        )
        state = contextual_learner.PersonaState()
        brief = contextual_learner.apply_chat_turn(
            state, message="train today?", ctx=ctx
        )
        blob = " ".join(
            [
                brief.priority_reason,
                brief.aria_instructions(),
                str(brief.last_verdict),
                str(brief.as_dict()),
            ]
        )
        self.assertNotIn("Ritz", blob)
        self.assertNotIn("Maya", blob)
        self.assertNotIn("secret", blob)
        self.assertEqual(brief.prioritize[0], "lifestyle")

    def test_wedding_still_leads_train_today_after_source_w(self):
        ctx = _ctx(
            tags=["calendar:kind:wedding", "calendar:evening:busy"],
            recovery=62,
            sleep_minutes=430,
        )
        state = contextual_learner.PersonaState()
        state.source_w["conversation"] = 1.4
        brief = contextual_learner.adapt("what should I train today?", ctx, state)
        self.assertEqual(brief.prioritize[0], "lifestyle")

    def test_learning_law_mentions_self_verdict(self):
        prompt = aria_engine.live_system_prompt()
        self.assertIn("last_verdict", prompt)
        self.assertIn("judges herself", prompt)
        self.assertLess(prompt.index("LEARNING LAW"), prompt.index("SECURITY LAW"))


class DummyDoesNotOwnCriticTests(unittest.TestCase):
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

    def test_dummy_source_never_imports_the_critic(self):
        text = Path(dummy.__file__).read_text()
        self.assertNotIn("TD_ALPHA", text)
        self.assertNotIn("self_trainer", text)
        self.assertIn("services.contextual_learner", text)
        self.assertIn("live-backend", text)

    def test_dummy_sidecar_still_owned_by_live_backend(self):
        row = dummy.respond("What should I train today?", seed=42)
        self.assertEqual(row["orchestration"]["owner"], "live-backend")
        self.assertEqual(row["orchestration"]["consumer"], "dummy-test")
        self.assertIn("judge", row["orchestration"]["learner_stages"])
        self.assertEqual(
            row["orchestration"]["prioritize"],
            row["contextualization"]["prioritize"],
        )
        self.assertNotIn("Ritz", str(row["contextualization"]))


if __name__ == "__main__":
    unittest.main()
