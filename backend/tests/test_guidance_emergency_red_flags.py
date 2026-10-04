"""Focused safety tests for cardiac / stroke / syncope red-flag phrasing.

classify_band must send these turns down the 911 emergency path, pick steps
by red-flag type, and must not escalate ordinary training soreness. CPR is
only for unresponsive / not-breathing arrest.
"""

from __future__ import annotations

import json
import os
import re
import tempfile
import unittest
from dataclasses import asdict
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from aria_core import state_read  # noqa: E402
from services import aria_engine  # noqa: E402
from services import guidance  # noqa: E402

CARDIAC_REPLY = (
    "Call 911 now. Stop what you're doing and sit or lie down somewhere safe. "
    "Don't drive yourself, and unlock the door so help can get in."
)
CARDIAC_HELPER_REPLY = (
    "Call 911 now. Help them sit or lie down, don't let them drive, unlock "
    "the door and stay with them."
)
STROKE_REPLY = (
    "Call 911 now. Note the time it started, don't eat or drink anything, "
    "don't drive, unlock the door and don't stay alone."
)
STROKE_HELPER_REPLY = (
    "Call 911 now. Note the time it started, give them nothing to eat or "
    "drink, and stay with them."
)
FAINT_REPLY = (
    "Call 911 now. Lie down flat and stay down, don't get back on the "
    "equipment or drive, and keep someone with you if you can."
)
FAINT_RESOLVED_REPLY = (
    "Call 911 now, even if you feel okay again. "
    "Passing out needs a proper look right away. "
    "Lie down, skip driving, and keep someone with you."
)
FAINT_RESOLVED_TRAINING_REPLY = (
    "Call 911 now, even if you feel okay again. "
    "Passing out mid-workout needs a proper look right away. "
    "Lie down, skip driving, and keep someone with you."
)
FAINT_HELPER_REPLY = f"Call 911 now. {guidance._EMERGENCY_FAINT_HELPER}"
CPR_REPLY = f"Call 911 now. {guidance._EMERGENCY_CPR}"
CONDITIONAL_CPR_REPLY = f"Call 911 now. {guidance._EMERGENCY_CPR_IF_NEEDED}"
PATIENT_FALLBACK_REPLY = (
    f"Call 911 now. {guidance._EMERGENCY_PATIENT_FALLBACK}"
)
SLEEP_REFER_REPLY = (
    "I can't tell from here — a doctor can check it properly. "
    "Meanwhile I'm glad to help with sleep habits."
)
HABIT_REFER_REPLY = (
    "I can't tell from here — a doctor can check it properly. "
    "Meanwhile I'm glad to help with the day-to-day stuff around it."
)
MEDICATION_REFER_REPLY = (
    "That one's a call for your doctor or pharmacist — they know what you're on. "
    "I'm glad to help with the day-to-day stuff around it."
)

CARDIAC_PHRASES = (
    "chest pain and my left arm is numb",
    "crushing chest pressure",
    "my chest feels tight and I cant breathe",
    "chest hurts and my jaw aches",
    "I have chest pressure and a cold sweat",
    "pressure in my chest and I'm short of breath",
    "my chest hurts and my right arm is numb",
    "chest tightness and pain in my jaw",
)

STROKE_PHRASES = (
    "my face is drooping",
    "I cant lift my right arm and my words are slurred",
    "sudden worst headache of my life",
    "one side of my body is numb",
    "the left side of my face is drooping",
)
STROKE_HELPER_PHRASES = (
    "my dad is suddenly confused and cant talk right",
    "her speech is slurred",
    "he's suddenly confused",
)

SYNCOPE_PHRASES = (
    "I passed out on the treadmill",
    "I was fainting during intervals",
)
SYNCOPE_TRAINING_PHRASES = (
    "I fainted during my run",
    "I blacked out after squats",
    "I fainted while running",
    "passed out after lifting",
)
SYNCOPE_HELPER_PHRASES = (
    "he blacked out on the bike",
)
SYNCOPE_HELPER_TRAINING_PHRASES = (
    "she fainted after her workout",
)

CPR_PHRASES = (
    "he's not breathing, call 911",
    "he collapsed and is not breathing",
    "he has no pulse",
    "she passed out and is unresponsive",
)

SORENESS_NON_EMERGENCY = (
    "my chest is sore after chest day",
    "my legs are sore after leg day",
    "chest is sore from bench and legs are dead from squats",
    "my arms are sore after push day",
    "I'm confused about my split",
    "I can't talk right now, let's train later",
)

_NO_CPR = ("Start CPR", "compressions")


def _assert_typed_emergency(
    test: unittest.TestCase, message: str, expected: str, *, cpr: bool
) -> None:
    test.assertEqual(guidance.classify_band(message), guidance.EMERGENCY, message)
    assessed = guidance.assess(message)
    test.assertIsNotNone(assessed, message)
    test.assertEqual(assessed.band, guidance.EMERGENCY, message)
    test.assertTrue(assessed.wants_escalation, message)
    test.assertEqual(assessed.prose, expected, message)
    test.assertEqual(assessed.message, expected, message)
    if message != "I feel suicidal and want to die":
        test.assertTrue(assessed.prose.startswith("Call 911 now"), message)
    low = assessed.prose.lower()
    test.assertNotIn("lifestyle coach", low, message)
    test.assertNotIn("not a doctor", low, message)
    test.assertNotIn("aspirin", low, message)
    if cpr:
        test.assertIn("CPR", assessed.prose, message)
        test.assertIn("compressions", low, message)
    else:
        for banned in _NO_CPR:
            test.assertNotIn(banned, assessed.prose, message)
        test.assertNotIn("compressions", low, message)


class CardiacRedFlagTests(unittest.TestCase):
    def test_cardiac_phrases_get_sit_down_steps(self):
        for message in CARDIAC_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, CARDIAC_REPLY, cpr=False)


class StrokeRedFlagTests(unittest.TestCase):
    def test_stroke_phrases_get_time_and_stay_steps(self):
        for message in STROKE_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, STROKE_REPLY, cpr=False)

    def test_stroke_helper_phrases_get_helper_steps(self):
        for message in STROKE_HELPER_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, STROKE_HELPER_REPLY, cpr=False)


class SyncopeRedFlagTests(unittest.TestCase):
    def test_syncope_phrases_get_lie_down_steps(self):
        for message in SYNCOPE_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, FAINT_REPLY, cpr=False)

    def test_syncope_training_phrases_get_mid_workout_911(self):
        for message in SYNCOPE_TRAINING_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(
                    self, message, FAINT_RESOLVED_TRAINING_REPLY, cpr=False
                )
                self.assertEqual(guidance.scout_emergency_line(message), FAINT_RESOLVED_TRAINING_REPLY)
                self.assertEqual(guidance.scout_safety(message).line, FAINT_RESOLVED_TRAINING_REPLY)

    def test_resolved_faint_variants_match_chat_and_scout(self):
        rows = (
            ("I fainted earlier but I'm fine now", FAINT_RESOLVED_REPLY),
            ("I fainted during my run, I'm fine now", FAINT_RESOLVED_TRAINING_REPLY),
            ("I fainted while running", FAINT_RESOLVED_TRAINING_REPLY),
            ("passed out after lifting", FAINT_RESOLVED_TRAINING_REPLY),
            ("I passed out", FAINT_REPLY),
        )
        for message, expected in rows:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, expected, cpr=False)
                self.assertEqual(guidance.scout_emergency_line(message), expected)
                self.assertEqual(
                    guidance.scout_safety(message).line, expected, message
                )
                self.assertEqual(
                    guidance.scout_safety(message).tier, guidance.TIER_EMERGENCY
                )

    def test_syncope_helper_phrases_get_helper_steps(self):
        for message in SYNCOPE_HELPER_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, FAINT_HELPER_REPLY, cpr=True)

    def test_syncope_helper_training_phrases_get_mid_workout_911(self):
        for message in SYNCOPE_HELPER_TRAINING_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(
                    self, message, FAINT_RESOLVED_TRAINING_REPLY, cpr=False
                )


class ArrestCprTests(unittest.TestCase):
    def test_not_breathing_and_unresponsive_get_cpr(self):
        for message in CPR_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, CPR_REPLY, cpr=True)

    def test_fainted_and_not_breathing_prefers_cpr(self):
        _assert_typed_emergency(
            self, "I fainted and he's not breathing", CPR_REPLY, cpr=True
        )


class OtherEmergencyTests(unittest.TestCase):
    def test_bare_call_911_gets_conditional_cpr(self):
        _assert_typed_emergency(self, "call 911 now", CONDITIONAL_CPR_REPLY, cpr=True)

    def test_heart_attack_uses_cardiac_steps(self):
        _assert_typed_emergency(
            self, "I think he's having a heart attack", CARDIAC_HELPER_REPLY, cpr=False
        )

    def test_patient_overdose_is_fallback_without_cpr(self):
        _assert_typed_emergency(
            self, "I overdosed", PATIENT_FALLBACK_REPLY, cpr=False
        )

    def test_bare_overdose_is_emergency_ingestion(self):
        message = "I took an overdose"
        lower = guidance.normalize_message(message)
        self.assertEqual(guidance.classify_band(message), guidance.EMERGENCY)
        self.assertEqual(guidance._emergency_kind(lower), "ingestion")
        assessed = guidance.assess(message)
        self.assertIsNotNone(assessed)
        self.assertEqual(assessed.band, guidance.EMERGENCY)
        self.assertEqual(assessed.prose, PATIENT_FALLBACK_REPLY)
        self.assertEqual(assessed.suggested_actions[0], "Call 911")
        self.assertIn("Call 911", assessed.suggested_actions)

    def test_heavy_bleeding_on_period_is_not_chat_emergency(self):
        for message in ("heavy bleeding on my period", "There's heavy bleeding"):
            with self.subTest(message=message):
                self.assertNotEqual(
                    guidance.classify_band(message), guidance.EMERGENCY, message
                )
                assessed = guidance.assess(message)
                if assessed is not None:
                    self.assertNotEqual(assessed.band, guidance.EMERGENCY, message)
                    self.assertNotIn("Call 911 now.", assessed.prose)

    def test_chest_hurts_after_bench_is_todays_band(self):
        message = "My chest hurts after bench"
        band = guidance.classify_band(message)
        assessed = guidance.assess(message)
        # "hurts" is a lift-not-soreness cue, so this is chest triage, not
        # emergency and not coach. Pin today's band; do not invent a new one.
        self.assertEqual(band, guidance.TRIAGE)
        self.assertIsNotNone(assessed)
        self.assertEqual(assessed.band, guidance.TRIAGE)


class SelfHarmEmergencyTests(unittest.TestCase):
    def test_crisis_line_does_not_say_call_911_twice(self):
        assessed = guidance.assess("I feel suicidal and want to die")
        self.assertEqual(assessed.band, guidance.EMERGENCY)
        self.assertTrue(assessed.wants_escalation)
        self.assertEqual(assessed.prose, guidance._CRISIS_LINE)
        low = assessed.prose.lower()
        self.assertTrue(low.startswith("you matter"))
        self.assertIn("988", assessed.prose)
        self.assertIn("call or text", low)
        self.assertEqual(assessed.prose.count("911"), 1)
        self.assertEqual(low.count("call 911 now"), 1)
        self.assertFalse(assessed.prose.startswith("Call 911 now"))
        self.assertNotIn("chest compress", low)
        self.assertNotIn("start cpr", low)
        self.assertNotIn("lifestyle coach", low)
        self.assertNotIn("joke", low)


class TrainingSorenessStaysCoachTests(unittest.TestCase):
    def test_soreness_is_not_emergency(self):
        for message in SORENESS_NON_EMERGENCY:
            with self.subTest(message=message):
                self.assertEqual(
                    guidance.classify_band(message), guidance.COACH, message
                )
                self.assertIsNone(guidance.assess(message), message)


class EmergencyDigitExceptionTests(unittest.TestCase):
    """Nyx: 911 / compression digits are an emergency-band exception only."""

    def test_same_digits_fail_the_existing_check_off_emergency_band(self):
        cardiac = guidance.assess("chest pain and my left arm is numb")
        self.assertEqual(cardiac.band, guidance.EMERGENCY)
        self.assertEqual(cardiac.prose, CARDIAC_REPLY)
        self.assertTrue(state_read._DIGIT.search(cardiac.prose))
        self.assertIn("911", cardiac.prose)
        self.assertNotRegex(cardiac.prose, r"100[–-]120")

        arrest = guidance.assess("he's not breathing, call 911")
        self.assertEqual(arrest.prose, CPR_REPLY)
        self.assertRegex(arrest.prose, r"100[–-]120")

        self.assertEqual(
            guidance.classify_band("should I train hard today?"), guidance.COACH
        )
        coach_with_same_digits = (
            "Call 911 now. Start CPR: about 100–120 compressions a minute."
        )
        with self.assertRaises(ValueError):
            if state_read._DIGIT.search(coach_with_same_digits):
                raise ValueError(
                    f"state-read phrase has a digit: {coach_with_same_digits!r}"
                )


class EmergencyBedrockBypassTests(unittest.TestCase):
    """Sol: even with Bedrock flagged on, the emergency turn never calls it."""

    def _ctx(self):
        return aria_engine.ARIAContext.from_payload({"user_id": "u"})

    def test_chest_pain_turn_skips_mocked_bedrock(self):
        calls: list[tuple] = []

        def fake_converse(model_id, system, user):
            calls.append((model_id, system, user))
            return '{"prose_summary": "joke about skipping chest day"}'

        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        try:
            result = aria_engine.generate_response_live(
                "chest pain and my left arm is numb",
                self._ctx(),
                converse=fake_converse,
            )
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous

        self.assertEqual(result["guidance_band"], guidance.EMERGENCY)
        self.assertTrue(result["emergency_escalation"])
        self.assertEqual(result["message"], CARDIAC_REPLY)
        self.assertEqual(result["message"], result["prose_summary"])
        self.assertEqual(calls, [])
        self.assertNotIn("lifestyle coach", result["message"].lower())
        self.assertNotIn("joke", result["message"].lower())
        self.assertNotIn("Start CPR", result["message"])
        self.assertNotIn("compressions", result["message"].lower())

    def test_refer_out_and_self_harm_skip_mocked_bedrock(self):
        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        try:
            for message, band, needle in (
                ("do I have diabetes?", guidance.REFER_OUT, "day-to-day stuff around it"),
                ("I feel suicidal and want to die", guidance.EMERGENCY, "988"),
            ):
                with self.subTest(message=message):
                    calls: list[tuple] = []

                    def fake_converse(model_id, system, user):
                        calls.append((model_id, system, user))
                        return '{"prose_summary": "model tried to answer"}'

                    result = aria_engine.generate_response_live(
                        message, self._ctx(), converse=fake_converse
                    )
                    self.assertEqual(result["guidance_band"], band, message)
                    self.assertEqual(calls, [], message)
                    self.assertIn(needle, result["message"].lower(), message)
                    expected = guidance.assess(message)
                    self.assertEqual(result["message"], expected.message, message)
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous


class PatientVsBystanderTests(unittest.TestCase):
    def test_patient_phrasings_get_patient_steps_without_cpr(self):
        cases = (
            ("my arm is numb with chest pain", CARDIAC_REPLY),
            ("my face feels droopy", STROKE_REPLY),
            ("I just fainted", FAINT_REPLY),
        )
        for message, expected in cases:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, expected, cpr=False)

    def test_bystander_arrest_gets_cpr(self):
        for message in (
            "he's not breathing",
            "she collapsed and isn't breathing",
        ):
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, CPR_REPLY, cpr=True)

    def test_collapsed_without_breathing_info_is_conditional_cpr(self):
        _assert_typed_emergency(self, "she collapsed", CONDITIONAL_CPR_REPLY, cpr=True)


class EmergencyDigitRuleTests(unittest.TestCase):
    """On the emergency band, only 911, 988, and CPR compression digits."""

    def test_patient_replies_only_use_911(self):
        for message, expected in (
            ("chest pain and my left arm is numb", CARDIAC_REPLY),
            ("my face is drooping", STROKE_REPLY),
            ("I just fainted", FAINT_REPLY),
        ):
            with self.subTest(message=message):
                assessed = guidance.assess(message)
                self.assertEqual(assessed.prose, expected)
                self.assertEqual(
                    guidance.extra_speak_digits(assessed.prose, message),
                    frozenset(),
                )
                self.assertEqual(
                    guidance.allowed_speak_digits(message),
                    guidance.SPEAK_DIGITS,
                )

    def test_cpr_replies_may_use_compression_numbers(self):
        for message in ("he's not breathing", "call 911 now"):
            with self.subTest(message=message):
                assessed = guidance.assess(message)
                self.assertEqual(
                    guidance.extra_speak_digits(assessed.prose, message),
                    frozenset(),
                )
                self.assertTrue(
                    guidance.CPR_SPEAK_DIGITS <= guidance.allowed_speak_digits(message)
                )
                self.assertIn("911", set(re.findall(r"\d+", assessed.prose)))
                self.assertIn("100", set(re.findall(r"\d+", assessed.prose)))
                self.assertIn("120", set(re.findall(r"\d+", assessed.prose)))

    def test_self_harm_allows_988_and_911_only(self):
        message = "I feel suicidal and want to die"
        assessed = guidance.assess(message)
        self.assertEqual(
            guidance.extra_speak_digits(assessed.prose, message),
            frozenset(),
        )
        self.assertEqual(
            set(re.findall(r"\d+", assessed.prose)),
            set(guidance.SPEAK_DIGITS),
        )

    def test_faint_reply_cannot_keep_cpr_digits(self):
        dirty = f"{FAINT_REPLY} {guidance._EMERGENCY_CPR_STEPS}"
        self.assertEqual(
            guidance.extra_speak_digits(dirty, "I just fainted") & guidance.CPR_SPEAK_DIGITS,
            guidance.CPR_SPEAK_DIGITS,
        )


class GuardrailDoesNotWriteMemoryTests(unittest.TestCase):
    """Engine path: safety bands do not mutate companion memory on the context."""

    def test_emergency_self_harm_and_refer_out_leave_insights_untouched(self):
        ctx = aria_engine.ARIAContext.from_payload({"user_id": "memory-guard"})
        ctx.last_insights = ["keep today easy"]
        before = list(ctx.last_insights)
        for message in (
            "chest pain and my left arm is numb",
            "I feel suicidal and want to die",
            "do I have diabetes?",
        ):
            with self.subTest(message=message):
                aria_engine.generate_response(message, ctx)
                self.assertEqual(list(ctx.last_insights), before, message)


class HelperPatientSplitTests(unittest.TestCase):
    def test_helper_cases_have_no_patient_only_steps(self):
        cases = (
            ("my dad has chest pain and his arm is numb", CARDIAC_HELPER_REPLY),
            ("she has slurred speech", STROKE_HELPER_REPLY),
            ("my friend fainted", FAINT_HELPER_REPLY),
            ("she overdosed", CONDITIONAL_CPR_REPLY),
        )
        banned = (
            "stop what you're doing",
            "don't drive yourself",
            "don't stay alone",
            "lie down flat and stay down",
            "unlock the door and stay on the line",
        )
        for message, expected in cases:
            with self.subTest(message=message):
                assessed = guidance.assess(message)
                self.assertEqual(assessed.prose, expected, message)
                low = assessed.prose.lower()
                for bit in banned:
                    self.assertNotIn(bit, low, message)

    def test_patient_cases_contain_no_them_and_no_cpr(self):
        # Phrases not already pinned by #384 PatientVsBystanderTests.
        cases = (
            ("chest pain and my left arm is numb", CARDIAC_REPLY),
            ("I passed out on the treadmill", FAINT_REPLY),
            ("I overdosed", PATIENT_FALLBACK_REPLY),
        )
        for message, expected in cases:
            with self.subTest(message=message):
                assessed = guidance.assess(message)
                self.assertEqual(assessed.prose, expected, message)
                low = assessed.prose.lower()
                self.assertNotIn("them", low, message)
                self.assertNotIn("stay with them", low, message)
                self.assertNotIn("start cpr", low, message)
                self.assertNotIn("compressions", low, message)
                self.assertNotIn("Start first aid", assessed.suggested_actions)
                self.assertEqual(assessed.suggested_actions, ["Call 911", "Stay on the line"])

    def test_droopy_face_is_patient_stroke_without_them(self):
        """#384 added the droopy trigger; this pin is the unmixed patient reply."""
        assessed = guidance.assess("my face feels droopy")
        self.assertEqual(assessed.band, guidance.EMERGENCY)
        self.assertEqual(assessed.prose, STROKE_REPLY)
        low = assessed.prose.lower()
        self.assertNotIn("them", low)
        self.assertNotIn("stay with them", low)
        self.assertNotIn("if it's someone else", low)
        self.assertNotIn("start cpr", low)
        self.assertNotIn("compressions", low)
        self.assertNotIn("Start first aid", assessed.suggested_actions)
        self.assertEqual(assessed.suggested_actions, ["Call 911", "Stay on the line"])
        self.assertTrue(assessed.prose.startswith("Call 911 now."))

    def test_they_said_chest_pain_is_patient_not_helper(self):
        message = "they said my chest pain could be a heart attack"
        _assert_typed_emergency(self, message, CARDIAC_REPLY, cpr=False)
        assessed = guidance.assess(message)
        self.assertEqual(assessed.prose, CARDIAC_REPLY)
        self.assertNotEqual(assessed.prose, CARDIAC_HELPER_REPLY)
        low = assessed.prose.lower()
        self.assertNotIn("them", low)
        self.assertNotIn("stay with them", low)

    def test_helper_pronoun_keys_on_symptom_subject(self):
        _assert_typed_emergency(
            self, "her face is drooping", STROKE_HELPER_REPLY, cpr=False
        )
        _assert_typed_emergency(
            self, "my dad has crushing chest pain", CARDIAC_HELPER_REPLY, cpr=False
        )

    def test_refer_out_is_two_warm_sentences(self):
        diabetes = guidance.assess("do I have diabetes?")
        apnea = guidance.assess("do I have sleep apnea?")
        medication = guidance.assess("should I up my dose")
        self.assertEqual(diabetes.prose, HABIT_REFER_REPLY)
        self.assertEqual(apnea.prose, SLEEP_REFER_REPLY)
        self.assertEqual(medication.prose, MEDICATION_REFER_REPLY)
        for assessed, allow_pharmacist in (
            (diabetes, False),
            (apnea, False),
            (medication, True),
        ):
            low = assessed.prose.lower()
            self.assertNotIn("recovery", low)
            self.assertNotIn("not a doctor", low)
            self.assertEqual(assessed.band, guidance.REFER_OUT)
            if allow_pharmacist:
                self.assertIn("pharmacist", low)
            else:
                self.assertNotIn("pharmacist", low)
                self.assertNotIn("medication", low)

    def test_refer_out_wording_pinned_to_trigger(self):
        apnea = guidance.assess("do I have sleep apnea?")
        self.assertEqual(apnea.prose, SLEEP_REFER_REPLY)
        self.assertEqual(apnea.band, guidance.REFER_OUT)
        self.assertNotIn("pharmacist", apnea.prose.lower())
        med = guidance.assess("can I take ibuprofen")
        self.assertEqual(med.prose, MEDICATION_REFER_REPLY)
        self.assertEqual(med.band, guidance.REFER_OUT)
        self.assertNotIn("ibuprofen", med.prose.lower())
        self.assertNotRegex(med.prose, r"\d")
        self.assertIn("pharmacist", med.prose.lower())
        self.assertNotIn("not a doctor", med.prose.lower())
        self.assertNotIn("recovery", med.prose.lower())


class ChatRouteSafetyTests(unittest.TestCase):
    """Rowan + Sol: /ai/chat does not persist safety turns or call Bedrock."""

    def setUp(self):
        from storage import dynamodb

        dynamodb.clear_local_store()

    def _chat(self, uid: str, message: str, **env):
        import json
        from routes.aria import handle_post_ai_chat

        payload = {"message": message, **env}
        result = handle_post_ai_chat(payload, user_id=uid)
        self.assertEqual(result["statusCode"], 200, result)
        return json.loads(result["body"])

    def test_safety_turns_do_not_write_memory_or_persona(self):
        from services.aria_context import CoachContextEngine
        from services import contextual_learner

        uid = "safety-memory-lock"
        engine = CoachContextEngine()
        living = engine.get_or_create_context(uid)
        living.last_insights = ["keep today easy"]
        living.recent_patterns = ["easy weeks"]
        engine.update_context(
            uid,
            {
                "last_insights": list(living.last_insights),
                "recent_patterns": list(living.recent_patterns),
            },
        )
        persona = contextual_learner.load(uid)
        before_insights = list(engine.get_or_create_context(uid).last_insights)
        before_patterns = list(engine.get_or_create_context(uid).recent_patterns)
        before_persona = asdict(persona)
        for message in (
            "chest pain and my left arm is numb",
            "do I have sleep apnea?",
            "I feel suicidal and want to die",
        ):
            with self.subTest(message=message):
                self._chat(uid, message)
                after = engine.get_or_create_context(uid)
                self.assertEqual(list(after.last_insights), before_insights, message)
                self.assertEqual(list(after.recent_patterns), before_patterns, message)
                loaded = contextual_learner.load(uid)
                after_persona = asdict(loaded)
                self.assertEqual(after_persona, before_persona, message)
                blob = " ".join(after.last_insights + after.recent_patterns).lower()
                self.assertNotIn("suicidal", blob)
                self.assertNotIn("want to die", blob)
                persona_blob = str(after_persona).lower()
                self.assertNotIn("suicidal", persona_blob)
                self.assertNotIn("want to die", persona_blob)

    def test_chat_route_skips_bedrock_on_safety_bands(self):
        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        calls: list = []

        def boom(model_id, system, user):
            calls.append((model_id, system, user))
            raise AssertionError("Bedrock called")

        def boom_swarm(*args, **kwargs):
            raise AssertionError("swarm called")

        try:
            with patch(
                "services.aria_engine._default_converse", boom
            ), patch(
                "aria_core.aria_engine._default_converse", boom
            ), patch(
                "services.aria_swarm.run_swarm", boom_swarm
            ):
                for message, expected in (
                    ("chest pain and my left arm is numb", CARDIAC_REPLY),
                    ("do I have sleep apnea?", SLEEP_REFER_REPLY),
                    ("should I up my dose", MEDICATION_REFER_REPLY),
                    ("I feel suicidal and want to die", guidance._CRISIS_LINE),
                ):
                    with self.subTest(message=message):
                        body = self._chat("sol-chat-lock", message)
                        self.assertEqual(body["message"], expected, message)
                        self.assertEqual(calls, [], message)
                        self.assertFalse(body.get("swarm"), message)
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous

    def test_route_engine_and_dummy_agree_on_band(self):
        from backend.ai import aria_cli
        from backend.ai.aria_chat.session import run_turn

        real = guidance.classify_band
        calls: list[str] = []

        def spy(message):
            calls.append(message)
            return real(message)

        cases = (
            ("chest pain and my left arm is numb", guidance.EMERGENCY),
            ("do I have sleep apnea?", guidance.REFER_OUT),
            ("should I up my dose", guidance.REFER_OUT),
            ("I feel suicidal and want to die", guidance.EMERGENCY),
        )
        for message, expected in cases:
            with self.subTest(message=message):
                before = len(calls)
                with patch.object(guidance, "classify_band", spy):
                    body = self._chat("one-classifier", message)
                    engine = aria_engine.generate_response(
                        message,
                        aria_engine.ARIAContext.from_payload(
                            {"user_id": "one-classifier"}
                        ),
                        guidance_band=expected,
                    )
                dummy = run_turn(
                    message,
                    payload={"context": aria_cli.PROFILES["depleted"]["context"]},
                    persist_log=False,
                    install_pseudonym="inst-band-agree",
                )
                self.assertEqual(calls[before:], [message], message)
                self.assertEqual(body.get("guidance_band"), expected, message)
                self.assertEqual(engine.get("guidance_band"), expected, message)
                self.assertEqual(dummy.get("guidance_band"), expected, message)

    def test_third_person_emergency_skips_bedrock_and_omits_memory_keys(self):
        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        calls: list = []

        def boom(model_id, system, user):
            calls.append((model_id, system, user))
            raise AssertionError("Bedrock called")

        def boom_swarm(*args, **kwargs):
            raise AssertionError("swarm called")

        phrases = (
            "he's having chest pain",
            "my dad has chest pain",
            "my dad has chest pain after bench",
            "she is slurring her words",
            "my grandpa is slurring his words",
        )
        try:
            with patch(
                "services.aria_engine._default_converse", boom
            ), patch(
                "aria_core.aria_engine._default_converse", boom
            ), patch(
                "services.aria_swarm.run_swarm", boom_swarm
            ):
                for message in phrases:
                    with self.subTest(message=message):
                        body = self._chat("third-person-lock", message)
                        self.assertEqual(
                            body.get("guidance_band"), guidance.EMERGENCY, message
                        )
                        self.assertTrue(body.get("safety_lock"), message)
                        self.assertTrue(body.get("emergency_escalation"), message)
                        self.assertEqual(calls, [], message)
                        self.assertFalse(body.get("swarm"), message)
                        self.assertNotIn("memory", body)
                        self.assertNotIn("memory_reference", body)
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous

    def test_insight_mode_emergency_sets_safety_lock_without_memory_keys(self):
        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        converse_calls: list = []
        swarm_calls: list = []
        memory_keys = ("memory", "memory_reference", "checkin", "calendar_ingested")

        def boom(model_id, system, user):
            converse_calls.append((model_id, system, user))
            raise AssertionError("Bedrock called")

        def boom_swarm(*args, **kwargs):
            swarm_calls.append((args, kwargs))
            raise AssertionError("swarm called")

        try:
            with patch(
                "services.aria_engine._default_converse", boom
            ), patch(
                "aria_core.aria_engine._default_converse", boom
            ), patch(
                "services.aria_swarm.run_swarm", boom_swarm
            ):
                for message, band in (
                    ("he's having chest pain", guidance.EMERGENCY),
                    ("do I have sleep apnea?", guidance.REFER_OUT),
                ):
                    with self.subTest(message=message):
                        body = self._chat("insight-safety-lock", message, mode="insight")
                        self.assertEqual(body.get("guidance_band"), band, message)
                        self.assertTrue(body.get("safety_lock"), message)
                        self.assertEqual(body.get("reasoning_source"), "deterministic")
                        self.assertEqual(body.get("context_updates"), {})
                        for key in memory_keys:
                            self.assertNotIn(key, body)

                normal = self._chat(
                    "insight-safety-lock",
                    "Analyze my lifestyle today in 2-3 sentences.",
                    mode="insight",
                )
                self.assertFalse(normal.get("safety_lock"))
                self.assertEqual(normal.get("reasoning_source"), "deterministic")
                self.assertEqual(normal.get("context_updates"), {})
                self.assertIsNone(normal.get("memory_reference"))
                self.assertNotIn("memory", normal)
                self.assertNotIn("checkin", normal)
                self.assertNotIn("calendar_ingested", normal)
                self.assertEqual(converse_calls, [])
                self.assertEqual(swarm_calls, [])
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous

    def test_safety_replies_skip_memory_and_checkin_fields(self):
        from services.aria_context import CoachContextEngine

        uid = "safety-memory-prefix"
        engine = CoachContextEngine()
        engine.update_context(
            uid,
            {
                "last_insights": ["SEEDED_MEMORY_NOTE focused on recovery"],
                "relationship_level": 5,
            },
        )
        engine.record_life_fact(uid, "SEEDED_MEMORY_NOTE trains at dawn")
        for message, opener in (
            ("chest pain and my left arm is numb", "Call 911 now."),
            ("I feel suicidal and want to die", "You matter,"),
        ):
            with self.subTest(message=message):
                body = self._chat(uid, message)
                self.assertTrue(body["message"].startswith(opener), body["message"])
                if opener == "Call 911 now.":
                    first = body["message"].split(".", 1)[0] + "."
                    self.assertEqual(first, "Call 911 now.")
                self.assertNotIn("memory", body)
                self.assertNotIn("memory_reference", body)
                self.assertNotIn("checkin", body)
                self.assertNotIn("calendar_ingested", body)
                self.assertNotIn("SEEDED_MEMORY_NOTE", body["message"])
                self.assertNotIn("recovery", body["message"].lower())


THIRD_PERSON_EMERGENCY_CASES = (
    ("he's having chest pain", CARDIAC_HELPER_REPLY),
    ("my dad has chest pain", CARDIAC_HELPER_REPLY),
    ("my dad has chest pain after bench", CARDIAC_HELPER_REPLY),
    ("she is slurring her words", STROKE_HELPER_REPLY),
    ("my grandpa is slurring his words", STROKE_HELPER_REPLY),
)
THIRD_PERSON_COACH_CASES = (
    "my chest is sore after chest day",
    "his chest is sore after bench",
    "I was slurring my lines at rehearsal",
)


class ThirdPersonEmergencyParityTests(unittest.TestCase):
    """assess() and /ai/chat must agree. Dummy logs redact emergencies only."""

    def setUp(self):
        from storage import dynamodb

        dynamodb.clear_local_store()

    def _chat(self, uid: str, message: str):
        from routes.aria import handle_post_ai_chat

        result = handle_post_ai_chat({"message": message}, user_id=uid)
        self.assertEqual(result["statusCode"], 200, result)
        return json.loads(result["body"])

    def _bands(self, message: str):
        assessed = guidance.assess(message)
        assess_band = assessed.band if assessed is not None else guidance.COACH
        body = self._chat("third-person-parity", message)
        chat_band = body.get("guidance_band") or guidance.COACH
        return assess_band, chat_band, assessed, body

    def test_emergency_cases_agree_and_use_helper_reply(self):
        for message, expected in THIRD_PERSON_EMERGENCY_CASES:
            with self.subTest(message=message):
                assess_band, chat_band, assessed, body = self._bands(message)
                self.assertEqual(assess_band, guidance.EMERGENCY, message)
                self.assertEqual(chat_band, guidance.EMERGENCY, message)
                self.assertEqual(assess_band, chat_band, message)
                self.assertIsNotNone(assessed, message)
                self.assertEqual(assessed.prose, expected, message)
                self.assertEqual(assessed.message, expected, message)
                self.assertEqual(body["message"], expected, message)

    def test_coach_cases_agree_and_stay_coach(self):
        for message in THIRD_PERSON_COACH_CASES:
            with self.subTest(message=message):
                assess_band, chat_band, assessed, body = self._bands(message)
                self.assertEqual(assess_band, guidance.COACH, message)
                self.assertEqual(chat_band, guidance.COACH, message)
                self.assertEqual(assess_band, chat_band, message)
                self.assertIsNone(assessed, message)
                self.assertNotEqual(body.get("guidance_band"), guidance.EMERGENCY, message)
                self.assertNotEqual(body.get("message"), CARDIAC_HELPER_REPLY, message)
                self.assertNotEqual(body.get("message"), STROKE_HELPER_REPLY, message)

    def test_dummy_log_redacts_emergency_and_keeps_coach_text(self):
        from backend.ai.aria_chat import logging as chatlog
        from backend.ai.aria_chat.session import ChatSession

        next_turn = "hey, how's it going?"
        cases = [
            (message, True) for message, _expected in THIRD_PERSON_EMERGENCY_CASES
        ] + [(message, False) for message in THIRD_PERSON_COACH_CASES]
        for message, emergency in cases:
            with self.subTest(message=message, emergency=emergency):
                with tempfile.TemporaryDirectory() as tmp:
                    session = ChatSession(
                        payload={"context": {}},
                        log_dir=tmp,
                        session_id=f"parity-{abs(hash(message)) % 10_000_000}",
                        memory_enabled=False,
                        install_pseudonym="inst-third-person",
                    )
                    session.turn(message)
                    session.turn(next_turn)
                    blob = Path(session.log_path).read_text(encoding="utf-8")
                    rows = [
                        json.loads(line)
                        for line in blob.splitlines()
                        if line.strip()
                    ]
                    self.assertEqual(len(rows), 2, message)
                    dest = Path(tmp) / "export.jsonl"
                    session.export(dest)
                    exported = dest.read_text(encoding="utf-8")
                    exp_rows = [
                        json.loads(line)
                        for line in exported.splitlines()
                        if line.strip()
                    ]
                    if emergency:
                        self.assertEqual(
                            rows[0]["user_turn"], chatlog.REDACTED_USER_TURN, message
                        )
                        self.assertEqual(
                            rows[1]["request_history"],
                            [chatlog.REDACTED_USER_TURN],
                            message,
                        )
                        self.assertEqual(
                            exp_rows[0]["user_turn"],
                            chatlog.REDACTED_USER_TURN,
                            message,
                        )
                        self.assertEqual(
                            exp_rows[1]["request_history"],
                            [chatlog.REDACTED_USER_TURN],
                            message,
                        )
                        self.assertNotIn(message, blob)
                        self.assertNotIn(message, exported)
                    else:
                        self.assertEqual(rows[0]["user_turn"], message, message)
                        self.assertEqual(rows[1]["request_history"], [message], message)
                        self.assertEqual(exp_rows[0]["user_turn"], message, message)
                        self.assertEqual(
                            exp_rows[1]["request_history"], [message], message
                        )
                        self.assertNotEqual(
                            rows[0]["user_turn"], chatlog.REDACTED_USER_TURN, message
                        )


if __name__ == "__main__":
    unittest.main()

