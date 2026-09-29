"""Focused safety tests for cardiac / stroke / syncope red-flag phrasing.

classify_band must send these turns down the 911 emergency path, pick steps
by red-flag type, and must not escalate ordinary training soreness. CPR is
only for unresponsive / not-breathing arrest.
"""

from __future__ import annotations

import os
import re
import unittest

import _bootstrap  # noqa: F401

from aria_core import state_read  # noqa: E402
from services import aria_engine  # noqa: E402
from services import guidance  # noqa: E402

CARDIAC_REPLY = (
    "Call 911 now. Stop what you're doing and sit or lie down somewhere safe. "
    "Don't drive yourself, and unlock the door so help can get in."
)
STROKE_REPLY = (
    "Call 911 now. Note the time the symptoms started, don't eat or drink "
    "anything, and don't drive. Stay with them if it's someone else."
)
FAINT_REPLY = (
    "Call 911 now. Lie down flat and stay down, don't get back on the "
    "equipment or drive, and keep someone with you if you can."
)
CPR_REPLY = f"Call 911 now. {guidance._EMERGENCY_CPR}"
CONDITIONAL_CPR_REPLY = f"Call 911 now. {guidance._EMERGENCY_CPR_IF_NEEDED}"

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
    "my dad is suddenly confused and cant talk right",
    "her speech is slurred",
    "sudden worst headache of my life",
    "one side of my body is numb",
    "the left side of my face is drooping",
    "he's suddenly confused",
)

SYNCOPE_PHRASES = (
    "I passed out on the treadmill",
    "I fainted during my run",
    "I blacked out after squats",
    "she fainted after her workout",
    "he blacked out on the bike",
    "I was fainting during intervals",
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


class SyncopeRedFlagTests(unittest.TestCase):
    def test_syncope_phrases_get_lie_down_steps(self):
        for message in SYNCOPE_PHRASES:
            with self.subTest(message=message):
                _assert_typed_emergency(self, message, FAINT_REPLY, cpr=False)


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
            self, "I think he's having a heart attack", CARDIAC_REPLY, cpr=False
        )


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
                ("do I have diabetes?", guidance.REFER_OUT, "not a doctor"),
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

    _TOKEN = re.compile(r"\d+")
    _PATIENT = {"911"}
    _CRISIS = {"911", "988"}
    _CPR = {"911", "100", "120", "2", "30"}

    def _digits(self, text: str) -> set[str]:
        return set(self._TOKEN.findall(text))

    def test_patient_replies_only_use_911(self):
        for message, expected in (
            ("chest pain and my left arm is numb", CARDIAC_REPLY),
            ("my face is drooping", STROKE_REPLY),
            ("I just fainted", FAINT_REPLY),
        ):
            with self.subTest(message=message):
                assessed = guidance.assess(message)
                self.assertEqual(assessed.prose, expected)
                self.assertEqual(self._digits(assessed.prose), self._PATIENT)

    def test_cpr_replies_may_use_compression_numbers(self):
        for message in ("he's not breathing", "call 911 now"):
            with self.subTest(message=message):
                assessed = guidance.assess(message)
                digits = self._digits(assessed.prose)
                self.assertTrue(digits <= self._CPR, digits)
                self.assertIn("911", digits)
                self.assertIn("100", digits)
                self.assertIn("120", digits)

    def test_self_harm_allows_988_and_911_only(self):
        assessed = guidance.assess("I feel suicidal and want to die")
        self.assertEqual(self._digits(assessed.prose), self._CRISIS)


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


if __name__ == "__main__":
    unittest.main()

