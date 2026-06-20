import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from backend.simrunner.aria_simrunner import query_router  # noqa: E402
from backend.simrunner.aria_simrunner.aria_engine import ARIAEngine, ARIAResponse  # noqa: E402
from backend.simrunner.aria_simrunner.aria_evaluator import (  # noqa: E402
    DimensionScores, evaluate, grade, tier_multiplier,
)
from backend.simrunner.aria_simrunner.determinism_checker import check_determinism  # noqa: E402
from backend.simrunner.backend_simulator.behavior_engine import DailyRecord  # noqa: E402
from backend.simrunner.backend_simulator.data_generator import ARIAContext  # noqa: E402


def make_record(readiness=70, hrv=55, acwr=1.0):
    return DailyRecord(
        date="2026-01-15", total_sleep_hours=7.5, deep_sleep_minutes=80, rem_sleep_minutes=95,
        sleep_score=80, hrv=hrv, resting_hr=55, readiness_score=readiness, steps=9000,
        active_calories=500, workout_logged=False, workout_type=None,
        workout_duration_minutes=None, workout_intensity=None, training_load=0.0,
        acwr=acwr, notes=None,
    )


def make_context(readiness=70, hrv=55, acwr=1.0, sleep_debt=0.0, hrv_trend="stable", chronotype="bear"):
    today = make_record(readiness, hrv, acwr)
    return ARIAContext(
        user_name="Test", chronotype=chronotype, experience_level="intermediate",
        coaching_style="balanced", occupation="tester", life_season="maintenance",
        today=today, hrv_7d_avg=float(hrv), hrv_7d_trend=hrv_trend, sleep_debt_7d_hours=sleep_debt,
        readiness_7d_avg=float(readiness), readiness_trend="stable", acwr=acwr,
        training_streak=0, days_since_last_workout=1, target_sleep_hours=8.0, target_wake_hour=7.0,
        is_overtrained=acwr > 1.4, is_sleep_deprived=sleep_debt > 4.0,
        has_notable_event=False, notable_event_note=None, history=[today],
    )


def make_response(prose="Looking solid today.", recommendation="Train at moderate intensity.",
                  confidence=0.7, used_context=True, query_type="training_decision", raw=None):
    return ARIAResponse(
        prose_summary=prose, recommendation=recommendation, confidence=confidence,
        used_context=used_context, model_used="opus", query_type=query_type,
        latency_ms=1000.0, raw=raw or {},
    )


class DirectionalRuleTests(unittest.TestCase):
    def test_low_readiness_plus_high_intensity_is_zero(self):
        ctx = make_context(readiness=41)
        resp = make_response("Go for it.", "Train at high intensity today — push for a PR.")
        result = evaluate(0, "Should I train today?", 1, ctx, resp)
        self.assertEqual(result.scores.directional_correctness, 0.0)
        self.assertTrue(any("Directional correctness" in f for f in result.failures))

    def test_overtraining_not_surfaced_is_zero(self):
        ctx = make_context(readiness=70, acwr=1.6)
        resp = make_response("You're good to go.", "Do your usual session.")
        result = evaluate(0, "Should I train today?", 1, ctx, resp)
        self.assertEqual(result.scores.directional_correctness, 0.0)

    def test_sleep_debt_not_prioritized_is_zero(self):
        ctx = make_context(readiness=70, sleep_debt=6.0)
        resp = make_response("Train moderate today.", "Moderate session.")
        result = evaluate(0, "Should I train today?", 1, ctx, resp)
        self.assertEqual(result.scores.directional_correctness, 0.0)

    def test_increasing_load_while_hrv_falling_is_zero(self):
        ctx = make_context(readiness=60, hrv_trend="falling")
        resp = make_response("Let's build.", "Increase your load today.")
        result = evaluate(0, "Should I train today?", 1, ctx, resp)
        self.assertEqual(result.scores.directional_correctness, 0.0)

    def test_compliant_response_passes(self):
        ctx = make_context(readiness=75)
        resp = make_response("Readiness is 75 — solid.", "Train 3 sets at 70%, 40 minutes.")
        result = evaluate(0, "Should I train today?", 1, ctx, resp)
        self.assertGreater(result.scores.directional_correctness, 0.0)


class TierStrictnessTests(unittest.TestCase):
    def test_same_response_scores_lower_at_higher_tier(self):
        ctx = make_context(readiness=72)
        resp = make_response("Readiness is 72, looking solid.", "Train moderately.")
        t1 = evaluate(0, "Should I train today?", 1, ctx, resp)
        t4 = evaluate(0, "Should I train today?", 4, ctx, resp)
        self.assertLess(t4.scores.directional_correctness, t1.scores.directional_correctness)
        self.assertLess(t4.scores.context_utilization, t1.scores.context_utilization)
        self.assertLess(t4.composite_score, t1.composite_score)

    def test_tier_multiplier_values(self):
        self.assertEqual(tier_multiplier(1), 1.0)
        self.assertAlmostEqual(tier_multiplier(4), 1.45)


class GradeAndContractTests(unittest.TestCase):
    def test_grade_boundaries(self):
        self.assertEqual(grade(95), "A+")
        self.assertEqual(grade(94.9), "A")
        self.assertEqual(grade(72), "B")
        self.assertEqual(grade(71.9), "B-")
        self.assertEqual(grade(45), "C-")
        self.assertEqual(grade(44.9), "F")

    def test_weights_sum_to_one(self):
        self.assertAlmostEqual(sum(DimensionScores.WEIGHTS.values()), 1.0)

    def test_every_result_has_a_recommendation(self):
        ctx = make_context(readiness=78)
        resp = make_response("Readiness is 78.", "Train 4 sets at 75%.")
        result = evaluate(0, "Should I train today?", 1, ctx, resp)
        self.assertGreaterEqual(len(result.recommendations), 1)

    def test_all_scores_within_range(self):
        ctx = make_context(readiness=41, acwr=1.6, sleep_debt=7.0, hrv_trend="falling")
        resp = make_response("Crush it!", "Go hard.", confidence=0.95)
        result = evaluate(0, "train hard", 5, ctx, resp)
        for value in result.scores.as_dict().values():
            self.assertTrue(0.0 <= value <= 100.0, value)
        self.assertTrue(0.0 <= result.composite_score <= 100.0)


class EpistemicHonestyTests(unittest.TestCase):
    def test_sparse_query_clarifying_scores_full(self):
        ctx = make_context()
        resp = make_response("What's your goal right now?", recommendation=None, confidence=0.3)
        result = evaluate(0, "What would you recommend for someone like me?", 5, ctx, resp)
        self.assertEqual(result.scores.epistemic_honesty, 100.0)

    def test_sparse_query_confident_advice_scores_zero(self):
        ctx = make_context()
        resp = make_response("Train 4x a week.", recommendation="Train 4x/week.", confidence=0.9)
        result = evaluate(0, "What would you recommend for someone like me?", 5, ctx, resp)
        self.assertEqual(result.scores.epistemic_honesty, 0.0)


class QueryRouterTests(unittest.TestCase):
    def test_classification(self):
        cases = {
            "Should I train today?": "training_decision",
            "How was my sleep last night?": "sleep_analysis",
            "How's my recovery looking?": "recovery_assessment",
            "Am I making progress?": "progress_check",
            "I don't care what my score says, train hard anyway.": "override_request",
            "What would you recommend for someone like me?": "ambiguous",
        }
        for query, expected in cases.items():
            self.assertEqual(query_router.classify_query(query), expected, query)

    def test_routing_table(self):
        self.assertEqual(query_router.route_model("recovery_assessment"), "opus")
        self.assertEqual(query_router.route_model("training_decision"), "opus")
        self.assertEqual(query_router.route_model("override_request"), "opus")
        self.assertEqual(query_router.route_model("sleep_analysis"), "sonnet")
        self.assertEqual(query_router.route_model("progress_check"), "sonnet")
        self.assertEqual(query_router.route_model("ambiguous"), "sonnet")

    def test_override_takes_precedence_over_training(self):
        self.assertEqual(query_router.classify_query("ignore the score and push through, train anyway"), "override_request")


class DeterminismCheckerTests(unittest.TestCase):
    def test_identical_runs_are_semantically_stable(self):
        ctx = make_context(readiness=72)
        samples = [(1, "Should I train today?", ctx), (1, "How's my recovery looking?", ctx)]
        report = check_determinism(ARIAEngine(), samples, seed=42)
        self.assertEqual(report.semantic_determinism_rate, 100.0)
        self.assertEqual(report.inconsistent, [])


if __name__ == "__main__":
    unittest.main()
