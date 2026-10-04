"""Gate + dump rules for Scout. No network."""

from __future__ import annotations

import re
import unittest
from pathlib import Path

import _bootstrap  # noqa: F401

from backend.scout.gate import (
    ACTION_911,
    ACTION_988,
    CLIENT_EVIDENCE_CHARS,
    SCOUT_SELF_HARM_INTENT_LINE,
    SCOUT_SELF_HARM_THOUGHTS_LINE,
    SCOUT_STRESS_LINE,
    TIER_EMERGENCY,
    TIER_SELF_HARM_INTENT,
    TIER_SELF_HARM_THOUGHTS,
    TIER_STRESS,
    TIER_URGENT,
    emergency_phrases,
    evaluate,
    from_handoff,
    with_safety,
)
from backend.scout.retention import keyword_cache_key, working_set

REPO = Path(__file__).resolve().parents[2]
SWIFT_EVIDENCE = (
    REPO
    / "ForgeSwift"
    / "ForgeCore"
    / "Sources"
    / "ForgeCore"
    / "Intelligence"
    / "AriaWebEvidence.swift"
)
_SWIFT_MAX_RE = re.compile(r"static let maxEvidenceChars\s*=\s*(\d+)")


def _digits(text: str) -> set[str]:
    return set(re.findall(r"\d+", text or ""))


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
            self.assertIn(decision.reason, ("health", "safety"), prompt)
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

    def test_ambiguous_words_alone_stay_off(self) -> None:
        for prompt in (
            "I'm back from work",
            "hot take",
            "what a period of my life",
            "cold brew is great",
        ):
            decision = evaluate(prompt)
            self.assertFalse(decision.activate, prompt)
            self.assertIsNone(decision.safety, prompt)

    def test_ambiguous_words_activate_when_paired(self) -> None:
        back = evaluate("my back hurts")
        self.assertTrue(back.activate)
        self.assertEqual(back.reason, "health")
        iron = evaluate("iron supplement")
        self.assertTrue(iron.activate)
        self.assertEqual(iron.reason, "health")
        hot = evaluate("is it too hot to run")
        self.assertTrue(hot.activate)

    def test_ordinary_health_has_no_safety_line(self) -> None:
        decision = evaluate("I have a fever")
        self.assertTrue(decision.activate)
        self.assertIsNone(decision.safety)
        self.assertEqual(decision.tier, "none")

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


class SafetyTierTests(unittest.TestCase):
    def _tier(self, prompt: str):
        decision = evaluate(prompt)
        self.assertTrue(decision.activate, prompt)
        self.assertEqual(decision.reason, "safety", prompt)
        self.assertTrue(decision.safety, prompt)
        self.assertTrue(decision.safety.startswith(decision.safety.split(".")[0]), prompt)
        self.assertLessEqual(len(decision.safety), CLIENT_EVIDENCE_CHARS, prompt)
        low = decision.safety.lower()
        self.assertNotIn("recovery", low, prompt)
        self.assertNotIn("diagnos", low, prompt)
        self.assertNotIn("treat", low, prompt)
        self.assertNotIn("cure", low, prompt)
        extra = _digits(decision.safety) - {"911", "988"}
        self.assertEqual(extra, set(), prompt)
        return decision

    def test_emergency_opens_with_911_and_names_the_symptom(self) -> None:
        decision = self._tier("Look up chest pain, I think I'm having a heart attack.")
        self.assertEqual(decision.tier, TIER_EMERGENCY)
        self.assertTrue(decision.search)
        self.assertTrue(decision.safety.startswith("Call 911 now."))
        self.assertIn("chest pain", decision.safety.lower())
        self.assertIn("911", decision.safety)
        self.assertNotIn("988", decision.safety)
        self.assertEqual(decision.actions, [ACTION_911])
        self.assertIn(ACTION_911, decision.as_dict()["actions"])
        assert decision.mission is not None
        self.assertIn("chest", decision.mission.terms)
        self.assertEqual(from_handoff("chest pain").tier, TIER_EMERGENCY)
        self.assertTrue(from_handoff("chest pain").safety.startswith("Call 911 now."))

    def test_emergency_examples_open_with_911(self) -> None:
        cases = (
            ("I can't breathe", "trouble breathing"),
            ("my face is drooping", "stroke"),
            ("I think I took an overdose", "overdose"),
            ("I passed out", "passing out"),
            ("he's having a seizure", "seizure"),
            ("I'm bleeding out", "bleeding"),
        )
        for prompt, needle in cases:
            decision = self._tier(prompt)
            self.assertEqual(decision.tier, TIER_EMERGENCY, prompt)
            self.assertTrue(decision.safety.startswith("Call 911 now."), prompt)
            self.assertIn(needle, decision.safety.lower(), prompt)
            self.assertIn(ACTION_911, decision.actions, prompt)
            self.assertNotIn("988", decision.safety, prompt)

    def test_self_harm_intent_opens_with_988_and_does_not_search(self) -> None:
        decision = self._tier("I want to die, my wife Priya left")
        self.assertEqual(decision.tier, TIER_SELF_HARM_INTENT)
        self.assertFalse(decision.search)
        self.assertIsNone(decision.mission)
        self.assertEqual(decision.safety, SCOUT_SELF_HARM_INTENT_LINE)
        self.assertTrue(decision.safety.startswith("Call or text 988"))
        self.assertIn("988", decision.safety)
        self.assertIn("911", decision.safety)
        self.assertEqual(decision.actions, [ACTION_988, ACTION_911])
        self.assertEqual(from_handoff("I want to die").tier, TIER_SELF_HARM_INTENT)

    def test_self_harm_thoughts_offer_988_without_911(self) -> None:
        decision = self._tier("I don't want to be here")
        self.assertEqual(decision.tier, TIER_SELF_HARM_THOUGHTS)
        self.assertFalse(decision.search)
        self.assertIsNone(decision.mission)
        self.assertEqual(decision.safety, SCOUT_SELF_HARM_THOUGHTS_LINE)
        self.assertIn("988", decision.safety)
        self.assertNotIn("911", decision.safety)
        self.assertEqual(decision.actions, [ACTION_988])

    def test_urgent_fever_and_resolved_faint_and_chest(self) -> None:
        cases = (
            ("I've had a fever for several days", "fever"),
            ("I fainted earlier but I'm fine now", "faint"),
            ("chest tightness after a workout that went away", "arm"),
        )
        for prompt, warning in cases:
            decision = self._tier(prompt)
            self.assertEqual(decision.tier, TIER_URGENT, prompt)
            self.assertTrue(decision.search, prompt)
            self.assertTrue(
                decision.safety.startswith("Get it checked today by a doctor or urgent care."),
                prompt,
            )
            self.assertIn("Call 911 if", decision.safety, prompt)
            self.assertIn(warning, decision.safety.lower(), prompt)
            self.assertIn(ACTION_911, decision.actions, prompt)
            self.assertIn("911", decision.safety, prompt)
            self.assertNotIn("988", decision.safety, prompt)

    def test_stress_closes_with_988_anytime(self) -> None:
        decision = self._tier("I'm burned out and having panic attacks")
        self.assertEqual(decision.tier, TIER_STRESS)
        self.assertTrue(decision.search)
        self.assertEqual(decision.safety, SCOUT_STRESS_LINE)
        self.assertIn("988", decision.safety)
        self.assertNotIn("911", decision.safety)
        self.assertEqual(decision.actions, [ACTION_988])

    def test_safety_line_leads_and_survives_the_client_clip(self) -> None:
        long = "Fever is a body temperature above normal. " * 20
        line = evaluate("I have chest pain").safety
        answer = with_safety(long, line)
        self.assertTrue(answer.startswith(line))
        self.assertLessEqual(len(answer), CLIENT_EVIDENCE_CHARS)
        self.assertEqual(with_safety("", SCOUT_SELF_HARM_THOUGHTS_LINE), SCOUT_SELF_HARM_THOUGHTS_LINE)

    def test_every_guidance_emergency_phrase_is_emergency_tier(self) -> None:
        phrases = emergency_phrases()
        self.assertGreaterEqual(len(phrases), 20)
        for phrase in phrases:
            decision = evaluate(phrase)
            self.assertEqual(decision.tier, TIER_EMERGENCY, phrase)
            self.assertTrue(decision.safety.startswith("Call 911 now."), phrase)
            self.assertIn(ACTION_911, decision.actions, phrase)

    def test_chat_assess_keeps_existing_988_and_does_not_use_scout_extras(self) -> None:
        from aria_core import guidance

        assessed = guidance.assess("I don't want to be here")
        self.assertEqual(assessed.prose, guidance._CRISIS_LINE)
        self.assertEqual(guidance.classify_band("overdose"), guidance.COACH)
        self.assertEqual(guidance.classify_band("heavy bleeding"), guidance.COACH)


class ClipLimitLockTests(unittest.TestCase):
    def test_client_clip_limit_matches_swift_and_simrunner(self) -> None:
        from backend.ai.simrunner.aria_simrunner import web_research

        text = SWIFT_EVIDENCE.read_text(encoding="utf-8")
        match = _SWIFT_MAX_RE.search(text)
        self.assertIsNotNone(match, f"maxEvidenceChars missing in {SWIFT_EVIDENCE}")
        swift_limit = int(match.group(1))
        self.assertEqual(CLIENT_EVIDENCE_CHARS, 420)
        self.assertEqual(swift_limit, CLIENT_EVIDENCE_CHARS)
        self.assertEqual(web_research._MAX_EVIDENCE_CHARS, CLIENT_EVIDENCE_CHARS)


if __name__ == "__main__":
    unittest.main()
