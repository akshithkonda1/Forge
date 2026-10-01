"""Gate + dump rules for Scout. No network."""

from __future__ import annotations

import unittest

from backend.scout.gate import evaluate
from backend.scout.retention import keyword_cache_key, working_set


class GateTests(unittest.TestCase):
    def test_lookup_activates_and_scrubs(self) -> None:
        decision = evaluate(
            "Look up what a cardiac thoracotomy is. I'm 34 and my wife Priya asked."
        )
        self.assertTrue(decision.activate)
        self.assertEqual(decision.reason, "lookup")
        assert decision.mission is not None
        self.assertNotIn("priya", decision.mission.question)
        self.assertNotIn("34", decision.mission.question)
        self.assertIn("cardiac", decision.mission.terms)
        self.assertIn("thoracotomy", decision.mission.terms)
        self.assertFalse(decision.mission.retain)

    def test_coaching_stays_off(self) -> None:
        decision = evaluate("Should I train today? I slept badly.")
        self.assertFalse(decision.activate)
        self.assertIsNone(decision.mission)

    def test_explicit_lookup_beats_session_words(self) -> None:
        decision = evaluate("Look up whether zone 2 is safe the day after a bad night of sleep.")
        self.assertTrue(decision.activate)
        assert decision.mission is not None
        self.assertIn("zone", decision.mission.question)

    def test_safety_never_activates(self) -> None:
        decision = evaluate("Look up chest pain, I think I'm having a heart attack.")
        self.assertFalse(decision.activate)
        self.assertEqual(decision.reason, "safety")

    def test_working_set_dumps(self) -> None:
        with working_set() as held:
            held.mission = "cardiac thoracotomy"
            held.pages.append("page text that must not survive")
            self.assertEqual(len(held.pages), 1)
        self.assertEqual(held.mission, "")
        self.assertEqual(held.pages, [])

    def test_cache_key_is_not_the_query(self) -> None:
        key = keyword_cache_key("cardiac thoracotomy")
        self.assertNotIn("cardiac", key)
        self.assertEqual(key, keyword_cache_key("  Cardiac   thoracotomy "))


if __name__ == "__main__":
    unittest.main()
