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
        self.assertNotEqual(payload["context"]["training"].get("weeklyLoadScore"), 1.42)

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


class QualitativeSpeakFallbackTests(unittest.TestCase):
    """_scrub_fused_speak/friend_speak used to be all-or-nothing: the instant
    the lambda engine's real prose_summary/message tripped the vitals scrub
    (which _insight_response's own text reliably does -- it's literally
    "{metric}: {value}. {interpretation}." and the interpretation itself
    often embeds a number too, e.g. "Deep sleep at 21% is in a healthy
    band"), friend_speak discarded it entirely and handed back a lone,
    topic-disconnected wit-bank line. A real engine answer that correctly
    read 8.4h of great sleep and a sparse-context clarify scenario ended up
    looking identical either way. _qualitative_speak gives friend_speak a
    real, number-free, on-topic sentence to reach for first."""

    def test_qualitative_speak_returns_a_sleep_bank_line_for_the_sleep_topic(self):
        signals = dummy.SignalRead(
            sleep="rebuilt", recovery="steady", load="quiet", life="",
            missing=(), last_session="", notable="",
        )
        result = dummy._qualitative_speak(1, "sleep", signals)
        self.assertIn(result, dummy._SLEEP_TALK["rebuilt"])

    def test_qualitative_speak_picks_the_field_matching_the_topic(self):
        signals = dummy.SignalRead(
            sleep="thin", recovery="ready", load="on_a_streak", life="",
            missing=(), last_session="", notable="",
        )
        self.assertIn(dummy._qualitative_speak(2, "sleep", signals), dummy._SLEEP_TALK["thin"])
        self.assertIn(dummy._qualitative_speak(2, "recovery", signals), dummy._RECOVERY_TALK["ready"])
        self.assertIn(dummy._qualitative_speak(2, "workout", signals), dummy._LOAD_TALK["on_a_streak"])

    def test_qualitative_speak_empty_for_a_topic_it_does_not_cover(self):
        signals = dummy.SignalRead(
            sleep="rebuilt", recovery="steady", load="quiet", life="",
            missing=(), last_session="", notable="",
        )
        self.assertEqual(dummy._qualitative_speak(1, "aging", signals), "")
        self.assertEqual(dummy._qualitative_speak(1, "", signals), "")
        self.assertEqual(dummy._qualitative_speak(1, "sleep", None), "")

    def test_scrub_fused_speak_reduces_a_vitals_dump_to_the_fallback_sentinel(self):
        # The precondition the next two tests build on: _scrub_fused_speak
        # (called before friend_speak in _respond_via_lambda) really does
        # collapse _insight_response-style raw prose to _SPEAK_FALLBACK,
        # which is what actually triggers friend_speak's rescue branch.
        vitals_dump = "Sleep: 8.4 h total, 107 min deep (21%). Deep sleep at 21% is in a healthy band."
        envelope = dummy._scrub_fused_speak({"prose_summary": vitals_dump, "message": vitals_dump})
        self.assertEqual(envelope["prose_summary"], dummy._SPEAK_FALLBACK)
        self.assertEqual(envelope["message"], dummy._SPEAK_FALLBACK)

    def test_friend_speak_falls_back_to_qualitative_content_not_bare_wit(self):
        # What friend_speak actually receives once _scrub_fused_speak has run
        # on an _insight_response-style vitals dump (see the test above) --
        # not the raw text itself, which friend_speak never gets a chance to
        # rescue since _scrub_fused_speak already reduced it upstream.
        signals = dummy.SignalRead(
            sleep="rebuilt", recovery="steady", load="quiet", life="",
            missing=(), last_session="", notable="",
        )
        result = dummy.friend_speak(dummy._SPEAK_FALLBACK, seed=7, signals=signals, topic="sleep")
        # friend_speak capitalizes the qualitative sentence as a proper
        # opener, so compare case-insensitively against the (lowercase) bank.
        self.assertTrue(
            any(line in result.lower() for line in dummy._SLEEP_TALK["rebuilt"]),
            f"expected a _SLEEP_TALK[rebuilt] line inside {result!r}",
        )
        # Never reintroduces what the scrub was catching in the first place.
        self.assertNotIn("21%", result)
        self.assertNotIn("107 min", result)

    def test_friend_speak_without_a_topic_keeps_the_old_wit_only_behavior(self):
        signals = dummy.SignalRead(
            sleep="rebuilt", recovery="steady", load="quiet", life="",
            missing=(), last_session="", notable="",
        )
        result = dummy.friend_speak(dummy._SPEAK_FALLBACK, seed=7, signals=signals)
        self.assertTrue(any(line in result for line in dummy._WIT_HONEST + dummy._WIT_PROTECT + dummy._WIT_PROCEED))


class IOSWeeklyLoadParityTests(unittest.TestCase):
    """Dummy must send weeklyLoadScore / trainingLoadTrend the way iOS does.

    AriaContextStore.swift:130 — last-7 workout minutes when >= 3 sessions.
    AriaContextStore.swift:188 — trainingLoadTrend is 'steady' at that floor,
    not Dummy ``readiness_trend``.
    """

    def test_ios_rule_three_or_more_sessions(self):
        ctx, _ = _ctx()
        ctx.readiness_trend = "rising"
        for rec in ctx.history:
            rec.workout_logged = False
            rec.workout_duration_minutes = None
        for rec, minutes in zip(ctx.history[-4:], (30, 40, 50, 60)):
            rec.workout_logged = True
            rec.workout_duration_minutes = minutes
        payload = dummy.sim_context_to_chat_payload(ctx)
        self.assertEqual(payload["context"]["training"]["weeklyLoadScore"], 180.0)
        self.assertEqual(payload["context"]["progress"]["trainingLoadTrend"], "steady")
        self.assertNotEqual(
            payload["context"]["progress"]["trainingLoadTrend"],
            ctx.readiness_trend,
        )

    def test_ios_rule_fewer_than_three_sessions_is_silent(self):
        ctx, _ = _ctx()
        ctx.readiness_trend = "falling"
        for rec in ctx.history:
            rec.workout_logged = False
            rec.workout_duration_minutes = None
        for rec, minutes in zip(ctx.history[-2:], (45, 50)):
            rec.workout_logged = True
            rec.workout_duration_minutes = minutes
        payload = dummy.sim_context_to_chat_payload(ctx)
        self.assertIsNone(payload["context"]["training"]["weeklyLoadScore"])
        self.assertIsNone(payload["context"]["progress"]["trainingLoadTrend"])

    def test_last_seven_sessions_only(self):
        ctx, _ = _ctx()
        for rec in ctx.history:
            rec.workout_logged = True
            rec.workout_duration_minutes = 10
        for rec in ctx.history[-7:]:
            rec.workout_duration_minutes = 20
        payload = dummy.sim_context_to_chat_payload(ctx)
        self.assertEqual(payload["context"]["training"]["weeklyLoadScore"], 140.0)
        self.assertEqual(payload["context"]["progress"]["trainingLoadTrend"], "steady")


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

    def test_same_day_strength_never_says_zero_hours_since(self):
        ctx, _ = _ctx()
        ctx.days_since_last_workout = 0
        ctx.today.workout_logged = True
        ctx.last_workout_type = "strength"
        row = dummy.respond("Should I train today?", seed=1, engine="lambda", context=ctx)
        blob = " ".join(
            str(p)
            for p in (
                row.get("prose_summary"),
                row.get("message"),
                row.get("recommendation"),
                (row.get("card") or {}).get("action") if isinstance(row.get("card"), dict) else "",
                (row.get("card") or {}).get("why") if isinstance(row.get("card"), dict) else "",
            )
            if p
        ).lower()
        self.assertNotIn("0 h since", blob)
        self.assertNotIn("only 0 h since strength", blob)

    def test_progress_question_gets_a_sized_recommendation(self):
        ctx, _ = _ctx()
        ctx.training_streak = 14
        ctx.readiness_trend = "rising"
        ctx.today.readiness_score = 72
        engine = dummy.DummyARIAEngine()
        resp = engine.respond("Am I making progress?", ctx, seed=1)
        self.assertIsNotNone(resp.recommendation)
        self.assertTrue(str(resp.recommendation).strip())
        low = resp.recommendation.lower()
        self.assertTrue(
            any(w in low for w in ("hold", "progress", "block", "session", "minute", "variable")),
            resp.recommendation,
        )

    def test_deterministic_path_strips_repair_in_the_bank_guide(self):
        ctx, _ = _ctx()
        row = dummy.respond("Should I train today?", seed=1, engine="lambda", context=ctx)
        blob = f"{row.get('prose_summary') or ''} {row.get('message') or ''}"
        self.assertNotIn("they have repair in the bank", blob.lower())


if __name__ == "__main__":
    unittest.main()
