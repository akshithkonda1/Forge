import datetime
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import _readiness, generate_stream  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import build_context  # noqa: E402

PIN = datetime.date(2026, 1, 15)


class BehaviorEngineTests(unittest.TestCase):
    def test_stream_is_30_days(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            self.assertEqual(len(generate_stream(model["behavioral_profile"])), 30)

    def test_same_profile_and_seed_is_byte_identical(self):
        profile = reg.get_model("anthropic.claude-opus-4-8")["behavioral_profile"]
        a = generate_stream(profile, 42, PIN)
        b = generate_stream(profile, 42, PIN)
        self.assertEqual(a, b)

    def test_seed_changes_output(self):
        profile = reg.get_model("anthropic.claude-opus-4-8")["behavioral_profile"]
        self.assertNotEqual(generate_stream(profile, 1, PIN), generate_stream(profile, 2, PIN))

    def test_different_profiles_differ(self):
        a = generate_stream(reg.get_models_by_tier(1)[0]["behavioral_profile"], 42, PIN)
        b = generate_stream(reg.get_models_by_tier(5)[0]["behavioral_profile"], 42, PIN)
        self.assertNotEqual([r.readiness_score for r in a], [r.readiness_score for r in b])

    def test_at_least_three_notable_events(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            stream = generate_stream(model["behavioral_profile"])
            self.assertGreaterEqual(sum(1 for r in stream if r.notes), 3, model["model_id"])

    def test_numeric_invariants_across_every_model_and_day(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            baseline = model["behavioral_profile"]["hrv_baseline"]
            for r in generate_stream(model["behavioral_profile"]):
                self.assertTrue(0 <= r.readiness_score <= 100, (model["model_id"], r.readiness_score))
                if r.sleep_score is not None:
                    self.assertTrue(0 <= r.sleep_score <= 100)
                if r.hrv is not None:
                    self.assertTrue(15 <= r.hrv <= baseline * 1.4 + 1)
                if r.resting_hr is not None:
                    self.assertTrue(38 <= r.resting_hr <= 90)
                self.assertTrue(0.0 <= r.acwr <= 2.5)
                if r.total_sleep_hours is not None:
                    self.assertTrue(3.0 <= r.total_sleep_hours <= 10.5)
                if r.deep_sleep_minutes is not None:
                    self.assertGreaterEqual(r.deep_sleep_minutes, 0)
                if r.rem_sleep_minutes is not None:
                    self.assertGreaterEqual(r.rem_sleep_minutes, 0)
                self.assertGreaterEqual(r.steps, 0)
                if r.workout_logged:
                    self.assertIn(r.workout_intensity, ("low", "moderate", "high", "max"))

    def test_readiness_formula_is_consistent(self):
        profile = reg.get_model("anthropic.claude-sonnet-4-6")["behavioral_profile"]
        baseline = profile["hrv_baseline"]
        for r in generate_stream(profile):
            self.assertEqual(r.readiness_score, _readiness(r.sleep_score, r.hrv, baseline, r.acwr))

    def test_pinned_reference_date_sets_day_one(self):
        stream = generate_stream(reg.BEDROCK_MODEL_REGISTRY[0]["behavioral_profile"], 42, PIN)
        self.assertEqual(stream[-1].date, PIN.isoformat())
        self.assertEqual(stream[0].date, (PIN - datetime.timedelta(days=29)).isoformat())

    def test_regime_change_persona_drops_load(self):
        profile = reg.get_model("amazon.nova-premier-driftshift")["behavioral_profile"]
        stream = generate_stream(profile, 42, PIN)
        early = sum(r.training_load for r in stream[:15])
        late = sum(r.training_load for r in stream[15:])
        self.assertLess(late, early)

    def test_pathological_hrv_persona_stays_low(self):
        profile = reg.get_model("amazon.nova-pro-elite-v1")["behavioral_profile"]  # baseline 28
        stream = generate_stream(profile, 42, PIN)
        self.assertLess(max(r.hrv for r in stream), 40)


class DataGeneratorTests(unittest.TestCase):
    def _ctx(self, model_id, day=29):
        model = reg.get_model(model_id)
        return build_context(generate_stream(model["behavioral_profile"], 42, PIN), model["behavioral_profile"], day)

    def test_context_fields_populated(self):
        ctx = self._ctx("anthropic.claude-sonnet-4-6")
        self.assertEqual(ctx.chronotype, "bear")
        self.assertIsNotNone(ctx.today)
        self.assertEqual(len(ctx.history), 14)

    def test_day_index_is_clamped(self):
        model = reg.BEDROCK_MODEL_REGISTRY[0]
        stream = generate_stream(model["behavioral_profile"], 42, PIN)
        ctx = build_context(stream, model["behavioral_profile"], 999)
        self.assertEqual(ctx.today, stream[-1])

    def test_flags_match_thresholds(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            for day in (7, 14, 21, 29):
                ctx = build_context(generate_stream(model["behavioral_profile"], 42, PIN),
                                    model["behavioral_profile"], day)
                self.assertEqual(ctx.is_overtrained, ctx.acwr > 1.4)
                self.assertEqual(ctx.is_sleep_deprived, ctx.sleep_debt_7d_hours > 4.0)
                self.assertIn(ctx.hrv_7d_trend, ("rising", "falling", "stable"))
                self.assertIn(ctx.readiness_trend, ("rising", "falling", "stable"))
                self.assertGreaterEqual(ctx.sleep_debt_7d_hours, 0.0)

    def test_empty_stream_raises(self):
        with self.assertRaises(ValueError):
            build_context([], reg.BEDROCK_MODEL_REGISTRY[0]["behavioral_profile"])


if __name__ == "__main__":
    unittest.main()
