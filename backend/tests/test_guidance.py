"""Tests for ARIA's medical-boundary guidance policy (services.guidance).

ARIA is a lifestyle coach, not a doctor. It provides general first-aid
*information* and pushes people to 911 in an emergency, but it never diagnoses a
condition or prescribes/adjusts medication. These tests pin every band.
"""

from __future__ import annotations

import json
import unittest

import _bootstrap  # noqa: F401

from services import guidance  # noqa: E402
from services import aria_engine  # noqa: E402


class BandClassificationTests(unittest.TestCase):
    def test_emergency_states(self):
        for msg in [
            "my friend collapsed and is not breathing",
            "he has no pulse",
            "she passed out and is unresponsive",
            "call 911 now",
            "I think he's having a heart attack",
        ]:
            self.assertEqual(guidance.classify_band(msg), guidance.EMERGENCY, msg)

    def test_self_harm_is_emergency(self):
        g = guidance.assess("I feel suicidal and want to die")
        self.assertEqual(g.band, guidance.EMERGENCY)
        self.assertIn("988", g.prose)
        self.assertTrue(g.wants_escalation)

    def test_first_aid_howto(self):
        for msg in [
            "how do I do CPR?",
            "what do I do if someone is choking",
            "how to stop severe bleeding",
        ]:
            self.assertEqual(guidance.classify_band(msg), guidance.FIRST_AID, msg)

    def test_diagnosis_requests_refer_out(self):
        for msg in [
            "do I have diabetes?",
            "diagnose me",
            "what's wrong with me",
            "could I have a blood clot",
        ]:
            self.assertEqual(guidance.classify_band(msg), guidance.REFER_OUT, msg)

    def test_prescription_requests_refer_out(self):
        for msg in [
            "should I increase my dose of metformin?",
            "what medication should I take",
            "should I stop taking my antidepressants",
            "what should I take for my headache",
        ]:
            self.assertEqual(guidance.classify_band(msg), guidance.REFER_OUT, msg)

    def test_normal_coaching_is_coach(self):
        for msg in [
            "should I train hard today?",
            "do I have enough protein in my diet",
            "how do I improve my 5k time",
            "what should I take for my long run",  # gear/fuel, not a symptom
        ]:
            self.assertEqual(guidance.classify_band(msg), guidance.COACH, msg)
        self.assertIsNone(guidance.assess("should I train hard today?"))

    def test_emergency_takes_precedence_over_diagnosis(self):
        # Phrased like a diagnosis question but describes acute danger.
        self.assertEqual(
            guidance.classify_band("is he having a heart attack, he's not breathing"),
            guidance.EMERGENCY,
        )


class GuidanceContentTests(unittest.TestCase):
    def test_first_aid_provides_cpr_steps_and_911(self):
        g = guidance.assess("how do I do CPR")
        self.assertEqual(g.band, guidance.FIRST_AID)
        self.assertIn("911", g.prose)
        self.assertIn("compress", g.prose.lower())
        self.assertIn("first-aid information", g.prose.lower())
        self.assertFalse(g.wants_escalation)

    def test_emergency_leads_with_911_and_escalates(self):
        g = guidance.assess("someone collapsed and isn't breathing")
        self.assertTrue(g.wants_escalation)
        self.assertIn("911", g.prose)
        self.assertIn("CPR", g.prose)  # relevant first-aid included

    def test_refer_out_declines_without_diagnosing(self):
        g = guidance.assess("do I have diabetes")
        low = g.prose.lower()
        self.assertIn("not a doctor", low)
        self.assertIn("clinician", low)
        for banned in ("you have", "you probably have", "i diagnose"):
            self.assertNotIn(banned, low)


class PrescriptiveDetectorTests(unittest.TestCase):
    def test_flags_dosing_and_diagnosis(self):
        self.assertTrue(guidance.contains_prescriptive_medical_language("take 200 mg of ibuprofen"))
        self.assertTrue(guidance.contains_prescriptive_medical_language("you probably have a blood clot"))
        self.assertTrue(guidance.contains_prescriptive_medical_language("I'd prescribe rest and antibiotics"))

    def test_ignores_lifestyle_imperatives(self):
        for ok in ["you should sleep more", "get some zone 2 today", "add a protein shake"]:
            self.assertFalse(guidance.contains_prescriptive_medical_language(ok), ok)

    def test_disclaimer_appended_once(self):
        out = guidance.append_clinician_disclaimer("Here's a plan.")
        self.assertIn("not a doctor", out)


class EngineWiringTests(unittest.TestCase):
    """generate_response short-circuits to the guardrail deterministically, and
    the live path never lets the model override it."""

    def _ctx(self):
        return aria_engine.ARIAContext.from_payload({"user_id": "u"})

    def test_generate_response_short_circuits(self):
        r = aria_engine.generate_response("how do I do CPR", self._ctx())
        self.assertEqual(r["guidance_band"], guidance.FIRST_AID)
        self.assertIn("911", r["message"])

    def test_emergency_sets_escalation_flag(self):
        r = aria_engine.generate_response("he collapsed and is not breathing", self._ctx())
        self.assertEqual(r["guidance_band"], guidance.EMERGENCY)
        self.assertTrue(r["emergency_escalation"])

    def test_live_path_does_not_call_model_on_guardrail(self):
        calls = []

        def fake_converse(model_id, system, user):
            calls.append(user)
            return '{"prose_summary": "model tried to answer"}'

        r = aria_engine.generate_response_live(
            "do I have diabetes", self._ctx(), converse=fake_converse
        )
        self.assertEqual(r["guidance_band"], guidance.REFER_OUT)
        self.assertEqual(calls, [])  # model never invoked on the hard line
        self.assertEqual(r["reasoning_source"], "deterministic")

    def test_live_path_softens_prescriptive_model_output(self):
        def fake_converse(model_id, system, user):
            return '{"prose_summary": "You should take 400 mg of ibuprofen every 6 hours."}'

        r = aria_engine.generate_response_live(
            "my knee is sore after running", self._ctx(), converse=fake_converse
        )
        self.assertTrue(r.get("safety_softened"))
        self.assertIn("not a doctor", r["message"].lower())


class ChatRouteWiringTests(unittest.TestCase):
    def test_chat_surfaces_guidance_band(self):
        from routes.aria import handle_post_ai_chat

        result = handle_post_ai_chat(
            {"message": "he collapsed and isn't breathing"}, user_id="safety-user"
        )
        self.assertEqual(result["statusCode"], 200)
        body = json.loads(result["body"])
        self.assertEqual(body["guidance_band"], guidance.EMERGENCY)
        self.assertTrue(body["emergency_escalation"])


if __name__ == "__main__":
    unittest.main()
