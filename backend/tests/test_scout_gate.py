"""Gate + dump rules for Scout. No network."""

from __future__ import annotations

import json
import os
import re
import unittest
from pathlib import Path
from unittest.mock import patch

import _bootstrap  # noqa: F401

from backend.scout.gate import (
    ACTION_911,
    ACTION_988,
    CLIENT_EVIDENCE_CHARS,
    SCOUT_SELF_HARM_INTENT_LINE,
    SCOUT_SELF_HARM_THOUGHTS_LINE,
    SCOUT_STRESS_LINE,
    TIER_EMERGENCY,
    TIER_NONE,
    TIER_SELF_HARM_INTENT,
    TIER_SELF_HARM_THOUGHTS,
    TIER_STRESS,
    TIER_URGENT,
    emergency_phrases,
    evaluate,
    from_handoff,
    scout_search_query,
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


# Chat vs Scout band for post-lift chest pain is not decided on this branch.
_PENDING_CHEST_AFTER_BENCH = "chest pain after bench"
_PENDING_CHEST_REASON = (
    "pending owner decision: chat vs Scout band for post-lift chest pain"
)

_URGENT_EXAMPLES = (
    "I've had a fever for several days",
    "chest tightness after a workout that went away",
)
_STRESS_EXAMPLES = (
    "having a panic attack",
    "I'm burned out and there's no point",
    "I'm burned out and having panic attacks",
)
_SELF_HARM_EXAMPLES = (
    "I feel suicidal and want to die",
    "I don't want to be here",
)
_SAFETY_EXAMPLES = (
    "Look up chest pain, I think I'm having a heart attack.",
    "I can't breathe",
    "my face is drooping",
    "I think I took an overdose",
    "I passed out",
    "he's having a seizure",
    "I'm bleeding out",
    "took too many of my oxycodone",
    "I fainted during my run, I'm fine now",
    "I fainted earlier but I'm fine now",
    *_URGENT_EXAMPLES,
    *_STRESS_EXAMPLES,
)


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

    def _assert_fixed_query(self, decision, prompt: str) -> None:
        if not decision.search:
            self.assertIsNone(decision.mission, prompt)
            return
        from aria_core import guidance

        found = guidance.scout_safety(prompt)
        self.assertIsNotNone(found)
        question, terms = scout_search_query(found.kind)
        assert decision.mission is not None
        self.assertEqual(decision.mission.question, question, prompt)
        self.assertEqual(decision.mission.terms, list(terms), prompt)
        user_tokens = {
            part.lower()
            for part in re.findall(r"[a-z0-9']+", prompt.lower())
            if part.lower() not in set(terms)
        }
        leaked = [token for token in user_tokens if token in decision.mission.terms]
        self.assertEqual(leaked, [], prompt)

    def test_emergency_opens_with_911_without_a_symptom_label(self) -> None:
        decision = self._tier("Look up chest pain, I think I'm having a heart attack.")
        self.assertEqual(decision.tier, TIER_EMERGENCY)
        self.assertTrue(decision.search)
        self.assertTrue(decision.safety.startswith("Call 911 now."))
        self.assertIn("This needs emergency help right away.", decision.safety)
        self.assertNotIn("Chest pain needs emergency", decision.safety)
        self.assertIn("911", decision.safety)
        self.assertNotIn("988", decision.safety)
        self.assertEqual(decision.actions, [ACTION_911])
        self.assertIn(ACTION_911, decision.as_dict()["actions"])
        self._assert_fixed_query(decision, "Look up chest pain, I think I'm having a heart attack.")
        self.assertEqual(from_handoff("chest pain").tier, TIER_EMERGENCY)
        self.assertTrue(from_handoff("chest pain").safety.startswith("Call 911 now."))

    def test_emergency_examples_open_with_911(self) -> None:
        cases = (
            "I can't breathe",
            "my face is drooping",
            "I think I took an overdose",
            "I passed out",
            "he's having a seizure",
            "I'm bleeding out",
        )
        from aria_core import guidance

        for prompt in cases:
            decision = self._tier(prompt)
            self.assertEqual(decision.tier, TIER_EMERGENCY, prompt)
            self.assertTrue(decision.safety.startswith("Call 911 now."), prompt)
            kind = guidance._emergency_kind(guidance.normalize_message(prompt))
            if kind == "faint":
                self.assertEqual(decision.safety, guidance.scout_emergency_line(prompt), prompt)
            else:
                self.assertIn("This needs emergency help right away.", decision.safety, prompt)
            self.assertIn(ACTION_911, decision.actions, prompt)
            self.assertNotIn("988", decision.safety, prompt)
            self._assert_fixed_query(decision, prompt)

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
        self.assertTrue(decision.safety_lock)
        self.assertEqual(from_handoff("I want to die").tier, TIER_SELF_HARM_INTENT)

    def test_self_harm_thoughts_offer_988_without_911(self) -> None:
        decision = self._tier("I don't want to be here")
        self.assertEqual(decision.tier, TIER_SELF_HARM_THOUGHTS)
        self.assertFalse(decision.search)
        self.assertIsNone(decision.mission)
        self.assertEqual(decision.safety, SCOUT_SELF_HARM_THOUGHTS_LINE)
        self.assertTrue(decision.safety.startswith("I'm really glad you told me."))
        self.assertIn("988", decision.safety)
        self.assertNotIn("911", decision.safety)
        self.assertEqual(decision.actions, [ACTION_988])
        self.assertTrue(decision.safety_lock)

    def test_urgent_fever_and_resolved_chest(self) -> None:
        cases = (
            ("I've had a fever for several days", "breathing gets hard"),
            ("chest tightness after a workout that went away", "arm or jaw"),
        )
        for prompt, warning in cases:
            decision = self._tier(prompt)
            self.assertEqual(decision.tier, TIER_URGENT, prompt)
            self.assertTrue(decision.search, prompt)
            self.assertTrue(
                decision.safety.startswith(
                    "Let's get this checked today by a doctor or urgent care."
                ),
                prompt,
            )
            self.assertIn("Call 911 if", decision.safety, prompt)
            self.assertIn(warning, decision.safety.lower(), prompt)
            self.assertIn(ACTION_911, decision.actions, prompt)
            self.assertIn("911", decision.safety, prompt)
            self.assertNotIn("988", decision.safety, prompt)
            self.assertFalse(decision.safety_lock, prompt)
            self._assert_fixed_query(decision, prompt)

    def test_fainted_during_run_is_emergency_when_chat_says_emergency(self) -> None:
        from aria_core import guidance

        rows = (
            (
                "I fainted earlier but I'm fine now",
                guidance._EMERGENCY_FAINT_RESOLVED,
            ),
            (
                "I fainted during my run, I'm fine now",
                guidance._EMERGENCY_FAINT_RESOLVED_TRAINING,
            ),
            (
                "I fainted while running",
                guidance._EMERGENCY_FAINT_RESOLVED_TRAINING,
            ),
            (
                "passed out after lifting",
                guidance._EMERGENCY_FAINT_RESOLVED_TRAINING,
            ),
            (
                "I passed out",
                f"{guidance._EMERGENCY_OPEN} {guidance._EMERGENCY_FAINT}",
            ),
        )
        for prompt, expected in rows:
            with self.subTest(prompt=prompt):
                self.assertEqual(guidance.classify_band(prompt), guidance.EMERGENCY)
                self.assertEqual(guidance.assess(prompt).prose, expected)
                self.assertEqual(guidance.scout_emergency_line(prompt), expected)
                decision = self._tier(prompt)
                self.assertEqual(decision.tier, TIER_EMERGENCY, prompt)
                self.assertNotEqual(decision.tier, TIER_URGENT, prompt)
                self.assertEqual(decision.safety, expected, prompt)
                self._assert_fixed_query(decision, prompt)

    def test_panic_attack_appends_softened_988_and_does_not_lock(self) -> None:
        prompt = "having a panic attack"
        decision = self._tier(prompt)
        self.assertEqual(decision.tier, TIER_STRESS)
        self.assertEqual(decision.safety, SCOUT_STRESS_LINE)
        self.assertIn("988", decision.safety)
        self.assertNotIn("911", decision.safety)
        self.assertEqual(decision.actions, [ACTION_988])
        self.assertFalse(decision.safety_lock)
        self.assertFalse(decision.as_dict().get("safety_lock"))
        coaching = "Sit down and slow your breathing until it evens out."
        composed = with_safety(coaching, decision.safety, lead=False)
        self.assertTrue(composed.endswith(decision.safety))
        self.assertGreater(composed.find(decision.safety), composed.find("Sit down"))
        self.assertFalse(composed.startswith(decision.safety))
        self._assert_fixed_query(decision, prompt)

    def test_bare_stress_does_not_wake_scout(self) -> None:
        from services import aria_engine

        for prompt in (
            "stressed about my deadline",
            "stressed about the Acme launch",
        ):
            with self.subTest(prompt=prompt):
                decision = evaluate(prompt)
                self.assertFalse(decision.activate, prompt)
                self.assertEqual(decision.tier, TIER_NONE, prompt)
                self.assertIsNone(decision.safety, prompt)
                self.assertEqual(decision.actions, [], prompt)
                self.assertIsNone(decision.mission, prompt)
                self.assertFalse(decision.safety_lock, prompt)
                self.assertNotIn("988", json.dumps(decision.as_dict()), prompt)
                resp = aria_engine.generate_response(prompt, aria_engine.ARIAContext())
                self.assertFalse(resp.get("safety_lock"), prompt)
                spoken = f"{resp.get('prose_summary') or ''} {resp.get('message') or ''}"
                self.assertNotIn("988", spoken, prompt)
                extra = _digits(spoken)
                self.assertEqual(extra, set(), prompt)

    def test_safety_line_leads_and_survives_the_client_clip(self) -> None:
        long = "Fever is a body temperature above normal. " * 20
        line = evaluate("I have chest pain").safety
        answer = with_safety(long, line)
        self.assertTrue(answer.startswith(line))
        self.assertLessEqual(len(answer), CLIENT_EVIDENCE_CHARS)
        self.assertEqual(with_safety("", SCOUT_SELF_HARM_THOUGHTS_LINE), SCOUT_SELF_HARM_THOUGHTS_LINE)

    def test_every_guidance_emergency_phrase_is_emergency_tier(self) -> None:
        from aria_core import guidance

        phrases = emergency_phrases()
        self.assertGreaterEqual(len(phrases), 20)
        for phrase in phrases:
            decision = evaluate(phrase)
            self.assertEqual(decision.tier, TIER_EMERGENCY, phrase)
            self.assertTrue(decision.safety.startswith("Call 911 now."), phrase)
            kind = guidance._emergency_kind(guidance.normalize_message(phrase))
            if kind == "faint":
                self.assertEqual(decision.safety, guidance.scout_emergency_line(phrase), phrase)
            else:
                self.assertIn("This needs emergency help right away.", decision.safety, phrase)
            self.assertIn(ACTION_911, decision.actions, phrase)
            self._assert_fixed_query(decision, phrase)

    def test_chat_and_scout_agree_on_emergency_parity_table(self) -> None:
        from aria_core import guidance
        from aria_core.speak_guard import spoken_ban_hits
        from backend.ai.aria_chat.session import run_turn

        faint_message = {
            "I fainted earlier but I'm fine now": guidance._EMERGENCY_FAINT_RESOLVED,
            "I fainted during my run, I'm fine now": guidance._EMERGENCY_FAINT_RESOLVED_TRAINING,
            "I fainted while running": guidance._EMERGENCY_FAINT_RESOLVED_TRAINING,
            "passed out after lifting": guidance._EMERGENCY_FAINT_RESOLVED_TRAINING,
        }
        first_aid_phrases = (
            "how do I do CPR?",
            "what do I do if someone is choking",
            "how to stop severe bleeding",
            "what do I do if someone is unresponsive but breathing",
        )
        refer_out_phrases = (
            "do I have diabetes?",
            "do I have sleep apnea?",
            "should I up my dose",
        )
        # phrase, expected Dummy /ai/chat message (None = coach/stress: no 911/988 line)
        rows: list[tuple[str, str | None]] = []
        for phrase in emergency_phrases():
            assessed = guidance.assess(phrase)
            rows.append((phrase, assessed.message if assessed is not None else None))
        for phrase, expected in faint_message.items():
            rows.append((phrase, expected))
        for phrase in first_aid_phrases:
            assessed = guidance.assess(phrase)
            rows.append((phrase, assessed.message if assessed is not None else None))
        for phrase in refer_out_phrases:
            assessed = guidance.assess(phrase)
            rows.append((phrase, assessed.message if assessed is not None else None))
        for phrase in _SELF_HARM_EXAMPLES:
            assessed = guidance.assess(phrase)
            rows.append((phrase, assessed.message if assessed is not None else guidance._CRISIS_LINE))
        for phrase in (*_URGENT_EXAMPLES, *_STRESS_EXAMPLES):
            assessed = guidance.assess(phrase)
            rows.append((phrase, assessed.message if assessed is not None else None))
        rows.append((_PENDING_CHEST_AFTER_BENCH, None))
        self.assertGreaterEqual(len(rows), 20)

        def boom(*_args, **_kwargs):
            raise AssertionError("live model called")

        def _route(phrase: str) -> dict:
            from routes.aria import handle_post_ai_chat

            result = handle_post_ai_chat(
                {"message": phrase},
                user_id=f"parity-{abs(hash(phrase)) % 10**8}",
            )
            body = result.get("body")
            if isinstance(body, str):
                body = json.loads(body)
            return body if isinstance(body, dict) else {}

        previous = os.environ.get("ARIA_BEDROCK_ENABLED")
        os.environ["ARIA_BEDROCK_ENABLED"] = "true"
        try:
            with patch(
                "services.aria_engine._default_converse", boom
            ), patch(
                "aria_core.aria_engine._default_converse", boom
            ), patch(
                "services.aria_swarm.run_swarm", lambda *_a, **_k: {}
            ):
                for phrase, expected in rows:
                    with self.subTest(phrase=phrase):
                        if phrase == _PENDING_CHEST_AFTER_BENCH:
                            self.skipTest(_PENDING_CHEST_REASON)
                        chat = guidance.classify_band(phrase)
                        scout = guidance.scout_safety(phrase)
                        dummy = run_turn(
                            phrase,
                            persist_log=False,
                            memory_enabled=False,
                        )
                        spoken = str(dummy.get("message") or "")
                        routed = _route(phrase)
                        route_spoken = str(routed.get("message") or "")
                        if chat == guidance.EMERGENCY:
                            self.assertIsNotNone(scout, phrase)
                            if phrase in _SELF_HARM_EXAMPLES:
                                self.assertIn(
                                    scout.tier,
                                    (TIER_SELF_HARM_INTENT, TIER_SELF_HARM_THOUGHTS),
                                    phrase,
                                )
                            else:
                                self.assertEqual(scout.tier, TIER_EMERGENCY, phrase)
                                self.assertNotEqual(scout.tier, TIER_URGENT, phrase)
                            self.assertTrue(
                                spoken.startswith("Call 911 now")
                                or "988" in spoken,
                                spoken,
                            )
                        if expected is not None:
                            if phrase in first_aid_phrases:
                                self.assertEqual(
                                    " ".join(spoken.split()),
                                    " ".join(expected.split()),
                                    phrase,
                                )
                            else:
                                self.assertEqual(spoken, expected, phrase)
                        if phrase in faint_message:
                            self.assertEqual(spoken, faint_message[phrase], phrase)
                        if phrase in _SELF_HARM_EXAMPLES:
                            self.assertIn("988", spoken, phrase)
                            self.assertEqual(spoken, guidance._CRISIS_LINE, phrase)
                        if phrase in _STRESS_EXAMPLES:
                            self.assertNotIn("988", spoken, phrase)
                            self.assertEqual(_digits(spoken), set(), phrase)
                        if phrase in first_aid_phrases:
                            self.assertEqual(chat, guidance.FIRST_AID, phrase)
                            self.assertEqual(routed.get("guidance_band"), guidance.FIRST_AID, phrase)
                            if "unresponsive but breathing" in phrase:
                                self.assertIn("onto their side", spoken, spoken)
                                self.assertIn("onto their side", route_spoken, route_spoken)
                        if phrase in refer_out_phrases:
                            self.assertEqual(chat, guidance.REFER_OUT, phrase)
                            self.assertEqual(routed.get("guidance_band"), guidance.REFER_OUT, phrase)
                            if "diabetes" in phrase:
                                self.assertIn(
                                    "a doctor can check it properly", spoken, spoken
                                )
                                self.assertIn(
                                    "a doctor can check it properly",
                                    route_spoken,
                                    route_spoken,
                                )
                        self.assertEqual(spoken_ban_hits(spoken), (), spoken)
                        if chat != guidance.FIRST_AID:
                            self.assertEqual(
                                guidance.extra_speak_digits(spoken, phrase),
                                frozenset(),
                                spoken,
                            )
        finally:
            if previous is None:
                os.environ.pop("ARIA_BEDROCK_ENABLED", None)
            else:
                os.environ["ARIA_BEDROCK_ENABLED"] = previous

    def test_every_safety_example_uses_a_fixed_query(self) -> None:
        for prompt in _SAFETY_EXAMPLES:
            with self.subTest(prompt=prompt):
                decision = evaluate(prompt)
                self.assertEqual(decision.reason, "safety", prompt)
                self._assert_fixed_query(decision, prompt)
                if "oxycodone" in prompt.lower():
                    assert decision.mission is not None
                    self.assertNotIn("oxycodone", decision.mission.question)
                    self.assertNotIn("oxycodone", decision.mission.terms)

    def test_chat_assess_keeps_existing_988_and_does_not_use_scout_extras(self) -> None:
        from aria_core import guidance

        assessed = guidance.assess("I don't want to be here")
        self.assertEqual(assessed.prose, guidance._CRISIS_LINE)
        self.assertEqual(guidance.classify_band("overdose"), guidance.EMERGENCY)
        self.assertEqual(guidance.classify_band("heavy bleeding"), guidance.COACH)
        self.assertNotEqual(
            guidance.classify_band("heavy bleeding on my period"), guidance.EMERGENCY
        )


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
