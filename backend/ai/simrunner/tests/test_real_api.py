import datetime
import io
import sys
import unittest
from pathlib import Path
from unittest import mock

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import bedrock_client, prompts  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_engine import (  # noqa: E402
    ARIAEngine, ARIAResponse, _parse_envelope, _references_context, _safe_float,
)
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import build_context  # noqa: E402

PIN = datetime.date(2026, 1, 15)


def _silent(fn, *args, **kwargs):
    old = sys.stdout
    sys.stdout = io.StringIO()
    try:
        return fn(*args, **kwargs)
    finally:
        sys.stdout = old


def _ctx():
    model = reg.get_model("anthropic.claude-sonnet-4-6")
    return build_context(generate_stream(model["behavioral_profile"], 42, PIN),
                         model["behavioral_profile"], 29)


class EnvelopeParsingTests(unittest.TestCase):
    def test_plain_json(self):
        self.assertEqual(_parse_envelope('{"a": 1}'), {"a": 1})

    def test_fenced_json(self):
        self.assertEqual(_parse_envelope('```json\n{"a": 2}\n```'), {"a": 2})

    def test_prose_around_json(self):
        self.assertEqual(_parse_envelope('Here you go:\n{"a": 3}\nThanks!'), {"a": 3})

    def test_garbage_is_empty_dict(self):
        self.assertEqual(_parse_envelope("not json at all"), {})

    def test_non_object_is_empty_dict(self):
        self.assertEqual(_parse_envelope("[1, 2, 3]"), {})


class SafeFloatTests(unittest.TestCase):
    def test_clamps_and_defaults(self):
        self.assertEqual(_safe_float("0.8", 0.5), 0.8)
        self.assertEqual(_safe_float(1.7, 0.5), 1.0)
        self.assertEqual(_safe_float(-0.2, 0.5), 0.0)
        self.assertEqual(_safe_float("nope", 0.42), 0.42)
        self.assertEqual(_safe_float(None, 0.33), 0.33)


class ReferencesContextTests(unittest.TestCase):
    def test_detects_number(self):
        ctx = _ctx()
        prose = f"Your readiness is {ctx.today.readiness_score} today."
        self.assertTrue(_references_context(prose, ctx))

    def test_detects_keyword(self):
        self.assertTrue(_references_context("Your HRV is trending down.", _ctx()))

    def test_generic_prose_is_false(self):
        self.assertFalse(_references_context("You are doing wonderfully, keep going!", _ctx()))


class PromptTests(unittest.TestCase):
    def test_system_prompt_has_safety_gates(self):
        sp = prompts.system_prompt("v1")
        self.assertIn("SAFETY GATES", sp)
        self.assertIn("Readiness < 50", sp)

    def test_unknown_variant_falls_back_to_v1(self):
        self.assertEqual(prompts.system_prompt("does-not-exist"), prompts.ARIA_SYSTEM_PROMPT_V1)

    def test_user_prompt_embeds_query_and_numbers(self):
        ctx = _ctx()
        up = prompts.build_user_prompt("Should I train today?", ctx)
        self.assertIn("Should I train today?", up)
        self.assertIn(str(ctx.today.readiness_score), up)
        self.assertIn("JSON", up)


class RealApiEngineTests(unittest.TestCase):
    def test_success_path_parses_model_envelope(self):
        envelope = ('```json\n{"response_type":"recommendation",'
                    '"prose_summary":"Readiness is low; hold back today.",'
                    '"recommendation":"Zone 2 only.","confidence":0.82}\n```')
        with mock.patch.object(bedrock_client, "converse", return_value=envelope) as m:
            engine = ARIAEngine(use_real_api=True, engine_model="anthropic.claude-opus-4-8")
            resp = engine.respond("Should I train today?", _ctx(), 42)
        m.assert_called_once()
        self.assertIsInstance(resp, ARIAResponse)
        self.assertEqual(resp.model_used, "anthropic.claude-opus-4-8")
        self.assertEqual(resp.recommendation, "Zone 2 only.")
        self.assertAlmostEqual(resp.confidence, 0.82, places=2)
        self.assertEqual(resp.raw["scenario"], "real_api")

    def test_exception_falls_back_to_stub(self):
        with mock.patch.object(bedrock_client, "converse", side_effect=RuntimeError("no creds")):
            engine = ARIAEngine(use_real_api=True)
            resp = _silent(engine.respond, "Should I train today?", _ctx(), 42)
        self.assertIsInstance(resp, ARIAResponse)
        self.assertNotEqual(resp.raw.get("scenario"), "real_api")

    def test_warning_printed_once(self):
        with mock.patch.object(bedrock_client, "converse", side_effect=RuntimeError("boom")):
            engine = ARIAEngine(use_real_api=True)
            buf = io.StringIO()
            old = sys.stdout
            sys.stdout = buf
            try:
                engine.respond("q1", _ctx(), 42)
                engine.respond("q2", _ctx(), 42)
            finally:
                sys.stdout = old
        self.assertEqual(buf.getvalue().count("real-API path unavailable"), 1)

    def test_default_engine_does_not_import_boto3(self):
        sys.modules.pop("boto3", None)
        engine = ARIAEngine()  # offline default
        engine.respond("Should I train today?", _ctx(), 42)
        self.assertNotIn("boto3", sys.modules)

    def test_malformed_envelope_uses_raw_text(self):
        with mock.patch.object(bedrock_client, "converse", return_value="just words, no json"):
            engine = ARIAEngine(use_real_api=True, engine_model="anthropic.claude-opus-4-8")
            resp = engine.respond("Should I train today?", _ctx(), 42)
        self.assertEqual(resp.raw["scenario"], "real_api")
        self.assertIn("just words", resp.prose_summary)
        self.assertAlmostEqual(resp.confidence, 0.6, places=2)  # default when absent


class BedrockClientTests(unittest.TestCase):
    def test_missing_boto3_raises_bedrock_unavailable(self):
        import builtins
        real_import = builtins.__import__

        def fake_import(name, *args, **kwargs):
            if name == "boto3":
                raise ModuleNotFoundError("No module named 'boto3'")
            return real_import(name, *args, **kwargs)

        with mock.patch.object(builtins, "__import__", side_effect=fake_import):
            with self.assertRaises(bedrock_client.BedrockUnavailable):
                bedrock_client.converse("model", "sys", "user")


if __name__ == "__main__":
    unittest.main()
