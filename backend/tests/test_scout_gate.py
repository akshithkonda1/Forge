"""Gate + dump rules for Scout. No network."""

from __future__ import annotations

import unittest

from backend.scout.gate import (
    CLIENT_EVIDENCE_CHARS,
    EMERGENCY_LINE,
    SELF_HARM_LINE,
    evaluate,
    from_handoff,
    with_safety,
)
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

    def test_health_without_a_cue_activates(self) -> None:
        for prompt, term in (("I have a fever", "fever"), ("my knee hurts after running", "knee"),
                             ("is it too hot to run today", "hot"), ("creatine", "creatine")):
            decision = evaluate(prompt)
            self.assertTrue(decision.activate, prompt)
            self.assertEqual(decision.reason, "health")
            assert decision.mission is not None
            self.assertIn(term, decision.mission.terms)
            self.assertEqual(decision.mission.prefer, ["pubmed", "medlineplus"])

    def test_own_data_stays_off(self) -> None:
        for prompt in ("how did I sleep", "my hrv is low", "what's my readiness"):
            self.assertFalse(evaluate(prompt).activate, prompt)
        self.assertTrue(evaluate("what does research say about hrv").activate)

    def test_non_health_chat_stays_off(self) -> None:
        for prompt in ("tell me a joke", "hello aria", "good morning"):
            self.assertFalse(evaluate(prompt).activate, prompt)
        self.assertTrue(evaluate("what is the capital of france").activate)

    def test_one_word_handoff_needs_health(self) -> None:
        self.assertTrue(from_handoff("fever").activate)
        self.assertFalse(from_handoff("python").activate)
        self.assertTrue(from_handoff("python release notes").activate)

    def test_emergency_is_researched_with_911_line(self) -> None:
        decision = evaluate("Look up chest pain, I think I'm having a heart attack.")
        self.assertTrue(decision.activate)
        self.assertEqual(decision.reason, "safety")
        self.assertEqual(decision.safety, EMERGENCY_LINE)
        assert decision.mission is not None
        self.assertIn("chest", decision.mission.terms)
        self.assertEqual(decision.as_dict()["safety"], EMERGENCY_LINE)
        self.assertEqual(from_handoff("chest pain").safety, EMERGENCY_LINE)

    def test_self_harm_is_never_searched_as_typed(self) -> None:
        decision = evaluate("I want to die, my wife Priya left")
        self.assertTrue(decision.activate)
        self.assertEqual(decision.safety, SELF_HARM_LINE)
        assert decision.mission is not None
        self.assertEqual(decision.mission.question, "suicidal thoughts crisis support")

    def test_safety_line_survives_the_client_clip(self) -> None:
        long = "Fever is a body temperature above normal. " * 20
        answer = with_safety(long, EMERGENCY_LINE)
        self.assertTrue(answer.endswith(EMERGENCY_LINE))
        self.assertLessEqual(len(answer), CLIENT_EVIDENCE_CHARS)
        self.assertEqual(with_safety("", SELF_HARM_LINE), SELF_HARM_LINE)

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
