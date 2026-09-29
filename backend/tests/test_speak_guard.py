"""Shared speak guard: guide/label/memory leaks, same-day hours, confidence.

Bedrock stays mocked — no real AWS calls.
"""

from __future__ import annotations

import json
import os
import re
import types
import unittest
from unittest.mock import patch

import _bootstrap  # noqa: F401

from aria_core import aria_engine, speak_guard  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ARIAContext,
    ProgressContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)


GUIDE = "They have repair in the bank. Spend it on one quality session in the slot they actually use."
LABEL = "Usable picture is still thin"
MEMORY_NOTE = "You always skip Friday night sessions when work runs late"


def _ctx(**overrides) -> ARIAContext:
    ctx = ARIAContext(
        sleep=SleepContext(
            duration_minutes=440, rem_minutes=95, deep_minutes=70, hrv=58, nights_available=14
        ),
        readiness=ReadinessContext(
            hrv_7day_trend=-4, hrv_30day_baseline=62, recovery_score=72, hrv_days_available=7
        ),
        training=TrainingContext(
            last_workout_type="strength", hours_since_last_workout=14, weekly_load_score=60
        ),
        progress=ProgressContext(
            workouts_completed_30d=18, new_personal_records=2, training_load_trend="rising"
        ),
    )
    for key, value in overrides.items():
        setattr(ctx, key, value)
    return ctx


class DenySetFromSourceTests(unittest.TestCase):
    def test_deny_set_includes_context_plan_guide_strings(self):
        phrases = speak_guard._deny_phrases()
        self.assertTrue(any("repair in the bank" in p.lower() for p in phrases), phrases)
        self.assertTrue(any("usable picture is still thin" in p.lower() for p in phrases), phrases)
        # Built from the source functions, not a single hardcoded line.
        self.assertGreater(len(phrases), 4)


class GuardSpeakTests(unittest.TestCase):
    def test_strips_repair_in_the_bank_and_keeps_a_step(self):
        out = speak_guard.guard_speak(f"You're ready. {GUIDE}")
        self.assertNotIn("they have repair in the bank", out.lower())
        self.assertTrue(out.strip())
        self.assertTrue(
            any(c in out.lower() for c in ("minute", "session", "easy", "hold", "progress")),
            out,
        )

    def test_prefers_card_action_when_guide_is_stripped(self):
        out = speak_guard.guard_speak(
            GUIDE,
            card={"action": "Hold the structure and progress one variable next block"},
        )
        self.assertNotIn("repair in the bank", out.lower())
        self.assertIn("progress one variable", out.lower())

    def test_strips_internal_label(self):
        out = speak_guard.guard_speak(f"{LABEL}. Keep today easy.")
        self.assertNotIn("usable picture is still thin", out.lower())
        self.assertIn("easy", out.lower())

    def test_strips_memory_header_and_verbatim_note(self):
        raw = f"Recent patterns: {MEMORY_NOTE}. Hold the structure and progress one variable next block."
        out = speak_guard.guard_speak(raw, memory_notes=[MEMORY_NOTE])
        self.assertNotIn("recent patterns:", out.lower())
        self.assertNotIn(MEMORY_NOTE.lower(), out.lower())
        self.assertIn("progress", out.lower())

    def test_dedupes_repeated_fragments(self):
        out = speak_guard.guard_speak(
            "Keep today easy. Keep today easy. 20 easy minutes, then call it. 20 easy minutes, then call it."
        )
        self.assertEqual(out.lower().count("keep today easy"), 1)
        self.assertEqual(out.lower().count("20 easy minutes, then call it"), 1)

    def test_rewrites_zero_hours_since(self):
        out = speak_guard.guard_speak("Only 0 h since strength — keep today easy.")
        self.assertNotIn("0 h since", out.lower())
        self.assertIn("earlier today", out.lower())

    def test_leaves_zone_2_and_sleep_hours_alone(self):
        text = "Sleep looked like about 7 hours. Keep it Zone 2, twenty minutes."
        self.assertEqual(speak_guard.guard_speak(text), text)

    def test_zero_hours_keeps_words_after_single_label(self):
        out = speak_guard.guard_speak("0 h since strength so keep it easy.")
        self.assertNotIn("0 h since", out.lower())
        self.assertIn("strength earlier today", out.lower())
        self.assertIn("so keep it easy", out.lower())

    def test_join_inserts_period_before_appended_step(self):
        out = speak_guard.guard_speak(
            f"You're ready today {GUIDE}",
            card={"action": "Keep it shorter and lighter — 20 easy minutes, then call it"},
        )
        self.assertNotIn("today Keep it", out)
        self.assertRegex(out, r"today\.\s+Keep it")
        self.assertTrue(out.rstrip().endswith("."))

    def test_training_fallback_not_used_for_sleep_or_food(self):
        train = speak_guard.guard_speak(GUIDE, topic="training")
        self.assertIn("20 easy minutes", train.lower())
        self.assertIn("then call it", train.lower())
        sleep = speak_guard.guard_speak(GUIDE, topic="sleep")
        self.assertNotIn("20 easy minutes", sleep.lower())
        food = speak_guard.guard_speak(GUIDE, topic="food")
        self.assertNotIn("20 easy minutes", food.lower())

    def test_clarify_fallback_asks_how_you_slept(self):
        out = speak_guard.guard_speak(GUIDE, stance="clarify")
        self.assertIn("tell me how you slept and i'll size today", out.lower())
        self.assertNotIn("give me one missing signal", out.lower())

    def test_short_note_callback_survives(self):
        out = speak_guard.guard_speak(
            "Since you like morning runs, keep today easy.",
            memory_notes=["prefers morning runs"],
        )
        self.assertIn("since you like morning runs", out.lower())
        self.assertIn("keep today easy", out.lower())

    def test_long_note_readback_drops_whole_sentence(self):
        raw = (
            f"I remember {MEMORY_NOTE}, so we'll go gentle. "
            "Hold the structure and progress one variable next block."
        )
        out = speak_guard.guard_speak(raw, memory_notes=[MEMORY_NOTE])
        self.assertNotIn(MEMORY_NOTE.lower(), out.lower())
        self.assertNotIn("i remember", out.lower())
        self.assertNotIn("so we'll go gentle", out.lower())
        self.assertIn("progress", out.lower())

    def test_inline_goals_colon_is_not_stripped(self):
        text = "Two goals: sleep and steps"
        self.assertEqual(speak_guard.guard_speak(text), text)

    def test_header_on_same_line_as_note_is_still_caught(self):
        block = f"Recent patterns: {MEMORY_NOTE}"
        raw = f"{MEMORY_NOTE}. Hold the structure and progress one variable next block."
        out = speak_guard.guard_speak(raw, memory_block=block)
        self.assertNotIn(MEMORY_NOTE.lower(), out.lower())
        self.assertIn("progress", out.lower())


class DeterministicPathTests(unittest.TestCase):
    def test_generate_response_strips_repair_in_the_bank(self):
        resp = aria_engine.generate_response("Should I train today?", _ctx())
        blob = f"{resp.get('prose_summary') or ''} {resp.get('message') or ''}"
        self.assertNotIn("they have repair in the bank", blob.lower())

    def test_same_day_zero_hours_never_appears(self):
        ctx = _ctx(training=TrainingContext(last_workout_type="strength", hours_since_last_workout=0.0))
        resp = aria_engine.generate_response("Should I train today?", ctx)
        blob = speak_guard.user_visible(resp).lower()
        self.assertNotIn("0 h since", blob)
        self.assertNotIn("only 0 h since strength", blob)

    def test_progress_question_maps_sized_step_into_recommendation(self):
        resp = aria_engine.generate_response("Am I making progress?", _ctx())
        self.assertEqual(resp["response_type"], "summary")
        rec = resp.get("recommendation") or (resp.get("card") or {}).get("action")
        self.assertIsNotNone(rec)
        self.assertTrue(str(rec).strip())
        self.assertTrue(
            any(w in str(rec).lower() for w in ("hold", "progress", "block", "variable", "session")),
            rec,
        )

    def test_contradiction_caps_confidence_below_point_nine(self):
        ctx = _ctx(
            training=TrainingContext(last_workout_type="strength", hours_since_last_workout=3.0)
        )
        # Direct helper — generate_response rarely emits both sides at once.
        capped = speak_guard.cap_contradiction_confidence(
            "Recovery window is still open. Train hard today and push for a PR.",
            0.94,
            hours_since=3.0,
        )
        self.assertLess(capped, 0.9)
        envelope = {
            "prose_summary": "Recovery window is still open. Go hard — high-intensity session.",
            "confidence": 0.93,
            "card": {"action": "Train hard today"},
        }
        guarded = speak_guard.guard_envelope(envelope)
        self.assertLess(guarded["confidence"], 0.9)

    def test_lambda_path_rescrubs_vitals_from_added_step(self):
        dirty = "Keep it easy at 72 bpm with deep sleep at 21%"
        envelope = {
            "prose_summary": GUIDE,
            "message": GUIDE,
            "confidence": 0.8,
            "card": {"action": dirty},
            "fusion": {"stance": "protect"},
        }
        out = aria_engine._finish_spoken_envelope(envelope, _ctx(), "Should I train today?")
        speech = f"{out.get('prose_summary') or ''} {out.get('message') or ''}"
        self.assertNotIn("bpm", speech.lower())
        self.assertNotIn("21%", speech)
        self.assertNotRegex(speech.lower(), r"deep sleep at")

    def test_lambda_path_strips_notes_from_memory_block(self):
        self.assertGreaterEqual(len(MEMORY_NOTE.split()), 5)
        ctx = _ctx()
        ctx.last_insights = [MEMORY_NOTE]
        # Note lives on the prompt block, not memory_notes (recent_patterns only).
        self.assertNotIn(MEMORY_NOTE, aria_engine._memory_notes_from_ctx(ctx))
        block = aria_engine._memory_block_from_ctx(ctx)
        self.assertIn(MEMORY_NOTE, block)
        envelope = {
            "prose_summary": (
                f"Right — {MEMORY_NOTE}. Hold the structure and progress one variable next block."
            ),
            "message": f"Right — {MEMORY_NOTE}. Hold the structure.",
            "confidence": 0.7,
            "card": {"action": "Hold the structure and progress one variable next block"},
            "fusion": {"stance": "protect"},
        }
        out = aria_engine._finish_spoken_envelope(envelope, ctx, "Should I train today?")
        speech = f"{out.get('prose_summary') or ''} {out.get('message') or ''}"
        self.assertNotIn(MEMORY_NOTE.lower(), speech.lower())
        self.assertNotIn("right —", speech.lower())
        self.assertIn("progress", speech.lower())


class LiveBedrockGuardTests(unittest.TestCase):
    def setUp(self):
        self._flag = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        self._gateway = aria_engine._gateway
        aria_engine._gateway = None

    def tearDown(self):
        aria_engine._gateway = self._gateway
        if self._flag is None:
            os.environ.pop("ARIA_BEDROCK_ENABLED", None)
        else:
            os.environ["ARIA_BEDROCK_ENABLED"] = self._flag

    def test_bedrock_path_guards_guide_text_without_real_boto(self):
        leaked = (
            "You're cleared. They have repair in the bank. "
            "Spend it on one quality session in the slot they actually use."
        )
        payload = json.dumps(
            {
                "prose_summary": leaked,
                "response_type": "recommendation",
                "confidence": 0.8,
            }
        )
        boto_hits: list[tuple] = []

        class FakeGateway:
            def __init__(self, *args, **kwargs):
                self.calls = []

            def converse(self, **kwargs):
                self.calls.append(kwargs)
                return {"answer": payload}

        fake = FakeGateway()
        fake_boto = types.ModuleType("boto3")

        def _no_client(*args, **kwargs):
            boto_hits.append((args, kwargs))
            raise AssertionError("no real boto/Bedrock client")

        fake_boto.client = _no_client

        with patch.dict("sys.modules", {"boto3": fake_boto}):
            with patch.object(aria_engine, "_gateway", fake):
                with patch("ai_router.BedrockGateway", side_effect=lambda *a, **k: fake):
                    resp = aria_engine.generate_response_live(
                        "Should I train today?",
                        _ctx(),
                    )

        self.assertEqual(resp.get("reasoning_source"), "bedrock")
        blob = speak_guard.user_visible(resp)
        self.assertNotIn("they have repair in the bank", blob.lower())
        self.assertTrue(blob.strip())
        self.assertEqual(boto_hits, [])
        self.assertEqual(len(fake.calls), 1)


class LivePathGuardTests(unittest.TestCase):
    """Live path with an injected converse — ARIA_BEDROCK_ENABLED stays off."""

    def test_bedrock_flag_stays_off(self):
        self.assertNotIn(os.environ.get("ARIA_BEDROCK_ENABLED", "").lower(), {"1", "true", "yes"})

    def test_live_path_rescrubs_vitals_from_added_step(self):
        dirty = "Keep it easy at 72 bpm with deep sleep at 21%"
        base = aria_engine.generate_response("Should I train today?", _ctx())
        card = dict(base.get("card") or {})
        card["action"] = dirty
        base = dict(base)
        base["card"] = card

        def converse(_model_id, _system, _user):
            return json.dumps(
                {
                    "prose_summary": GUIDE,
                    "response_type": "recommendation",
                    "confidence": 0.8,
                }
            )

        with patch.object(aria_engine, "generate_response", return_value=base):
            resp = aria_engine.generate_response_live(
                "Should I train today?",
                _ctx(),
                converse=converse,
            )
        speech = f"{resp.get('prose_summary') or ''} {resp.get('message') or ''}"
        self.assertEqual(resp.get("reasoning_source"), "bedrock")
        self.assertNotIn("bpm", speech.lower())
        self.assertNotIn("21%", speech)
        self.assertNotRegex(speech.lower(), r"deep sleep at")
        self.assertNotIn(os.environ.get("ARIA_BEDROCK_ENABLED", "").lower(), {"1", "true", "yes"})

    def test_live_path_strips_notes_from_memory_block(self):
        self.assertGreaterEqual(len(MEMORY_NOTE.split()), 5)
        ctx = _ctx()
        ctx.last_insights = [MEMORY_NOTE]
        self.assertNotIn(MEMORY_NOTE, aria_engine._memory_notes_from_ctx(ctx))
        self.assertIn(MEMORY_NOTE, aria_engine._memory_block_from_ctx(ctx))

        def converse(_model_id, _system, _user):
            return json.dumps(
                {
                    "prose_summary": (
                        f"Right — {MEMORY_NOTE}. Hold the structure and progress one variable next block."
                    ),
                    "response_type": "recommendation",
                    "confidence": 0.8,
                }
            )

        resp = aria_engine.generate_response_live(
            "Should I train today?",
            ctx,
            converse=converse,
        )
        speech = f"{resp.get('prose_summary') or ''} {resp.get('message') or ''}"
        self.assertEqual(resp.get("reasoning_source"), "bedrock")
        self.assertNotIn(MEMORY_NOTE.lower(), speech.lower())
        self.assertNotIn("right —", speech.lower())
        self.assertIn("progress", speech.lower())
        self.assertNotIn(os.environ.get("ARIA_BEDROCK_ENABLED", "").lower(), {"1", "true", "yes"})


class BareLabelLeakTests(unittest.TestCase):
    def test_join_with_step_does_not_emit_bare_why(self):
        spoken = speak_guard._join_with_step(
            "a personal short night. Why",
            "Sync HealthKit",
        )
        self.assertNotRegex(spoken, r"(?i)\bWhy\.")
        self.assertRegex(spoken, r"(?i)sync healthkit")
        guarded = speak_guard.guard_speak("personal short night. Why. Timing.")
        self.assertNotRegex(guarded, r"(?i)\bWhy\.")
        self.assertNotRegex(guarded, r"(?i)\bTiming\.")


class ButtonSentenceTests(unittest.TestCase):
    def test_show_deload_week_is_a_button_show_up_is_not(self):
        self.assertTrue(speak_guard.is_button_sentence("Show deload week."))
        self.assertTrue(speak_guard.spoken_has_button("Show deload week."))
        self.assertFalse(
            speak_guard.is_button_sentence(
                "Show up for ten easy minutes and call it a win."
            )
        )
        self.assertFalse(
            speak_guard.spoken_has_button(
                "Show up for ten easy minutes and call it a win."
            )
        )
        card = {"action": "Show deload week."}
        self.assertTrue(
            speak_guard.is_button_sentence("Show deload week.", card)
        )
        self.assertFalse(
            speak_guard.is_button_sentence(
                "Show up for ten easy minutes and call it a win.", card
            )
        )

    def test_any_spoken_sentence_matching_card_action_is_a_button(self):
        card = {"action": "Keep today easy."}
        self.assertTrue(speak_guard.is_button_sentence("Keep today easy.", card))
        self.assertTrue(speak_guard.is_button_sentence("keep today easy", card))
        self.assertTrue(speak_guard.spoken_has_button("Keep today easy.", card))
        self.assertFalse(
            speak_guard.is_button_sentence(
                "Keep today easy and call it a win.", card
            )
        )
        self.assertFalse(
            speak_guard.spoken_has_button(
                "Keep today easy and call it a win.", card
            )
        )
        overtrain = {"action": aria_engine.BUTTON_OVERTRAIN}
        self.assertTrue(
            speak_guard.is_button_sentence(aria_engine.BUTTON_OVERTRAIN, overtrain)
        )
        self.assertFalse(
            speak_guard.is_button_sentence(aria_engine.SPOKEN_PROTECT_STEP, overtrain)
        )


class BlockingPatternSpeakTests(unittest.TestCase):
    _BANNED = re.compile(
        r"(?i)\b(?:overtrain\w*|overreach\w*|fatigue|deload|acwr|debt)\b"
    )
    _STUCK_UNIT = re.compile(r"\d+(?:\.\d+)?[A-Za-z]")

    def _assert_clean_spoken(self, resp, line: str) -> None:
        spoken_m = resp.get("message") or ""
        spoken_p = resp.get("prose_summary") or ""
        self.assertIn(line, spoken_m)
        self.assertIn(line, spoken_p)
        for blob in (spoken_m, spoken_p):
            self.assertFalse(re.search(r"\d", blob), blob)
            self.assertNotRegex(blob, self._STUCK_UNIT)
            self.assertNotRegex(blob, self._BANNED)
            self.assertFalse(speak_guard.spoken_has_button(blob, resp.get("card")))
            if line == aria_engine.SPOKEN_SHORT_SLEEP:
                self.assertLessEqual(len(re.findall(r"(?i)\bsleep\b", blob)), 1, blob)
            why = "You've had a run of short nights, so sleep comes first."
            self.assertNotIn(why, blob)

    def test_blocking_pattern_speaks_clean_line_never_risk_memory(self):
        from routes.aria import _insight_takeaway
        from services.aria_context import CoachContextEngine
        from services.aria_engine import (
            ARIAContext,
            ReadinessContext,
            SleepContext,
            TrainingContext,
        )
        from storage import dynamodb

        both = ARIAContext(
            sleep=SleepContext(
                duration_minutes=360,
                nights_available=10,
                sleep_debt_7d_hours=6.5,
            ),
            readiness=ReadinessContext(
                hrv_7day_trend=-14,
                hrv_30day_baseline=60,
                recovery_score=42,
                hrv_days_available=7,
            ),
            training=TrainingContext(
                weekly_load_score=88,
                acwr=1.62,
                is_overtrained=True,
                hours_since_last_workout=10,
            ),
        )
        resp = aria_engine.generate_response(
            "should I train hard today?", both, voice_mode=True
        )
        # Protect's spoken line wins when overreaching and sleep-protect both fire.
        self.assertEqual(resp["message"], resp["prose_summary"])
        self._assert_clean_spoken(resp, aria_engine.SPOKEN_SHORT_SLEEP)
        self.assertNotIn(aria_engine.SPOKEN_OVERTRAIN, resp["prose_summary"])
        notice = (resp.get("evidence") or {}).get("notice") or ""
        self.assertTrue(
            re.search(r"(?i)overtrain|workload is running hot", notice), notice
        )

        only_load = ARIAContext(
            sleep=SleepContext(duration_minutes=480, nights_available=10, sleep_debt_7d_hours=0),
            readiness=ReadinessContext(
                hrv_7day_trend=2, recovery_score=72, hrv_days_available=7
            ),
            training=TrainingContext(
                weekly_load_score=95,
                acwr=1.7,
                is_overtrained=True,
                hours_since_last_workout=36,
            ),
        )
        hot = aria_engine.generate_response(
            "should I train hard today?", only_load, voice_mode=True
        )
        self.assertEqual(hot["message"], hot["prose_summary"])
        self._assert_clean_spoken(hot, aria_engine.SPOKEN_OVERTRAIN)

        hot_text = aria_engine.generate_response(
            "should I train hard today?", only_load, voice_mode=False
        )
        sleep_text = aria_engine.generate_response(
            "should I train hard today?", both, voice_mode=False
        )
        self._assert_clean_spoken(sleep_text, aria_engine.SPOKEN_SHORT_SLEEP)
        self._assert_clean_spoken(hot_text, aria_engine.SPOKEN_OVERTRAIN)
        sleep_card = sleep_text.get("card") or {}
        hot_card = hot_text.get("card") or {}
        self.assertEqual(sleep_card.get("action"), aria_engine.BUTTON_SHORT_SLEEP)
        self.assertEqual(hot_card.get("action"), aria_engine.BUTTON_OVERTRAIN)
        for text_resp in (sleep_text, hot_text):
            action = ((text_resp.get("card") or {}).get("action") or "").strip()
            spoken = f"{text_resp.get('message') or ''} {text_resp.get('prose_summary') or ''}"
            for part in re.split(r"(?<=[.!?])\s+", spoken):
                sentence = part.strip()
                if not sentence or not action:
                    continue
                self.assertNotEqual(
                    speak_guard._norm(sentence),
                    speak_guard._norm(action),
                    (sentence, action),
                )
            self.assertFalse(
                speak_guard.spoken_has_button(spoken, text_resp.get("card"))
            )

        dynamodb.clear_local_store()
        uid = f"block-speak-{id(self)}"
        takeaway = _insight_takeaway(resp["prose_summary"])
        engine = CoachContextEngine()
        if takeaway:
            engine.add_insight(uid, takeaway[:180])
        insights = engine.get_or_create_context(uid).last_insights
        risk = (resp.get("evidence") or {}).get("notice") or ""
        for item in insights:
            self.assertNotRegex(item, self._BANNED, insights)
            self.assertNotRegex(item, r"(?i)\bdebt\b", insights)
            self.assertNotRegex(item, self._STUCK_UNIT, insights)
            if risk:
                self.assertNotIn(risk, item)
        clean = aria_engine.SPOKEN_SHORT_SLEEP.rstrip(".")
        self.assertTrue(
            not insights
            or all(item.strip().rstrip(".") == clean for item in insights),
            insights,
        )
        takeaway_hot = _insight_takeaway(hot["prose_summary"])
        if takeaway_hot:
            engine.add_insight(uid + "-hot", takeaway_hot[:180])
        hot_insights = engine.get_or_create_context(uid + "-hot").last_insights
        for item in hot_insights:
            self.assertNotRegex(item, self._BANNED, hot_insights)
            self.assertNotRegex(item, r"(?i)\bdebt\b", hot_insights)
            self.assertNotRegex(item, self._STUCK_UNIT, hot_insights)
        hot_clean = aria_engine.SPOKEN_OVERTRAIN.rstrip(".")
        self.assertTrue(
            not hot_insights
            or all(item.strip().rstrip(".") == hot_clean for item in hot_insights),
            hot_insights,
        )


if __name__ == "__main__":
    unittest.main()
