"""Production learner — lives on the Lambda hot path, dummy only consumes it."""

from __future__ import annotations

import os
import unittest
from pathlib import Path
from types import SimpleNamespace

import _bootstrap  # noqa: F401

from services import aria_engine, contextual_learner  # noqa: E402
from storage import dynamodb, keys  # noqa: E402

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402


def _ctx(**kwargs):
    lifestyle = SimpleNamespace(
        tags=list(kwargs.pop("tags", [])),
        recent_patterns=list(kwargs.pop("patterns", [])),
        goals=list(kwargs.pop("goals", [])),
    )
    sleep = SimpleNamespace(duration_minutes=kwargs.pop("sleep_minutes", None))
    readiness = SimpleNamespace(recovery_score=kwargs.pop("recovery", None))
    return SimpleNamespace(
        lifestyle=lifestyle,
        sleep=sleep,
        readiness=readiness,
        missing_fields=kwargs.pop("missing_fields", []),
        has_sleep=kwargs.pop("has_sleep", sleep.duration_minutes is not None),
        last_insights=list(kwargs.pop("insights", [])),
        constraints=list(kwargs.pop("constraints", [])),
        current_goals=list(kwargs.pop("goals_top", [])),
    )


class CalendarIngestTests(unittest.TestCase):
    def test_titles_places_and_attendees_never_survive(self):
        cal = contextual_learner.parse_calendar(
            [
                "calendar:kind:wedding",
                "calendar:evening:busy",
                "Maya's wedding at the Ritz",
                "calendar:title:secret",
                "with:alex@example.com",
            ]
        )
        self.assertEqual(cal.kinds, ("wedding",))
        self.assertTrue(cal.evening_busy)
        blob = str(cal.as_dict())
        self.assertNotIn("Ritz", blob)
        self.assertNotIn("Maya", blob)
        self.assertNotIn("alex", blob)

    def test_unknown_kind_is_dropped(self):
        cal = contextual_learner.parse_calendar(["calendar:kind:bachelor-party"])
        self.assertEqual(cal.kinds, ())


class PolicyTests(unittest.TestCase):
    def test_wedding_and_evening_busy_protects_on_turn_one(self):
        ctx = _ctx(
            tags=["calendar:kind:wedding", "calendar:evening:busy", "calendar:busy:4"],
            recovery=62,
            sleep_minutes=430,
        )
        brief = contextual_learner.adapt("what should I train today?", ctx)
        self.assertEqual(brief.stance, "protect")
        self.assertEqual(brief.grounding, "contextual")
        self.assertTrue(brief.teach_user)
        self.assertIn("lifestyle", brief.specialists)
        self.assertEqual(brief.prioritize[0], "lifestyle")
        self.assertEqual(brief.event_bucket, "wedding")
        self.assertIn("event=wedding", brief.priority_reason)
        blob = brief.aria_instructions()
        self.assertIn("prioritize:", blob)
        self.assertNotIn("Ritz", blob)
        self.assertNotIn("Maya", blob)

    def test_empty_context_still_coaches_generalized(self):
        brief = contextual_learner.adapt("hey", _ctx())
        self.assertIn(brief.stance, contextual_learner.STANCES)
        self.assertEqual(brief.grounding, "generalized")
        self.assertTrue(brief.teach_user)
        self.assertTrue(brief.aria_instructions())

    def test_short_sleep_train_ask_protects(self):
        ctx = _ctx(sleep_minutes=4 * 60, recovery=40)
        brief = contextual_learner.adapt("should I train today?", ctx)
        self.assertEqual(brief.stance, "protect")
        self.assertEqual(brief.grounding, "contextual")


class ReinforcementTests(unittest.TestCase):
    def test_complete_after_proceed_raises_q(self):
        state = contextual_learner.PersonaState()
        feat = {
            "evening_busy": 0.0,
            "headline": 0.0,
            "low_recovery": 0.0,
            "high_recovery": 1.0,
            "short_sleep": 0.0,
        }
        key = contextual_learner.bucket(feat)
        contextual_learner.commit_action(state, key, "proceed", ("workout",))
        before = contextual_learner._q(state, key, "proceed")
        delta = contextual_learner.reinforce(
            state,
            contextual_learner.reward_for_workout(
                completed=True, last_stance="proceed"
            ),
        )
        after = contextual_learner._q(state, key, "proceed")
        self.assertGreater(after, before)
        self.assertNotEqual(delta, 0.0)

    def test_skips_on_busy_evening_teach_protect(self):
        state = contextual_learner.PersonaState()
        ctx = _ctx(tags=["calendar:evening:busy"], recovery=70, sleep_minutes=430)
        for _ in range(8):
            brief = contextual_learner.apply_chat_turn(
                state,
                message="what should I train tonight?",
                ctx=ctx,
                tags=["calendar:evening:busy"],
            )
            contextual_learner.apply_workout_outcome(
                state,
                completed=False,
                evening_busy=True,
            )
        later = contextual_learner.adapt("train tonight?", ctx, state)
        self.assertEqual(brief.stance in contextual_learner.STANCES, True)
        self.assertEqual(later.stance, "protect")
        self.assertGreaterEqual(state.n_updates, 8)
        self.assertTrue(later.teach_user)

    def test_persona_roundtrip_keeps_q(self):
        dynamodb.clear_local_store()
        state = contextual_learner.PersonaState()
        contextual_learner.commit_action(
            state,
            "evening_busy|mixed",
            "protect",
            ("lifestyle",),
            event_bucket_key="evening_busy",
            priority=["lifestyle", "sleep", "training"],
        )
        contextual_learner.reinforce(state, 0.85)
        uid = "learner-roundtrip"
        contextual_learner.save(uid, state)
        loaded = contextual_learner.load(uid)
        self.assertEqual(loaded.last_stance, "protect")
        self.assertEqual(loaded.n_updates, 1)
        self.assertEqual(keys.aria_persona_key(uid)["sk"], "ARIA#PERSONA")
        self.assertGreater(
            contextual_learner._q(loaded, "evening_busy|mixed", "protect"),
            0.0,
        )
        self.assertEqual(loaded.last_event_bucket, "evening_busy")
        self.assertEqual(loaded.last_priority[0], "lifestyle")
        self.assertGreater(
            contextual_learner._pq(loaded, "evening_busy", "lifestyle"),
            0.0,
        )


class LiveEngineSidecarTests(unittest.TestCase):
    def test_generate_response_attaches_brief_without_changing_prose(self):
        ctx = aria_engine.ARIAContext()
        first = aria_engine.generate_response("should I train today?", ctx)
        self.assertIn("contextualization", first)
        self.assertIn(first["contextualization"]["stance"], contextual_learner.STANCES)
        prose = first["prose_summary"]
        again = aria_engine.generate_response("should I train today?", ctx)
        self.assertEqual(again["prose_summary"], prose)
        self.assertTrue(first["contextualization"]["teach_user"])

    def test_live_prompt_keeps_persona_then_learning_then_security(self):
        prompt = aria_engine.live_system_prompt()
        self.assertTrue(prompt.startswith(aria_engine.ARIA_SYSTEM_PROMPT))
        self.assertLess(prompt.index("You are ARIA"), prompt.index("LEARNING LAW"))
        self.assertLess(prompt.index("LEARNING LAW"), prompt.index("SECURITY LAW"))
        self.assertIn("[CONTEXTUALIZATION]", prompt)


class DummyConsumesProductionLearnerTests(unittest.TestCase):
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

    def test_dummy_does_not_own_the_learner(self):
        src = dummy.__file__
        text = Path(src).read_text()
        self.assertNotIn("TD_ALPHA", text)
        self.assertIn("services.contextual_learner", text)
        self.assertIn("live-backend", text)

    def test_respond_attaches_the_same_learner_sidecar(self):
        row = dummy.respond("What should I train today?", seed=42)
        self.assertTrue(row["prose_summary"].strip())
        self.assertIn("contextualization", row)
        self.assertEqual(row["orchestration"]["owner"], "live-backend")
        self.assertEqual(row["orchestration"]["consumer"], "dummy-test")
        self.assertTrue(row["orchestration"]["durable"])
        self.assertIn(row["contextualization"]["stance"], contextual_learner.STANCES)
        self.assertIn("prioritize", row["contextualization"])
        self.assertTrue(row["contextualization"]["prioritize"])
        self.assertEqual(row["orchestration"]["prioritize"], row["contextualization"]["prioritize"])
        self.assertNotIn("Ritz", str(row["contextualization"]))
        self.assertNotIn("Ritz", str(row["orchestration"]))

    def test_same_seed_still_deterministic_with_learner(self):
        a = dummy.respond("How did I sleep last night?", seed=7)
        b = dummy.respond("How did I sleep last night?", seed=7)
        self.assertEqual(a["prose_summary"], b["prose_summary"])
        self.assertEqual(a["agents"], b["agents"])
        self.assertEqual(
            a.get("contextualization", {}).get("stance"),
            b.get("contextualization", {}).get("stance"),
        )


class PriorityRankerTests(unittest.TestCase):
    def test_wedding_beats_train_today_language(self):
        ctx = _ctx(
            tags=["calendar:kind:wedding", "calendar:evening:busy"],
            recovery=62,
            sleep_minutes=430,
        )
        brief = contextual_learner.adapt("what should I train today?", ctx)
        self.assertEqual(brief.prioritize[0], "lifestyle")
        self.assertNotEqual(brief.prioritize[0], "training")
        self.assertEqual(brief.lead_domain, "lifestyle")
        self.assertEqual(brief.specialists[0], "lifestyle")
        self.assertEqual(brief.event_bucket, "wedding")

    def test_ingest_and_relationship_raise_sleep_on_a_clear_day(self):
        ctx = _ctx(
            insights=["sleep debt last night", "strong_sleep_recovery"],
            patterns=["strong_sleep_recovery"],
            recovery=70,
            sleep_minutes=430,
        )
        state = contextual_learner.PersonaState()
        contextual_learner.observe_relationship(state, 6)
        contextual_learner.observe_ingest(state, ctx)
        brief = contextual_learner.adapt("hey", ctx, state)
        self.assertEqual(brief.event_bucket, "clear")
        self.assertEqual(brief.prioritize[0], "sleep")
        cold = contextual_learner.adapt("hey", _ctx(recovery=70, sleep_minutes=430))
        self.assertLess(brief.prioritize.index("sleep"), cold.prioritize.index("sleep"))

    def test_skips_after_training_first_teach_lifestyle_priority(self):
        state = contextual_learner.PersonaState()
        ctx = _ctx(tags=["calendar:evening:busy"], recovery=70, sleep_minutes=430)
        key = contextual_learner.bucket(
            {
                "evening_busy": 1.0,
                "headline": 0.0,
                "low_recovery": 0.0,
                "high_recovery": 1.0,
                "short_sleep": 0.0,
            }
        )
        for _ in range(6):
            contextual_learner.commit_action(
                state,
                key,
                "proceed",
                ("workout",),
                event_bucket_key="evening_busy",
                priority=["training", "lifestyle", "sleep"],
            )
            contextual_learner.apply_workout_outcome(
                state,
                completed=False,
                evening_busy=True,
            )
        self.assertLess(
            contextual_learner._pq(state, "evening_busy", "training"),
            contextual_learner._pq(state, "evening_busy", "lifestyle"),
        )
        later = contextual_learner.adapt("what should I train tonight?", ctx, state)
        self.assertEqual(later.event_bucket, "evening_busy")
        self.assertLess(
            later.prioritize.index("lifestyle"),
            later.prioritize.index("training"),
        )

    def test_titles_never_enter_priority_reason(self):
        ctx = _ctx(
            tags=[
                "calendar:kind:wedding",
                "Maya's wedding at the Ritz",
                "calendar:title:secret",
            ]
        )
        brief = contextual_learner.adapt("train today?", ctx)
        blob = " ".join(
            [
                brief.priority_reason,
                " ".join(brief.prioritize),
                brief.event_bucket,
                brief.aria_instructions(),
            ]
        )
        self.assertNotIn("Ritz", blob)
        self.assertNotIn("Maya", blob)
        self.assertNotIn("secret", blob)
        self.assertEqual(brief.event_bucket, "wedding")

    def test_stamp_living_context_feeds_ingest(self):
        ctx = _ctx()
        living = SimpleNamespace(
            last_insights=["sleep is the constraint this week"],
            recent_patterns=["strong_sleep_recovery"],
            current_goals=["protect sleep before volume"],
            constraints=["busy evenings"],
        )
        contextual_learner.stamp_living_context(ctx, living)
        self.assertIn("sleep is the constraint this week", ctx.last_insights)
        self.assertIn("strong_sleep_recovery", ctx.lifestyle.recent_patterns)
        state = contextual_learner.PersonaState()
        contextual_learner.observe_relationship(state, 7)
        contextual_learner.observe_ingest(state, ctx)
        brief = contextual_learner.adapt("hey", ctx, state)
        self.assertEqual(brief.prioritize[0], "sleep")


if __name__ == "__main__":
    unittest.main()
