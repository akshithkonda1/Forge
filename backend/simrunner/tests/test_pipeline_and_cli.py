import datetime
import io
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from backend.simrunner.aria_simrunner.aria_engine import ARIAEngine, ARIAResponse  # noqa: E402
from backend.simrunner.aria_simrunner.aria_evaluator import evaluate, grade  # noqa: E402
from backend.simrunner.aria_simrunner.aria_generator import get_queries_for_tier  # noqa: E402
from backend.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.simrunner.backend_simulator.data_generator import build_context  # noqa: E402
from backend.simrunner import lifetime_suite  # noqa: E402

PIN = datetime.date(2026, 1, 15)
_GRADES = {"A+", "A", "B+", "B", "B-", "C", "C-", "F"}


def _silent(fn, *args, **kwargs):
    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        return fn(*args, **kwargs)
    finally:
        sys.stdout = old


def _eval_model(model, reference_date=PIN):
    profile = model["behavioral_profile"]
    tier = model["difficulty_tier"]
    stream = generate_stream(profile, 42, reference_date)
    engine = ARIAEngine()
    results = []
    for day in (7, 14, 21, 29):
        ctx = build_context(stream, profile, day)
        for query in get_queries_for_tier(tier):
            results.append(evaluate(0, query, tier, ctx, engine.respond(query, ctx, 42)))
    return results


class ConfigValidationTests(unittest.TestCase):
    def test_garbage_config_is_coerced(self):
        cfg = lifetime_suite._validate_config({
            "seed": "99", "snapshot_days": ["x", 7, 99, 14],
            "determinism_sample_size": 0, "report_format": "weird", "use_real_api": "yes",
        })
        self.assertEqual(cfg["seed"], 99)
        self.assertEqual(cfg["snapshot_days"], [7, 14])       # bad/out-of-range dropped
        self.assertEqual(cfg["determinism_sample_size"], 1)   # floored to >= 1
        self.assertEqual(cfg["report_format"], "both")        # invalid → default
        self.assertTrue(cfg["use_real_api"])

    def test_empty_config_uses_defaults(self):
        cfg = lifetime_suite._validate_config({})
        self.assertEqual(cfg["snapshot_days"], [7, 14, 21, 29])
        self.assertEqual(cfg["report_format"], "both")

    def test_load_config_returns_valid_shape(self):
        cfg = lifetime_suite.load_config()
        self.assertIsInstance(cfg["seed"], int)
        self.assertTrue(cfg["snapshot_days"])
        self.assertIn(cfg["report_format"], ("text", "json", "both"))


class CLITests(unittest.TestCase):
    def test_list_exits_zero(self):
        self.assertEqual(_silent(lifetime_suite.main, ["--list"]), 0)

    def test_unknown_model_returns_nonzero(self):
        self.assertEqual(_silent(lifetime_suite.main, ["--model", "does-not-exist"]), 2)

    def test_default_tier1_run_succeeds(self):
        self.assertEqual(_silent(lifetime_suite.main, []), 0)


class EngineTests(unittest.TestCase):
    def _ctx(self):
        model = reg.get_model("anthropic.claude-sonnet-4-6")
        return build_context(generate_stream(model["behavioral_profile"], 42, PIN),
                             model["behavioral_profile"], 29)

    def test_real_api_falls_back_without_crashing(self):
        engine = ARIAEngine(use_real_api=True)
        resp = _silent(engine.respond, "Should I train today?", self._ctx(), 42)
        self.assertIsInstance(resp, ARIAResponse)

    def test_stub_is_deterministic(self):
        ctx = self._ctx()
        engine = ARIAEngine()
        self.assertEqual(engine.respond("Should I train today?", ctx, 42),
                         engine.respond("Should I train today?", ctx, 42))


class PropertyTests(unittest.TestCase):
    def test_every_evaluation_is_valid_for_all_archetypes(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            for result in _eval_model(model):
                self.assertIn(result.grade, _GRADES)
                self.assertTrue(0.0 <= result.composite_score <= 100.0)
                for value in result.scores.as_dict().values():
                    self.assertTrue(0.0 <= value <= 100.0, (model["model_id"], value))
                self.assertGreaterEqual(len(result.recommendations), 1, model["model_id"])

    def test_full_pipeline_is_deterministic(self):
        model = reg.get_model("anthropic.claude-opus-4-8-adversarial")
        a = [(r.grade, r.composite_score, r.scores.as_dict()) for r in _eval_model(model)]
        b = [(r.grade, r.composite_score, r.scores.as_dict()) for r in _eval_model(model)]
        self.assertEqual(a, b)


if __name__ == "__main__":
    unittest.main()
