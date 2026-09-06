import datetime
import io
import sys
import tempfile
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import bedrock_client, terraform_config as tfc  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_engine import ARIAEngine, ARIAResponse  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_evaluator import evaluate, grade  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_generator import get_queries_for_tier  # noqa: E402
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import build_context  # noqa: E402
from backend.ai.simrunner import lifetime_suite  # noqa: E402
from backend.ai.simrunner.aria_simrunner.stability_analyzer import analyze  # noqa: E402
from backend.ai.simrunner.backend_simulator import bedrock_catalog  # noqa: E402

PIN = datetime.date(2026, 1, 15)
_GRADES = {"A+", "A", "B+", "B", "B-", "C", "C-", "F"}


def _silent(fn, *args, **kwargs):
    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        return fn(*args, **kwargs)
    finally:
        sys.stdout = old


def _captured(fn, *args, **kwargs):
    """Like _silent, but returns (result, printed_text) instead of discarding it."""
    old = sys.stdout
    buf = io.StringIO()
    sys.stdout = buf
    try:
        result = fn(*args, **kwargs)
    finally:
        sys.stdout = old
    return result, buf.getvalue()


def _fake_terraform_config(infra_dir: str, bedrock_enabled: bool) -> tfc.AriaTerraformConfig:
    with open(f"{infra_dir}/terraform.tfvars", "w", encoding="utf-8") as fh:
        fh.write(f"aria_bedrock_enabled = {'true' if bedrock_enabled else 'false'}\n")
    return tfc.load(infra_dir=infra_dir)


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

    def test_list_bedrock_exits_zero(self):
        self.assertEqual(_silent(lifetime_suite.main, ["--list-bedrock"]), 0)

    def test_catalog_model_runs_via_derived_persona(self):
        self.assertEqual(_silent(lifetime_suite.main, ["--model", "amazon.nova-pro-v1:0"]), 0)


class LiveModeCLITests(unittest.TestCase):
    def test_force_live_without_live_errors(self):
        self.assertEqual(_silent(lifetime_suite.main, ["--force-live"]), 2)

    def test_live_conflicts_with_matrix(self):
        self.assertEqual(_silent(lifetime_suite.main, ["--live", "--matrix"]), 2)

    def test_check_config_exits_zero_and_touches_nothing_live(self):
        with mock.patch.object(bedrock_client, "converse") as conv:
            code, text = _captured(lifetime_suite.main, ["--check-config"])
        self.assertEqual(code, 0)
        conv.assert_not_called()
        self.assertIn("REAL AI CONFIGURATION", text)

    def test_isometric_selects_exactly_the_two_isometric_archetypes(self):
        parser_ns = type("Args", (), {"model": None, "isometric": True, "all": False, "tier": None})()
        models = lifetime_suite._select_models(parser_ns)
        self.assertEqual({m["model_id"] for m in models}, set(lifetime_suite._ISOMETRIC_MODEL_IDS))

    def test_live_refuses_when_config_has_bedrock_off_without_force(self):
        with tempfile.TemporaryDirectory() as d:
            fake_config = _fake_terraform_config(d, bedrock_enabled=False)
            with mock.patch.object(lifetime_suite.terraform_config, "load", return_value=fake_config), \
                 mock.patch.object(bedrock_client, "converse") as conv:
                code, text = _captured(lifetime_suite.main, ["--live", "--isometric"])
        self.assertEqual(code, 2)
        conv.assert_not_called()
        self.assertIn("aria_bedrock_enabled=False", text)

    def test_force_live_bypasses_the_bedrock_off_refusal(self):
        envelope = '{"prose_summary":"Fine.","recommendation":"Train normally.","confidence":0.7}'
        with tempfile.TemporaryDirectory() as d:
            fake_config = _fake_terraform_config(d, bedrock_enabled=False)
            with mock.patch.object(lifetime_suite.terraform_config, "load", return_value=fake_config), \
                 mock.patch.object(bedrock_client, "converse", return_value=envelope):
                code, text = _captured(lifetime_suite.main, ["--live", "--force-live", "--isometric"])
        self.assertEqual(code, 0)
        self.assertIn("testing MODEL CAPABILITY", text)

    def test_live_proceeds_without_force_live_when_bedrock_is_on(self):
        envelope = '{"prose_summary":"Fine.","recommendation":"Train normally.","confidence":0.7}'
        with tempfile.TemporaryDirectory() as d:
            fake_config = _fake_terraform_config(d, bedrock_enabled=True)
            with mock.patch.object(lifetime_suite.terraform_config, "load", return_value=fake_config), \
                 mock.patch.object(bedrock_client, "converse", return_value=envelope):
                code, text = _captured(lifetime_suite.main, ["--live", "--isometric"])
        self.assertEqual(code, 0)
        self.assertNotIn("testing MODEL CAPABILITY", text)

    def test_live_failure_aborts_the_whole_run_before_the_second_archetype(self):
        with tempfile.TemporaryDirectory() as d:
            fake_config = _fake_terraform_config(d, bedrock_enabled=True)
            with mock.patch.object(lifetime_suite.terraform_config, "load", return_value=fake_config), \
                 mock.patch.object(bedrock_client, "converse", side_effect=RuntimeError("simulated outage")) as conv:
                code, text = _captured(lifetime_suite.main, ["--live", "--isometric"])
        self.assertEqual(code, 3)
        self.assertIn("LIVE CONFIG CHECK FAILED", text)
        # Fails on the very first call -- the second isometric archetype's
        # run_model is never reached, so converse is called exactly once.
        conv.assert_called_once()


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

    def test_models_used_are_concrete_bedrock_ids(self):
        report = analyze(_eval_model(reg.get_model("anthropic.claude-opus-4-8")))
        self.assertTrue(report.models_used)
        for model_id in report.models_used:
            self.assertTrue(bedrock_catalog.is_bedrock_model(model_id), model_id)


if __name__ == "__main__":
    unittest.main()
