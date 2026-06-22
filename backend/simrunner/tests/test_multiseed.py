import datetime
import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from backend.simrunner import lifetime_suite  # noqa: E402
from backend.simrunner.aria_simrunner import _stats, report_builder  # noqa: E402
from backend.simrunner.aria_simrunner.aria_engine import ARIAEngine  # noqa: E402
from backend.simrunner.aria_simrunner.aria_evaluator import DimensionScores, evaluate  # noqa: E402
from backend.simrunner.aria_simrunner.aria_generator import get_queries_for_tier  # noqa: E402
from backend.simrunner.aria_simrunner.stability_analyzer import analyze  # noqa: E402
from backend.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.simrunner.backend_simulator.data_generator import build_context  # noqa: E402

PIN = datetime.date(2026, 1, 15)


def _silent(fn, *args, **kwargs):
    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        return fn(*args, **kwargs)
    finally:
        sys.stdout = old


def _results(model_id, tier=None, seed=42):
    model = reg.get_model(model_id)
    profile = model["behavioral_profile"]
    t = tier or model["difficulty_tier"]
    stream = generate_stream(profile, seed, PIN)
    engine = ARIAEngine()
    out, rid = [], 0
    for day in (7, 14, 21, 29):
        ctx = build_context(stream, profile, day)
        for q in get_queries_for_tier(t):
            out.append(evaluate(rid, q, t, ctx, engine.respond(q, ctx, seed)))
            rid += 1
    return out


class StatsTests(unittest.TestCase):
    def test_basic_summary(self):
        dist = _stats.summarize([10.0, 12.0, 14.0])
        self.assertEqual(dist.mean, 12.0)
        self.assertEqual(dist.min, 10.0)
        self.assertEqual(dist.max, 14.0)
        self.assertEqual(dist.n, 3)
        self.assertGreater(dist.stdev, 0)

    def test_empty_is_zeroed_and_stable(self):
        dist = _stats.summarize([])
        self.assertEqual((dist.mean, dist.stdev, dist.n), (0.0, 0.0, 0))
        self.assertTrue(dist.stable)

    def test_identical_values_are_stable(self):
        dist = _stats.summarize([82.0, 82.0, 82.0])
        self.assertEqual(dist.stdev, 0.0)
        self.assertEqual(dist.cv, 0.0)
        self.assertTrue(dist.stable)

    def test_high_variance_is_unstable(self):
        dist = _stats.summarize([10.0, 90.0, 20.0, 80.0])
        self.assertFalse(dist.stable)

    def test_percentiles_bracket_the_mean(self):
        xs = [60.0, 70.0, 80.0, 90.0, 100.0]
        dist = _stats.summarize(xs)
        self.assertLessEqual(dist.p10, dist.mean)
        self.assertGreaterEqual(dist.p90, dist.mean)

    def test_single_seed_determinism_yields_zero_variance(self):
        # Same seed twice → identical composites → a perfectly stable distribution.
        a = analyze(_results("anthropic.claude-opus-4-8-adversarial", seed=42)).overall_composite
        b = analyze(_results("anthropic.claude-opus-4-8-adversarial", seed=42)).overall_composite
        self.assertTrue(_stats.summarize([a, b]).stable)


def _multiseed_dict(model_id="anthropic.claude-sonnet-4-6"):
    runs = [analyze(_results(model_id, seed=42 + i)) for i in range(3)]
    return {
        "seed_count": 3,
        "composite": _stats.summarize([r.overall_composite for r in runs]),
        "dimensions": {
            dim: _stats.summarize([getattr(r.dimension_averages, dim) for r in runs])
            for dim in DimensionScores.WEIGHTS
        },
    }, runs


class ReportIntegrationTests(unittest.TestCase):
    def setUp(self):
        self.model = reg.get_model("anthropic.claude-sonnet-4-6")
        self.results = _results("anthropic.claude-sonnet-4-6")
        self.stability = analyze(self.results)
        self.multiseed, _ = _multiseed_dict()

    def test_json_includes_multiseed_block(self):
        doc = report_builder.build_json(self.model, self.stability, None, self.results,
                                        "2026-01-15T00:00:00", "stub", diagnostic=None,
                                        multiseed=self.multiseed)
        self.assertIsNotNone(doc["multiseed"])
        self.assertEqual(doc["multiseed"]["seed_count"], 3)
        self.assertIn("mean", doc["multiseed"]["composite"])
        self.assertEqual(len(doc["multiseed"]["dimensions"]), 6)

    def test_json_multiseed_absent_when_none(self):
        doc = report_builder.build_json(self.model, self.stability, None, self.results,
                                        "2026-01-15T00:00:00", "stub")
        self.assertIsNone(doc["multiseed"])

    def test_narrative_has_statistical_confidence_section(self):
        text = report_builder.build_narrative(self.model, self.stability, None,
                                              "2026-01-15T00:00:00", "stub", diagnostic=None,
                                              multiseed=self.multiseed)
        self.assertIn("STATISTICAL CONFIDENCE", text)

    def test_narrative_flags_skipped_determinism(self):
        text = report_builder.build_narrative(self.model, self.stability, None,
                                              "2026-01-15T00:00:00", "stub")
        self.assertIn("Skipped", text)


class CLITests(unittest.TestCase):
    def test_multiseed_run_succeeds(self):
        self.assertEqual(_silent(lifetime_suite.main, ["--tier", "1", "--seeds", "3"]), 0)

    def test_seeds_floor_to_one(self):
        cfg = lifetime_suite._validate_config({"seed_count": 0})
        self.assertEqual(cfg["seed_count"], 1)

    def test_gate_max_drop_coerced(self):
        cfg = lifetime_suite._validate_config({"gate_max_drop": "bad"})
        self.assertEqual(cfg["gate_max_drop"], 3.0)


if __name__ == "__main__":
    unittest.main()
