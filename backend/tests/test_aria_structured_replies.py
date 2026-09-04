"""ARIA chat replies read like a good assistant answer: short labeled sections
(What I notice / One next step / optional Why), not a metric dump. ARIA is a
lifestyle coach, not a clinician. Voice mode stays a single spoken line and the
precise numbers live on the card.
"""
import unittest

import _bootstrap  # noqa: F401

from services import aria_engine as A  # noqa: E402

REC = {"context": {
    "sleep": {"durationMinutes": 360, "deepMinutes": 45, "remMinutes": 70, "efficiency": 0.82, "hrv": 44, "nightsAvailable": 14},
    "readiness": {"hrv7DayTrend": -14, "hrv30DayBaseline": 60, "recoveryScore": 47, "hrvDaysAvailable": 7},
    "training": {"weeklyLoadScore": 88, "hoursSinceLastWorkout": 16}}}
SUM = {"context": {"progress": {"workoutsCompleted30d": 18, "newPersonalRecords": 3, "trainingLoadTrend": "rising"}}}
INS = {"context": {
    "sleep": {"durationMinutes": 400, "deepMinutes": 90, "remMinutes": 95, "efficiency": 0.9, "hrv": 60, "nightsAvailable": 10},
    "readiness": {"hrv7DayTrend": 2, "hrv30DayBaseline": 58, "recoveryScore": 75, "hrvDaysAvailable": 10}}}


class StructuredReplyTests(unittest.TestCase):
    def _resp(self, body, q, **kw):
        return A.generate_response(q, A.ARIAContext.from_payload(body), **kw)

    def test_recommendation_has_labeled_sections(self):
        r = self._resp(REC, "should I train hard today?")
        self.assertEqual(r["response_type"], "recommendation")
        self.assertIn("What I notice", r["message"])
        self.assertIn("One next step", r["message"])

    def test_summary_and_insight_are_structured(self):
        s = self._resp(SUM, "how is my progress this month?")
        self.assertEqual(s["response_type"], "summary")
        self.assertIn("What I notice", s["message"])
        self.assertIn("One next step", s["message"])

        i = self._resp(INS, "how did I sleep?")
        self.assertEqual(i["response_type"], "insight")
        self.assertIn("One next step", i["message"])

    def test_clarification_is_structured(self):
        c = self._resp({"context": {"profile": {"primaryGoal": "lose-fat"}}}, "what should I do?")
        self.assertEqual(c["response_type"], "clarification")
        self.assertIn("What I notice", c["message"])
        self.assertIn("One next step", c["message"])

    def test_voice_mode_is_a_single_line_without_labels(self):
        r = self._resp(REC, "should I train hard today?", voice_mode=True)
        self.assertEqual(r["message"], r["prose_summary"])
        self.assertNotIn("What I notice", r["message"])
        self.assertIsNone(r["card"])

    def test_lifestyle_coach_not_a_doctor(self):
        low = self._resp(REC, "should I train hard today?")["message"].lower()
        for word in ("diagnos", "prescrib", "disease", "medical condition"):
            self.assertNotIn(word, low)


if __name__ == "__main__":
    unittest.main()
