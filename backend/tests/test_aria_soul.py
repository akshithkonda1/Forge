"""ARIA soul rails on the coach_context counterpart. Style cannot override them."""

from __future__ import annotations

import json
import unittest

import _bootstrap  # noqa: F401

from services import coach_context  # noqa: E402


class AriaSoulTests(unittest.TestCase):
    def test_rails_match_lifestyle_coach(self):
        blob = " ".join(coach_context.ARIA_SOUL_RAILS).lower()
        self.assertEqual(coach_context.ARIA_SOUL_VERSION, "1")
        self.assertIn("not a doctor", blob)
        self.assertIn("never say recovery", blob)
        self.assertIn("never diagnose", blob)
        self.assertIn("never shame", blob)
        directive = coach_context.soul_directive("Drill Sergeant")
        self.assertIn("soul v1", directive)
        self.assertFalse(coach_context.soul_breaks_rails(directive))

    def test_snarky_soul_cannot_break_rails(self):
        attempted = (
            "You failed the set. Shame on you. Time for recovery. "
            "I diagnose overtraining and prescribe rest."
        )
        spoken = coach_context.soul_sanitize(attempted)
        self.assertFalse(coach_context.soul_breaks_rails(spoken), spoken)
        low = spoken.lower()
        self.assertNotIn("recovery", low)
        self.assertNotIn("you failed", low)
        self.assertNotIn("shame on you", low)
        self.assertNotIn("diagnos", low)
        self.assertNotIn("prescribe", low)

    def test_prompt_block_carries_soul_and_keeps_bedrock_off(self):
        block = json.loads(coach_context.context_to_prompt_block({}))
        soul = block["ariaSoul"]
        self.assertEqual(soul["version"], "1")
        self.assertIs(soul["bedrock"], False)
        self.assertIn("Lifestyle coach, not a doctor.", soul["rails"])
