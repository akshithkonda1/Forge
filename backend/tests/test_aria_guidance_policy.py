"""Tests for aria_core.aria_guidance_policy, the Python port of ForgeCore's
AriaGuidancePolicy.swift (Dummy's 3-band policy, not the 4-band guidance.assess).
"""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import aria_guidance_policy as gp  # noqa: E402


class AriaGuidancePolicyTests(unittest.TestCase):
    def test_ordinary_coaching_is_coach(self):
        self.assertEqual(gp.decide("should I train hard today?").band, gp.COACH)

    def test_chest_pain_refers_out(self):
        decision = gp.decide("I have chest pain after intervals")
        self.assertEqual(decision.band, gp.REFER_OUT)
        self.assertEqual(decision.matched, "chest pain")
        self.assertIn("medical help", decision.line)

    def test_sharp_pain_is_care(self):
        decision = gp.decide("sharp pain in my knee when I squat")
        self.assertEqual(decision.band, gp.COACH_WITH_CARE)

    def test_guidance_only_mode_marks_body_related_as_care(self):
        decision = gp.decide("my shoulder is sore", guidance_only_mode=True)
        self.assertEqual(decision.band, gp.COACH_WITH_CARE)

    def test_should_remind_on_ordinary_turn(self):
        self.assertFalse(gp.should_remind_on_ordinary_turn(0))
        self.assertTrue(gp.should_remind_on_ordinary_turn(12))
        self.assertFalse(gp.should_remind_on_ordinary_turn(13))


if __name__ == "__main__":
    unittest.main()
