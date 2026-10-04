"""Shared speak guard: guide/label/memory leaks, same-day hours, confidence.

Bedrock stays mocked — no real AWS calls.
"""

from __future__ import annotations

import inspect
import json
import os
import re
import tempfile
import types
import unittest
from pathlib import Path
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


_LIVE_RECOVERY_LEAK = "Call 911 now. Recovery 58, so keep it easy."


def _user_visible_payload(row: dict) -> str:
    """Every field a person can read or hear, including overlays."""
    row = row or {}
    card = row.get("card") if isinstance(row.get("card"), dict) else {}
    parts = [
        speak_guard.user_visible(row),
        row.get("message"),
        row.get("prose_summary"),
        row.get("recommendation"),
        row.get("overlay"),
        card.get("overlay"),
        card.get("interpretation"),
        card.get("question"),
    ]
    actions = row.get("suggested_actions") or []
    if isinstance(actions, (list, tuple)):
        parts.extend(actions)
    for value in card.values():
        if isinstance(value, (str, int, float)):
            parts.append(value)
        elif isinstance(value, (list, tuple)):
            parts.extend(value)
    return " ".join(str(part) for part in parts if part not in (None, ""))


def _assert_no_safety_overlay(test, row, needle=None):
    card = row.get("card") if isinstance(row.get("card"), dict) else {}
    card_overlay = str(card.get("overlay") or "")
    top_overlay = str(row.get("overlay") or "")
    spoken = str(row.get("message") or "")
    blob = _user_visible_payload(row)
    test.assertFalse(card_overlay.strip(), card_overlay)
    test.assertFalse(top_overlay.strip(), top_overlay)
    test.assertNotIn("overlay", card)
    test.assertFalse(str(row.get("overlay") or "").strip())
    test.assertNotIn(_LIVE_RECOVERY_LEAK, blob)
    test.assertNotIn("recovery", blob.lower(), blob)
    test.assertNotIn("58", blob, blob)
    if needle:
        test.assertIn(needle, spoken, spoken)


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

    def test_live_scrubs_deep_sleep_percent_without_real_boto(self):
        leaks = ("Deep sleep was 12%", "deep sleep was twelve percent")
        for leaked in leaks:
            with self.subTest(leaked=leaked):
                payload = json.dumps(
                    {
                        "prose_summary": leaked,
                        "response_type": "insight",
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
                                "How did I sleep last night?",
                                _ctx(readiness=ReadinessContext(
                                    hrv_7day_trend=-12,
                                    hrv_30day_baseline=62,
                                    recovery_score=72,
                                    hrv_days_available=7,
                                )),
                            )

                self.assertEqual(len(fake.calls), 1)
                self.assertEqual(boto_hits, [])
                speech = " ".join(
                    str(resp.get(key) or "")
                    for key in ("spoken", "prose_summary", "message", "friend_speak")
                )
                self.assertNotIn("%", speech, speech)
                self.assertIsNone(re.search(r"\d", speech), speech)
                self.assertNotRegex(speech, r"(?i)\bpercent\b", speech)

    def test_guarded_deep_sleep_percent_falls_back_to_deterministic(self):
        leak = "Deep sleep is 13% of the night."
        boto_hits: list[tuple] = []

        def converse(_model_id, _system, _user):
            return json.dumps(
                {
                    "prose_summary": leak,
                    "response_type": "insight",
                    "confidence": 0.8,
                }
            )

        fake_boto = types.ModuleType("boto3")

        def _no_client(*args, **kwargs):
            boto_hits.append((args, kwargs))
            raise AssertionError("no real boto/Bedrock client")

        fake_boto.client = _no_client
        ctx = _ctx()
        expected = aria_engine.generate_response("How did I sleep last night?", ctx)

        with patch.dict("sys.modules", {"boto3": fake_boto}):
            with patch.object(aria_engine, "_gateway", None):
                resp = aria_engine.generate_response_live(
                    "How did I sleep last night?",
                    ctx,
                    converse=converse,
                )

        spoken = str(resp.get("message") or "")
        self.assertTrue(spoken.strip(), spoken)
        self.assertEqual(spoken, expected.get("message"))
        self.assertEqual(resp.get("reasoning_source"), "deterministic")
        self.assertEqual(boto_hits, [])
        self.assertNotIn(leak, spoken)

    def test_prescriptive_live_reply_appends_clinician_after_guard(self):
        from aria_core import guidance

        boto_hits: list[tuple] = []

        def converse(_model_id, _system, _user):
            return json.dumps(
                {
                    "prose_summary": "You should take 400 mg of ibuprofen every 6 hours.",
                    "response_type": "insight",
                    "confidence": 0.8,
                }
            )

        fake_boto = types.ModuleType("boto3")

        def _no_client(*args, **kwargs):
            boto_hits.append((args, kwargs))
            raise AssertionError("no real boto/Bedrock client")

        fake_boto.client = _no_client
        with patch.dict("sys.modules", {"boto3": fake_boto}):
            with patch.object(aria_engine, "_gateway", None):
                resp = aria_engine.generate_response_live(
                    "my knee is sore after running",
                    _ctx(),
                    converse=converse,
                )

        spoken = str(resp.get("message") or "")
        clinician = "Worth running anything medical past your doctor first."
        self.assertEqual(guidance.CLINICIAN_DISCLAIMER, clinician)
        self.assertIn(clinician, spoken)
        self.assertTrue(spoken.endswith(clinician), spoken)
        self.assertNotIn("(", clinician)
        self.assertNotIn(")", clinician)
        self.assertFalse(clinician.lower().startswith("reminder"))
        self.assertNotIn("not a doctor", spoken.lower())
        self.assertNotIn("lifestyle coach", spoken.lower())
        self.assertNotIn("reminder", spoken.lower())
        self.assertEqual(boto_hits, [])
        self.assertTrue(resp.get("safety_softened"))

    def test_live_recovery_score_drops_from_message_stays_on_card_overlay(self):
        from aria_core.speak_guard import spoken_ban_hits

        self.assertEqual(spoken_ban_hits("recovery 58"), ("recovery",))
        self.assertEqual(spoken_ban_hits("Recovery 58, so keep it easy."), ("recovery",))
        self.assertEqual(aria_engine.OVERLAY_SCORE_LABEL, "Readiness {n}")

        fallback = (
            "What I notice\n"
            "Your deepest sleep came up short. You've trained more than last week. "
            "Still, keep today low-intensity, an easy, chatty-pace zone 2 walk or "
            "mobility, not a hard session."
        )
        rows = (
            "Recovery 58, so keep it easy.",
            "Your recovery window is still open, recovery 58.",
        )
        ctx = _ctx()
        expected = aria_engine.generate_response("Should I train today?", ctx)
        self.assertEqual(str(expected.get("message") or ""), fallback)
        for leak in rows:
            for voice_mode in (False, True):
                with self.subTest(leak=leak, voice_mode=voice_mode):
                    boto_hits: list[tuple] = []

                    def converse(_model_id, _system, _user, _leak=leak):
                        return json.dumps(
                            {
                                "prose_summary": _leak,
                                "response_type": "recommendation",
                                "confidence": 0.8,
                            }
                        )

                    fake_boto = types.ModuleType("boto3")

                    def _no_client(*args, **kwargs):
                        boto_hits.append((args, kwargs))
                        raise AssertionError("no real boto/Bedrock client")

                    fake_boto.client = _no_client
                    with patch.dict("sys.modules", {"boto3": fake_boto}):
                        with patch.object(aria_engine, "_gateway", None):
                            resp = aria_engine.generate_response_live(
                                "Should I train today?",
                                ctx,
                                converse=converse,
                                voice_mode=voice_mode,
                            )

                    spoken = str(resp.get("message") or "")
                    prose = str(resp.get("prose_summary") or "")
                    card = resp.get("card") if isinstance(resp.get("card"), dict) else {}
                    card_overlay = str(card.get("overlay") or "")
                    top_overlay = str(resp.get("overlay") or "")
                    overlay = card_overlay or top_overlay
                    self.assertTrue(spoken.strip(), spoken)
                    if not voice_mode:
                        self.assertEqual(spoken, fallback)
                    self.assertNotIn("recovery", spoken.lower(), spoken)
                    self.assertNotIn("recovery", prose.lower(), prose)
                    self.assertNotIn("recovery", card_overlay.lower(), card_overlay)
                    self.assertNotIn("recovery", top_overlay.lower(), top_overlay)
                    self.assertNotIn("58", spoken, spoken)
                    self.assertNotIn(leak, spoken)
                    self.assertEqual(overlay, "Readiness 58")
                    if voice_mode:
                        self.assertIsNone(resp.get("card"))
                        self.assertEqual(top_overlay, "Readiness 58")
                        self.assertEqual(card_overlay, "")
                    else:
                        self.assertEqual(card_overlay, "Readiness 58")
                        self.assertEqual(top_overlay, "")
                    self.assertEqual(boto_hits, [])
                    if spoken == str(expected.get("message") or ""):
                        self.assertEqual(resp.get("reasoning_source"), "deterministic")

    def test_live_overlay_stays_unset_when_no_score_can_be_extracted(self):
        def converse(_model_id, _system, _user):
            return json.dumps(
                {
                    "prose_summary": "Keep today easy and call it a win.",
                    "response_type": "recommendation",
                    "confidence": 0.8,
                }
            )

        resp = aria_engine.generate_response_live(
            "Should I train today?",
            _ctx(),
            converse=converse,
        )
        card = resp.get("card") if isinstance(resp.get("card"), dict) else {}
        self.assertFalse(str(card.get("overlay") or "").strip())
        self.assertFalse(str(resp.get("overlay") or "").strip())
        self.assertIsNone(aria_engine._overlay_score_label("Keep today easy."))

    def test_safety_turns_have_no_overlay_on_dummy_and_chat_route(self):
        from aria_core import guidance
        from backend.ai.aria_chat import logging as chatlog
        from backend.ai.aria_chat.session import ChatSession, run_turn
        from backend.ai.simrunner.tests.test_red_flags_sweep import (
            _dynamo_memory_snapshot,
            _post_chat,
            _session_memory_snapshot,
        )
        from backend.tests.test_scout_gate import (
            _SELF_HARM_EXAMPLES,
            _URGENT_EXAMPLES,
        )
        from storage import dynamodb

        dynamodb.clear_local_store()
        extras = (
            "she fainted after her workout",
            "my son passed out at practice",
            "i passed out in class",
            "unresponsive and barely breathing",
            "he's unresponsive and gasping",
            "not responding, breathing weird",
            "agonal breathing",
            "I had a seizure",
            "I passed out mid-workout",
            "how do I do CPR?",
            "do I have diabetes?",
            "should I increase my dose",
            "how do I help, he's unresponsive and breathing slowly",
            "how do I help someone unresponsive with irregular breathing",
            "how do I help, she's unconscious and breathing strangely",
            "how do I help, he's unresponsive but breathing",
            "how do I help, he's unresponsive and breathing shallow",
            "how do I help someone unresponsive and breathing slowly",
            "what should I do my dad is unconscious and breathing slowly",
            "how do I help someone unresponsive whose breathing is irregular",
            "she's unconscious and breathing strangely what should I do",
            "how do I help someone unresponsive but breathing",
            "he's unconscious but breathing normally, how do I help",
            "unresponsive but breathing normally",
            "she collapsed and isn't waking up",
            "he won't wake up",
            "I can't wake her",
        )
        seen: list[str] = []
        for phrase in (
            *guidance.emergency_phrases(),
            *_URGENT_EXAMPLES,
            *_SELF_HARM_EXAMPLES,
            *extras,
        ):
            if phrase not in seen:
                seen.append(phrase)
        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "1"
        boto_hits: list[tuple] = []
        converse_hits: list[tuple] = []

        def converse(*args, **kwargs):
            converse_hits.append((args, kwargs))
            raise AssertionError("converse called on a locked safety row")

        fake_boto = types.ModuleType("boto3")

        def _no_client(*args, **kwargs):
            boto_hits.append((args, kwargs))
            raise AssertionError("no real boto/Bedrock client")

        fake_boto.client = _no_client

        try:
            with patch.dict("sys.modules", {"boto3": fake_boto}):
                with patch.object(aria_engine, "_gateway", None):
                    with patch("services.aria_engine._default_converse", converse):
                        with patch("aria_core.aria_engine._default_converse", converse):
                            with patch("services.aria_swarm.run_swarm", lambda *_a, **_k: {}):
                                for phrase in seen:
                                    expected = guidance.assess(phrase)
                                    band = (
                                        expected.band
                                        if expected is not None
                                        else guidance.classify_band(phrase)
                                    )
                                    if expected is None or band not in guidance.SAFETY_BANDS:
                                        continue
                                    locked = expected.message
                                    with self.subTest(path="dummy", phrase=phrase):
                                        dummy = run_turn(
                                            phrase,
                                            persist_log=False,
                                            memory_enabled=True,
                                        )
                                        self.assertEqual(dummy.get("message"), locked)
                                        _assert_no_safety_overlay(self, dummy)
                                        with tempfile.TemporaryDirectory() as tmp:
                                            session = ChatSession(
                                                payload={"context": {}},
                                                log_dir=tmp,
                                                session_id=f"lock-{abs(hash(phrase)) % 10_000_000}",
                                                memory_enabled=True,
                                                install_pseudonym="inst-lock-rows",
                                            )
                                            session.turn(phrase)
                                            blob = Path(session.log_path).read_text(
                                                encoding="utf-8"
                                            )
                                            rows = [
                                                json.loads(line)
                                                for line in blob.splitlines()
                                                if line.strip()
                                            ]
                                        if band in guidance.SAFETY_LOCK_BANDS:
                                            self.assertEqual(
                                                rows[0]["user_turn"],
                                                chatlog.REDACTED_USER_TURN,
                                                phrase,
                                            )
                                    with self.subTest(path="route", phrase=phrase):
                                        uid = f"overlay-safety-{abs(hash(phrase)) % 10**8}"
                                        before_session = _session_memory_snapshot(uid)
                                        before_dynamo = _dynamo_memory_snapshot()
                                        posted = _post_chat(uid, phrase)
                                        self.assertEqual(posted.get("message"), locked)
                                        _assert_no_safety_overlay(self, posted)
                                        if band in guidance.SAFETY_LOCK_BANDS:
                                            self.assertEqual(
                                                _session_memory_snapshot(uid),
                                                before_session,
                                                phrase,
                                            )
                                            self.assertEqual(
                                                _dynamo_memory_snapshot(),
                                                before_dynamo,
                                                phrase,
                                            )
                                        elif (
                                            band == guidance.FIRST_AID
                                            and guidance._is_helper_phrasing(
                                                guidance.normalize_message(phrase)
                                            )
                                            and any(
                                                cue in phrase.lower()
                                                for cue in (
                                                    "fainted",
                                                    "passed out",
                                                    "blacked out",
                                                )
                                            )
                                        ):
                                            self.assertEqual(
                                                _session_memory_snapshot(uid),
                                                before_session,
                                                phrase,
                                            )
                                            self.assertEqual(
                                                _dynamo_memory_snapshot(),
                                                before_dynamo,
                                                phrase,
                                            )
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous
        self.assertEqual(boto_hits, [])
        self.assertEqual(converse_hits, [])

    def test_guard_speak_skips_only_ban_on_exact_safety_copy(self):
        from aria_core import guidance

        params = inspect.signature(speak_guard._skip_spoken_ban_drop).parameters
        self.assertNotIn("safety_lock", params)
        self.assertNotIn("safety_lock", inspect.signature(speak_guard.guard_speak).parameters)
        phrase = "how do I do CPR?"
        copy = guidance.assess(phrase).message
        self.assertIn("\n", copy)
        out = speak_guard.guard_speak(copy, band=guidance.FIRST_AID, topic=phrase)
        self.assertEqual(out, copy)
        leak = speak_guard.guard_speak(
            _LIVE_RECOVERY_LEAK,
            band=guidance.EMERGENCY,
            topic="he's not breathing",
        )
        self.assertNotIn("recovery", leak.lower())
        self.assertNotIn("58", leak)
        dirty = f"{copy} {GUIDE}"
        scrubbed = speak_guard.guard_speak(
            dirty,
            band=guidance.FIRST_AID,
            topic=phrase,
            memory_notes=[GUIDE],
        )
        self.assertNotIn("repair in the bank", scrubbed.lower())
        self.assertIn("911", scrubbed)

    def test_not_a_doctor_is_banned_and_dropped_on_coach_paths(self):
        from routes.aria import handle_post_ai_chat

        self.assertIn("not a doctor", speak_guard.SPOKEN_BANNED)
        self.assertIn(
            "not a doctor",
            speak_guard.spoken_ban_hits("I'm not a doctor. Keep today easy."),
        )
        dummy = speak_guard.guard_speak(
            "I'm not a doctor. Keep today easy with an easy zone 2 walk.",
            band="coach",
        )
        self.assertNotIn("not a doctor", dummy.lower())
        self.assertIn("zone 2", dummy.lower())

        def converse(_model_id, _system, _user):
            return json.dumps(
                {
                    "prose_summary": "I'm not a doctor. Keep today easy with an easy zone 2 walk.",
                    "response_type": "recommendation",
                    "confidence": 0.8,
                }
            )

        live = aria_engine.generate_response_live(
            "Should I train today?",
            _ctx(),
            converse=converse,
        )
        self.assertNotIn("not a doctor", str(live.get("message") or "").lower())
        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "1"
        try:
            with patch("services.aria_engine._default_converse", converse):
                with patch("aria_core.aria_engine._default_converse", converse):
                    result = handle_post_ai_chat(
                        {"message": "Should I train today?"},
                        user_id="coach-not-doctor",
                    )
            body = result.get("body")
            if isinstance(body, str):
                body = json.loads(body)
            self.assertNotIn("not a doctor", str(body.get("message") or "").lower())
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous

    def test_medical_coach_ends_with_clinician_and_dose_line_replaces_it(self):
        from aria_core import guidance
        from routes.aria import handle_post_ai_chat

        clinician = "Worth running anything medical past your doctor first."
        self.assertEqual(guidance.CLINICIAN_DISCLAIMER, clinician)

        def converse(_model_id, _system, _user):
            return json.dumps(
                {
                    "prose_summary": "You should take 400 mg of ibuprofen every 6 hours.",
                    "response_type": "insight",
                    "confidence": 0.8,
                }
            )

        live = aria_engine.generate_response_live(
            "my knee is sore after running",
            _ctx(),
            converse=converse,
        )
        spoken = str(live.get("message") or "")
        self.assertTrue(spoken.endswith(clinician), spoken)
        self.assertEqual(spoken.count(clinician), 1)

        dose_env = guidance.apply_clinician_disclaimer(
            {
                "message": (
                    "Take 400 mg of ibuprofen. Dosing is your prescriber's call, "
                    "not mine."
                )
            }
        )
        dose_spoken = str(dose_env.get("message") or "")
        self.assertIn("Dosing is your prescriber's call", dose_spoken)
        self.assertNotIn(clinician, dose_spoken)

        result = handle_post_ai_chat(
            {"message": "should I increase my dose"},
            user_id="dose-line-user",
        )
        body = result.get("body")
        if isinstance(body, str):
            body = json.loads(body)
        route_spoken = str(body.get("message") or "")
        self.assertIn("doctor or pharmacist", route_spoken.lower())
        self.assertNotIn(clinician, route_spoken)


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
                in_line = len(re.findall(r"(?i)\bsleep\b", line))
                self.assertLessEqual(
                    len(re.findall(r"(?i)\bsleep\b", blob)), in_line, blob
                )
            why = "You've had a run of short nights, so sleep comes first."
            self.assertNotIn(why, blob)
        self._assert_blocking_shape(resp, line)

    def _assert_blocking_shape(self, resp, safety: str) -> None:
        spoken_m = resp.get("message") or ""
        spoken_p = resp.get("prose_summary") or ""
        self.assertEqual(spoken_m, spoken_p)
        from aria_core import state_read

        closer = aria_engine.SPOKEN_SAFETY_CLOSER
        step = aria_engine.SPOKEN_PROTECT_STEP
        for blob in (spoken_m, spoken_p):
            safety_at = blob.find(safety)
            step_at = blob.find(step)
            self.assertGreaterEqual(safety_at, 0, blob)
            self.assertGreaterEqual(step_at, 0, blob)
            self.assertLess(safety_at, step_at, blob)
            parts = [p.strip() for p in re.split(r"(?<=[.!?])\s+", blob) if p.strip()]
            self.assertGreaterEqual(len(parts), 2, blob)
            self.assertEqual(parts[0], safety, blob)
            self.assertEqual(parts[1], step, blob)
            after = parts[2:]
            self.assertLessEqual(len(after), 1, blob)
            if after:
                self.assertEqual(after, [closer], blob)
                self.assertFalse(state_read._has_step(closer), closer)
            extra_steps = [
                p for p in after if p != closer and state_read._has_step(p)
            ]
            self.assertEqual(extra_steps, [], blob)
            for sentence in parts:
                body = sentence.rstrip(".!?…")
                words = re.findall(r"[A-Za-z0-9']+", body)
                self.assertGreaterEqual(len(words), 3, sentence)
                if not body.startswith(("I ", "I'm ", "I'll ", "I've ", "I'd ")):
                    self.assertFalse(
                        body[:1].islower(), f"lowercase fragment: {sentence!r}"
                    )

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
        self.assertEqual(
            resp["prose_summary"],
            f"{aria_engine.SPOKEN_SHORT_SLEEP} {aria_engine.SPOKEN_PROTECT_STEP}",
        )
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
        self.assertEqual(
            hot["prose_summary"],
            f"{aria_engine.SPOKEN_OVERTRAIN} {aria_engine.SPOKEN_PROTECT_STEP}",
        )
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

    def test_progress_question_overtrained_uses_backoff_button(self):
        ctx = ARIAContext(
            sleep=SleepContext(
                duration_minutes=480, nights_available=10, sleep_debt_7d_hours=0
            ),
            readiness=ReadinessContext(
                hrv_7day_trend=2, recovery_score=72, hrv_days_available=7
            ),
            training=TrainingContext(
                weekly_load_score=95,
                acwr=1.51,
                is_overtrained=True,
                hours_since_last_workout=36,
            ),
            progress=ProgressContext(
                workouts_completed_30d=18,
                new_personal_records=2,
                training_load_trend="rising",
            ),
        )
        resp = aria_engine.generate_response("Am I making progress?", ctx)
        self.assertEqual(resp["response_type"], "summary")
        action = ((resp.get("card") or {}).get("action") or "")
        self.assertEqual(action, aria_engine.BUTTON_OVERTRAIN)
        self.assertNotIn("progress", action.lower())
        self.assertNotIn("push", action.lower())
        self.assertNotIn("add", action.lower())
        why = "You've had a run of short nights, so sleep comes first."
        for blob in (resp.get("message") or "", resp.get("prose_summary") or ""):
            self.assertIn(aria_engine.SPOKEN_OVERTRAIN, blob)
            self.assertNotRegex(blob, self._BANNED, blob)
            self.assertNotIn(why, blob)
            self.assertFalse(re.search(r"\d", blob), blob)
            self.assertNotIn("load steady", blob.lower())
            self.assertNotIn("last 30 days", blob.lower())
        self._assert_clean_spoken(resp, aria_engine.SPOKEN_OVERTRAIN)
        spoken = f"{resp.get('message') or ''} {resp.get('prose_summary') or ''}"
        self.assertFalse(speak_guard.spoken_has_button(spoken, resp.get("card")))
        card = resp.get("card") or {}
        self.assertTrue(re.search(r"\d", str(card.get("headline") or "")), card)
        self.assertNotIn("load steady", (card.get("headline") or "").lower())
        self.assertNotIn("load steady", (card.get("win") or "").lower())
        self.assertIn("load rising", (card.get("headline") or "").lower())
        voice = aria_engine.generate_response(
            "Am I making progress?", ctx, voice_mode=True
        )
        self.assertEqual(voice["message"], voice["prose_summary"])
        self.assertEqual(
            voice["prose_summary"],
            f"{aria_engine.SPOKEN_OVERTRAIN} {aria_engine.SPOKEN_PROTECT_STEP}",
        )
        self.assertIn(aria_engine.SPOKEN_OVERTRAIN, voice["prose_summary"])
        self.assertFalse(re.search(r"\d", voice["prose_summary"] or ""))
        self.assertFalse(
            speak_guard.spoken_has_button(
                voice["prose_summary"], voice.get("card")
            )
        )

    def test_safety_turns_have_one_step_and_step_free_closer(self):
        from services.aria_engine import (
            ARIAContext,
            ReadinessContext,
            SleepContext,
            TrainingContext,
        )

        short = ARIAContext(
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
                weekly_load_score=40,
                acwr=1.1,
                is_overtrained=False,
                hours_since_last_workout=36,
            ),
        )
        heavy = ARIAContext(
            sleep=SleepContext(
                duration_minutes=480, nights_available=10, sleep_debt_7d_hours=0
            ),
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
        short_line = (
            f"{aria_engine.SPOKEN_SHORT_SLEEP} {aria_engine.SPOKEN_PROTECT_STEP}"
        )
        heavy_line = (
            f"{aria_engine.SPOKEN_OVERTRAIN} {aria_engine.SPOKEN_PROTECT_STEP}"
        )
        cases = (
            (short, "should I train hard today?", short_line, aria_engine.SPOKEN_SHORT_SLEEP),
            (heavy, "should I train hard today?", heavy_line, aria_engine.SPOKEN_OVERTRAIN),
            (both, "should I train hard today?", short_line, aria_engine.SPOKEN_SHORT_SLEEP),
        )
        for ctx, q, exact, safety in cases:
            for voice in (True, False):
                resp = aria_engine.generate_response(q, ctx, voice_mode=voice)
                self.assertEqual(resp["message"], resp["prose_summary"], resp)
                self.assertEqual(resp["prose_summary"], exact, resp["prose_summary"])
                self._assert_clean_spoken(resp, safety)
        progress = ARIAContext(
            sleep=SleepContext(
                duration_minutes=480, nights_available=10, sleep_debt_7d_hours=0
            ),
            readiness=ReadinessContext(
                hrv_7day_trend=2, recovery_score=72, hrv_days_available=7
            ),
            training=TrainingContext(
                weekly_load_score=95,
                acwr=1.51,
                is_overtrained=True,
                hours_since_last_workout=36,
            ),
            progress=ProgressContext(
                workouts_completed_30d=18,
                new_personal_records=2,
                training_load_trend="rising",
            ),
        )
        summary = aria_engine.generate_response("Am I making progress?", progress)
        self.assertEqual(summary["response_type"], "summary")
        self.assertEqual(summary["message"], summary["prose_summary"])
        self.assertEqual(summary["prose_summary"], heavy_line)
        self._assert_clean_spoken(summary, aria_engine.SPOKEN_OVERTRAIN)

    def test_sleep_question_never_uses_training_template(self):
        heavy = ARIAContext(
            sleep=SleepContext(
                duration_minutes=480, nights_available=10, sleep_debt_7d_hours=0
            ),
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
        banned = re.compile(r"(?i)\b(?:deload|overtrain|recovery)\b")
        resp = aria_engine.generate_response("How was my sleep last night?", heavy)
        spoken = f"{resp.get('message') or ''} {resp.get('prose_summary') or ''}"
        self.assertNotIn(aria_engine.SPOKEN_OVERTRAIN, spoken)
        # 8 h, no 7-day debt: never claim a shortfall the data doesn't show.
        self.assertNotIn(aria_engine.SPOKEN_SHORT_SLEEP, spoken)
        self.assertIn(aria_engine.SPOKEN_SLEEP_GUARD, spoken)
        card = resp.get("card") or {}
        action = str(card.get("action") or "")
        self.assertEqual(
            action,
            f"Back off the hard stuff — {aria_engine.ZONE2_SWAP[0].lower()}{aria_engine.ZONE2_SWAP[1:]}",
        )
        self.assertIn("zone 2", action.lower())
        self.assertIn("back off", action.lower())
        self.assertNotIn("deload", action.lower())
        visible = " ".join(
            [
                spoken,
                action,
                str(card.get("interpretation") or ""),
                str(card.get("metric") or ""),
            ]
        )
        self.assertNotRegex(visible, banned, visible)

    def test_ordinary_train_day_keeps_zone2_card(self):
        day = ARIAContext(
            sleep=SleepContext(
                duration_minutes=480, nights_available=10, sleep_debt_7d_hours=0
            ),
            readiness=ReadinessContext(
                hrv_7day_trend=-2, recovery_score=42, hrv_days_available=7
            ),
            training=TrainingContext(
                weekly_load_score=55,
                acwr=1.05,
                is_overtrained=False,
                hours_since_last_workout=20,
            ),
        )
        resp = aria_engine.generate_response("Should I train today?", day)
        spoken = f"{resp.get('message') or ''} {resp.get('prose_summary') or ''}"
        self.assertNotIn(aria_engine.SPOKEN_OVERTRAIN, spoken)
        card = resp.get("card") or {}
        blob = " ".join(
            [
                str(card.get("action") or ""),
                " ".join(str(item) for item in (resp.get("suggested_actions") or [])),
                spoken,
            ]
        ).lower()
        self.assertIn("zone 2", blob, (card, resp.get("suggested_actions"), spoken))


class SpokenBanSourceTests(unittest.TestCase):
    def test_iris_bar_and_floor_share_one_list(self):
        from aria_core.speak_guard import SPOKEN_BANNED, spoken_ban_hits

        for phrase in (
            "not a doctor",
            "i won't",
            "i don't claim",
            "i'm not going to",
            "keep the digits",
            "no figures",
        ):
            self.assertIn(phrase, SPOKEN_BANNED)
        self.assertEqual(
            spoken_ban_hits("I'm not going to guess without data."),
            ("i'm not going to",),
        )
        self.assertEqual(
            spoken_ban_hits("If last night felt bad, that's the read"),
            ("bad",),
        )
        self.assertEqual(
            spoken_ban_hits("so I won't invent one"),
            ("i won't",),
        )
        self.assertEqual(
            spoken_ban_hits("I'll keep the digits to myself. No figures in my mouth."),
            ("keep the digits", "no figures"),
        )
        self.assertEqual(spoken_ban_hits("overtraining flag is set"), ("overtrain",))
        self.assertEqual(spoken_ban_hits("treat it as a deload"), ("deload",))
        self.assertEqual(spoken_ban_hits("the recovery one"), ("recovery",))
        self.assertEqual(spoken_ban_hits("recovery 58"), ("recovery",))
        self.assertEqual(spoken_ban_hits("I don't have enough to go on yet."), ())
        self.assertEqual(spoken_ban_hits("If last night felt rough"), ())


if __name__ == "__main__":
    unittest.main()
