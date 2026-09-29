"""Focused safety tests for cardiac / stroke / syncope red-flag phrasing.

classify_band must send these turns down the 911 emergency path, and must
not escalate ordinary training soreness. Existing acute cues (not breathing,
call 911) stay emergency.
"""

from __future__ import annotations

import os
import unittest

import _bootstrap  # noqa: F401

from aria_core import state_read  # noqa: E402
from services import aria_engine  # noqa: E402
from services import guidance  # noqa: E402

# User-facing examples plus several natural variants per red-flag family.
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

EXISTING_EMERGENCY = (
    "he's not breathing, call 911",
    "he collapsed and is not breathing",
)

SORENESS_NON_EMERGENCY = (
    "my chest is sore after chest day",
    "my legs are sore after leg day",
    "chest is sore from bench and legs are dead from squats",
    "my arms are sore after push day",
    "I'm confused about my split",
    "I can't talk right now, let's train later",
)


def _assert_911_emergency(test: unittest.TestCase, message: str) -> None:
    test.assertEqual(
        guidance.classify_band(message), guidance.EMERGENCY, message
    )
    assessed = guidance.assess(message)
    test.assertIsNotNone(assessed, message)
    test.assertEqual(assessed.band, guidance.EMERGENCY, message)
    test.assertTrue(assessed.wants_escalation, message)
    test.assertTrue(assessed.prose.startswith("Call 911 now"), message)
    test.assertIn("CPR", assessed.prose, message)
    low = assessed.prose.lower()
    test.assertNotIn("lifestyle coach", low, message)
    test.assertNotIn("not a doctor", low, message)


class CardiacRedFlagTests(unittest.TestCase):
    def test_cardiac_phrases_are_emergency_911(self):
        for message in CARDIAC_PHRASES:
            with self.subTest(message=message):
                _assert_911_emergency(self, message)


class StrokeRedFlagTests(unittest.TestCase):
    def test_stroke_phrases_are_emergency_911(self):
        for message in STROKE_PHRASES:
            with self.subTest(message=message):
                _assert_911_emergency(self, message)


class SyncopeRedFlagTests(unittest.TestCase):
    def test_syncope_phrases_are_emergency_911(self):
        for message in SYNCOPE_PHRASES:
            with self.subTest(message=message):
                _assert_911_emergency(self, message)


class ExistingEmergencyStillFiresTests(unittest.TestCase):
    def test_not_breathing_call_911_still_escalates(self):
        for message in EXISTING_EMERGENCY:
            with self.subTest(message=message):
                _assert_911_emergency(self, message)


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
        assessed = guidance.assess("chest pain and my left arm is numb")
        self.assertEqual(assessed.band, guidance.EMERGENCY)
        self.assertTrue(state_read._DIGIT.search(assessed.prose))
        self.assertIn("911", assessed.prose)
        self.assertRegex(assessed.prose, r"100[–-]120")

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
        self.assertTrue(result["message"].startswith("Call 911 now"))
        self.assertEqual(result["message"], result["prose_summary"])
        self.assertEqual(calls, [])
        self.assertNotIn("lifestyle coach", result["message"].lower())
        self.assertNotIn("joke", result["message"].lower())


if __name__ == "__main__":
    unittest.main()
