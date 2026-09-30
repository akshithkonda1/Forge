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
import re
import sys
import unittest
from datetime import date, timedelta
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_generator import get_queries_for_tier  # noqa: E402
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
    """weeklyLoadScore still matches iOS; load trend follows the ACWR signal.

    AriaContextStore.swift:130 — last-7 workout minutes when >= 3 sessions.
    AriaContextStore.swift:188 hardcodes trainingLoadTrend 'steady' at that
    floor. Dummy used to copy that, which put 'load steady' next to ACWR 1.51.
    Non-blocking days still use the iOS floor; overreach uses 'rising'.
    """

    def test_ios_rule_three_or_more_sessions(self):
        ctx, _ = _ctx()
        ctx.readiness_trend = "rising"
        ctx.is_overtrained = False
        ctx.acwr = 1.0
        ctx.today.acwr = 1.0
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
        ctx.is_overtrained = False
        ctx.acwr = 1.0
        ctx.today.acwr = 1.0
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
        # Sleep lives on the spoken line; the button stays distinct.
        self.assertEqual(resp.recommendation.rstrip("."), "Keep today easy")
        self.assertIn("sleep", (resp.prose_summary or "").lower())

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

    def test_workouts_completed_30d_matches_pinned_acwr_load_series(self):
        """Recap count uses SIMRUNNER_TODAY + the same stream ACWR used.

        Main 61f5568 mapped training_streak (often 0 on a rest day) and
        hardcoded 'steady', so Scout t13 spoke '0 workouts' next to ACWR 1.51.
        That is a different load source, not Dummy reading datetime.now.
        iOS AriaContextStore.swift:109 cuts back from Date() — a harness
        clock mismatch if HealthKit dates are pinned to 2026-01-15.
        A wall-clock last-30-days filter from date.today() finds 0 on this
        stream; the pinned ACWR series does not.
        """
        os.environ["SIMRUNNER_TODAY"] = "2026-01-15"
        model = reg.get_model("meta.llama4-scout-17b")
        stream = generate_stream(model["behavioral_profile"], seed=42)
        day_index = 21
        ctx = build_context(stream, model["behavioral_profile"], day_index)
        window = stream[max(0, day_index - 29): day_index + 1]
        expected = sum(1 for rec in window if rec.workout_logged)
        self.assertGreater(expected, 0)
        self.assertEqual(ctx.workouts_completed_30d, expected)
        self.assertEqual(ctx.today.date, window[-1].date)
        self.assertTrue(str(ctx.today.date).startswith("2026-01-"))

        wall_cutoff = date.today() - timedelta(days=30)
        wall_count = 0
        for rec in window:
            if not rec.workout_logged:
                continue
            try:
                rec_day = date.fromisoformat(str(rec.date)[:10])
            except ValueError:
                continue
            if rec_day > wall_cutoff:
                wall_count += 1
        self.assertEqual(
            wall_count,
            0,
            "wall-clock last-30-days would find workouts; recap must not use date.today()",
        )

        from backend.ai.simrunner.aria_simrunner import production_bridge

        self.assertEqual(production_bridge.pinned_today(ctx), date.fromisoformat(ctx.today.date[:10]))
        self.assertNotEqual(production_bridge.pinned_today(ctx), date.today())
        self.assertEqual(production_bridge.workouts_completed_30d(ctx), expected)

        payload = dummy.sim_context_to_chat_payload(ctx)
        self.assertEqual(payload["context"]["progress"]["workoutsCompleted30d"], expected)
        if ctx.is_overtrained or ctx.acwr >= 1.5:
            self.assertEqual(payload["context"]["progress"]["trainingLoadTrend"], "rising")
        engine = dummy.DummyARIAEngine()
        resp = engine.respond("Am I making progress?", ctx, seed=42)
        spoken = f"{resp.prose_summary or ''} {getattr(resp, 'recommendation', '') or ''}"
        if ctx.is_overtrained:
            self.assertFalse(re.search(r"\d", resp.prose_summary or ""), resp.prose_summary)
            self.assertNotIn("load steady", spoken.lower())
            self.assertNotIn("last 30 days", (resp.prose_summary or "").lower())
            self.assertEqual(
                resp.prose_summary,
                "Your training has climbed fast lately, so let's ease off and rest up "
                "for a few days. Keep today easy and call it a win. Future you says thanks.",
            )

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
            any(
                w in low
                for w in (
                    "hold",
                    "progress",
                    "block",
                    "session",
                    "minute",
                    "variable",
                    "back off",
                    "easy",
                )
            ),
            resp.recommendation,
        )

    def test_deterministic_path_strips_repair_in_the_bank_guide(self):
        ctx, _ = _ctx()
        row = dummy.respond("Should I train today?", seed=1, engine="lambda", context=ctx)
        blob = f"{row.get('prose_summary') or ''} {row.get('message') or ''}"
        self.assertNotIn("they have repair in the bank", blob.lower())

    def test_sleep_question_under_high_load_never_uses_training_template(self):
        ctx, _ = _ctx()
        ctx.is_overtrained = True
        ctx.acwr = 1.7
        ctx.today.acwr = 1.7
        ctx.sleep_debt_7d_hours = 0
        row = dummy.respond(
            "How was my sleep last night?",
            seed=1,
            engine="lambda",
            context=ctx,
        )
        spoken = f"{row.get('prose_summary') or ''} {row.get('message') or ''}"
        self.assertNotIn("your training has climbed fast lately", spoken.lower())
        # sleep_debt_7d_hours = 0: never claim a shortfall the data doesn't show.
        self.assertNotIn("you've been running short on sleep", spoken.lower())
        self.assertIn("sleep is the thing to guard tonight", spoken.lower())
        rec = str(row.get("recommendation") or "")
        card = row.get("card") if isinstance(row.get("card"), dict) else {}
        action = str(card.get("action") or rec)
        self.assertIn("zone 2", action.lower())
        self.assertEqual(action, "Back off the hard stuff — swap to an easy, chatty-pace zone 2.")
        banned = re.compile(r"(?i)\b(?:deload|overtrain|recovery)\b")
        for blob in (spoken, action, rec):
            self.assertNotRegex(blob, banned, blob)

    def test_sleep_question_at_overtrained_acwr_rec_backs_off(self):
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from aria_core.aria_evidence import ACWR_OVERREACH
        from aria_core.speak_guard import spoken_ban_hits

        ctx, _ = _ctx()
        ctx.is_overtrained = True
        ctx.acwr = ACWR_OVERREACH
        ctx.today.acwr = ACWR_OVERREACH
        ctx.sleep_debt_7d_hours = 0
        row = dummy.respond(
            "How was my sleep last night?",
            seed=1,
            engine="lambda",
            context=ctx,
        )
        rec = str(row.get("recommendation") or "")
        card = row.get("card") if isinstance(row.get("card"), dict) else {}
        action = str(card.get("action") or rec)
        expected = "Back off the hard stuff — swap to an easy, chatty-pace zone 2."
        self.assertEqual(action, expected)
        self.assertEqual(rec, expected)
        self.assertEqual(spoken_ban_hits(action), ())
        self.assertEqual(spoken_ban_hits(rec), ())

    def test_ordinary_train_day_keeps_zone2_card(self):
        ctx, _ = _ctx()
        ctx.is_overtrained = False
        ctx.acwr = 1.05
        ctx.today.acwr = 1.05
        ctx.sleep_debt_7d_hours = 0
        ctx.today.readiness_score = 42
        row = dummy.respond(
            "Should I train today?",
            seed=1,
            engine="lambda",
            context=ctx,
        )
        spoken = f"{row.get('prose_summary') or ''} {row.get('message') or ''}"
        self.assertNotIn("your training has climbed fast lately", spoken.lower())
        card = row.get("card") if isinstance(row.get("card"), dict) else {}
        blob = " ".join(
            [
                spoken,
                str(row.get("recommendation") or ""),
                str(card.get("action") or ""),
                " ".join(str(item) for item in (row.get("suggested_actions") or [])),
            ]
        ).lower()
        self.assertIn("zone 2", blob, blob)


class SpokenBanSweepTests(unittest.TestCase):
    """Every graded Dummy turn stays off the single speak-floor + Iris list."""

    def test_tier1_dummy_turns_stay_off_spoken_ban_list(self):
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from aria_core.speak_guard import spoken_ban_hits

        os.environ["SIMRUNNER_TODAY"] = "2026-01-15"
        engine = dummy.DummyARIAEngine()
        queries = get_queries_for_tier(1)
        days = (7, 14, 21, 29)
        hits: list[str] = []
        for model in reg.get_models_by_tier(1):
            stream = generate_stream(model["behavioral_profile"], seed=42)
            for day in days:
                ctx = build_context(stream, model["behavioral_profile"], day)
                for query in queries:
                    resp = engine.respond(query, ctx, seed=42)
                    for field, text in (
                        ("reply", resp.prose_summary),
                        ("rec", resp.recommendation),
                    ):
                        found = spoken_ban_hits(text or "")
                        if found:
                            hits.append(
                                f"{model['model_id']} day={day} {query!r} {field} "
                                f"{found!r}: {text!r}"
                            )
        self.assertEqual(hits, [], "\n".join(hits))


if __name__ == "__main__":
    unittest.main()
