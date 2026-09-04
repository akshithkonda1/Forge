"""Regression: the evaluator must not score correct hold/recovery advice as a
directional violation. Substring matching used to read "no high-intensity work"
as recommending high intensity, and the " pr" fragment matched "priority" —
fabricating mission-critical failures on good advice.
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner.aria_engine import ARIAResponse  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_evaluator import (  # noqa: E402
    _HIGH_INTENSITY, _INCREASE_LOAD, _advocates, evaluate,
)
from backend.ai.simrunner.backend_simulator.behavior_engine import DailyRecord  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import ARIAContext  # noqa: E402


def _context(readiness=45, hrv=48, acwr=1.0, sleep_debt=0.0, hrv_trend="stable"):
    today = DailyRecord(
        date="2026-01-15", total_sleep_hours=7.0, deep_sleep_minutes=70, rem_sleep_minutes=90,
        sleep_score=70, hrv=hrv, resting_hr=58, readiness_score=readiness, steps=6000,
        active_calories=400, workout_logged=False, workout_type=None,
        workout_duration_minutes=None, workout_intensity=None, training_load=0.0,
        acwr=acwr, notes=None,
    )
    return ARIAContext(
        user_name="Test", chronotype="bear", experience_level="intermediate",
        coaching_style="balanced", occupation="tester", life_season="maintenance",
        today=today, hrv_7d_avg=float(hrv), hrv_7d_trend=hrv_trend, sleep_debt_7d_hours=sleep_debt,
        readiness_7d_avg=float(readiness), readiness_trend="stable", acwr=acwr,
        training_streak=0, days_since_last_workout=1, target_sleep_hours=8.0, target_wake_hour=7.0,
        is_overtrained=acwr > 1.4, is_sleep_deprived=sleep_debt > 4.0,
        has_notable_event=False, notable_event_note=None, history=[today],
    )


def _response(prose, recommendation):
    return ARIAResponse(
        prose_summary=prose, recommendation=recommendation, confidence=0.7,
        used_context=True, model_used="opus", query_type="training_decision",
        latency_ms=500.0, raw={}, model_class="opus",
    )


class AdvocatesTests(unittest.TestCase):
    def test_negated_phrases_are_not_advocated(self):
        self.assertFalse(_advocates("keep it easy — zone 2, no high-intensity work.", _HIGH_INTENSITY))
        self.assertFalse(_advocates("recovery is the priority today.", _HIGH_INTENSITY))
        self.assertFalse(_advocates("hold volume steady; don't add load.", _INCREASE_LOAD))

    def test_genuine_recommendations_are_advocated(self):
        self.assertTrue(_advocates("go hard: heavy strength today.", _HIGH_INTENSITY))
        self.assertTrue(_advocates("add load and build volume this week.", _INCREASE_LOAD))


class DirectionalScoringTests(unittest.TestCase):
    def test_correct_recovery_advice_is_not_a_directional_failure(self):
        ctx = _context(readiness=45)
        resp = _response(
            "Recovery is the priority today — keep it easy, Zone 2 or mobility, no high-intensity work.",
            "Zone 2 cardio only; reassess tomorrow.")
        result = evaluate(0, "Should I train today?", 1, ctx, resp)
        self.assertGreater(result.scores.directional_correctness, 0.0)
        self.assertFalse(any("recommended high-intensity" in f for f in result.failures))

    def test_genuine_violation_is_still_caught(self):
        ctx = _context(readiness=45)
        resp = _response(
            "Let's go hard today — heavy strength, push for a PR.",
            "Train at high intensity today.")
        result = evaluate(0, "Should I train today?", 1, ctx, resp)
        self.assertEqual(result.scores.directional_correctness, 0.0)
        self.assertTrue(any("high-intensity" in f for f in result.failures))


if __name__ == "__main__":
    unittest.main()
