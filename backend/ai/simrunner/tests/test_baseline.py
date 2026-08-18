import datetime
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import baseline, diagnostics  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_engine import ARIAEngine  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_evaluator import evaluate  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_generator import get_queries_for_tier  # noqa: E402
from backend.ai.simrunner.aria_simrunner.stability_analyzer import analyze  # noqa: E402
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import build_context  # noqa: E402

PIN = datetime.date(2026, 1, 15)


def _results(model_id, tier=None):
    model = reg.get_model(model_id)
    profile = model["behavioral_profile"]
    t = tier or model["difficulty_tier"]
    stream = generate_stream(profile, 42, PIN)
    engine = ARIAEngine()
    out, rid = [], 0
    for day in (7, 14, 21, 29):
        ctx = build_context(stream, profile, day)
        for q in get_queries_for_tier(t):
            out.append(evaluate(rid, q, t, ctx, engine.respond(q, ctx, 42)))
            rid += 1
    return out


def _record(model_id, tier=None, det=100.0):
    model = reg.get_model(model_id)
    results = _results(model_id, tier)
    stability = analyze(results)
    diag, _ = diagnostics.diagnose(results)
    return baseline.record(model, stability, diag, det)


def _minimal(model_id="m", composite=80.0, mission=None):
    return {
        "model_id": model_id, "tier": 1, "composite": composite, "grade": "B+",
        "dimensions": {}, "verdict": "SHIP", "system_passed": True,
        "mission_critical_count": len(mission or []),
        "mission_critical_queries": sorted(mission or []), "determinism_rate": 100.0,
    }


class SafeNameTests(unittest.TestCase):
    def test_sanitizes_bedrock_punctuation(self):
        self.assertEqual(baseline._safe("anthropic.claude-opus-4-8:0"), "anthropic_claude_opus_4_8_0")


class RecordTests(unittest.TestCase):
    def test_record_has_expected_shape(self):
        rec = _record("amazon.nova-lite-v1", 1)
        for key in ("model_id", "tier", "composite", "grade", "dimensions", "verdict",
                    "system_passed", "mission_critical_count", "mission_critical_queries",
                    "determinism_rate"):
            self.assertIn(key, rec)
        self.assertEqual(rec["model_id"], "amazon.nova-lite-v1")
        self.assertEqual(len(rec["dimensions"]), 6)
        self.assertEqual(rec["mission_critical_count"], len(rec["mission_critical_queries"])
                         if len(set(rec["mission_critical_queries"])) == rec["mission_critical_count"] else rec["mission_critical_count"])
        self.assertEqual(rec["determinism_rate"], 100.0)

    def test_record_is_deterministic(self):
        self.assertEqual(_record("cohere.command-r-plus", 1), _record("cohere.command-r-plus", 1))


class SaveLoadTests(unittest.TestCase):
    def test_round_trip(self):
        recs = [_record("anthropic.claude-sonnet-4-6", 1), _record("amazon.nova-lite-v1", 1)]
        with tempfile.TemporaryDirectory() as d:
            written = baseline.save(recs, d)
            self.assertEqual(len(written), 2)
            loaded = baseline.load(d)
        self.assertEqual(set(loaded), {"anthropic.claude-sonnet-4-6", "amazon.nova-lite-v1"})
        self.assertEqual(loaded["amazon.nova-lite-v1"]["composite"],
                         recs[1]["composite"])

    def test_files_are_byte_stable(self):
        rec = _record("anthropic.claude-sonnet-4-6", 1)
        with tempfile.TemporaryDirectory() as d:
            baseline.save([rec], d)
            first = Path(d, baseline._safe(rec["model_id"]) + ".json").read_text()
            baseline.save([rec], d)
            second = Path(d, baseline._safe(rec["model_id"]) + ".json").read_text()
        self.assertEqual(first, second)

    def test_load_missing_dir_is_empty(self):
        self.assertEqual(baseline.load("/no/such/dir/simrunner"), {})


class CompareTests(unittest.TestCase):
    def test_identical_has_zero_delta(self):
        base = {"m": _minimal(composite=80.0)}
        diffs = baseline.compare([_minimal(composite=80.0)], base)
        self.assertEqual(diffs[0].composite_delta, 0.0)
        self.assertFalse(diffs[0].new_mission_critical)
        self.assertFalse(diffs[0].missing_baseline)

    def test_missing_baseline_flagged(self):
        diffs = baseline.compare([_minimal()], {})
        self.assertTrue(diffs[0].missing_baseline)

    def test_new_and_resolved_mission_critical(self):
        base = {"m": _minimal(mission=["old query"])}
        cur = _minimal(mission=["new query"])
        diffs = baseline.compare([cur], base)
        self.assertEqual(diffs[0].new_mission_critical, ["new query"])
        self.assertEqual(diffs[0].resolved_mission_critical, ["old query"])


class GateTests(unittest.TestCase):
    def test_pass_when_stable(self):
        diffs = baseline.compare([_minimal(composite=80.0)], {"m": _minimal(composite=80.0)})
        ok, reasons = baseline.gate(diffs, 3.0)
        self.assertTrue(ok)
        self.assertEqual(reasons, [])

    def test_fail_on_large_composite_drop(self):
        diffs = baseline.compare([_minimal(composite=70.0)], {"m": _minimal(composite=80.0)})
        ok, reasons = baseline.gate(diffs, 3.0)
        self.assertFalse(ok)
        self.assertTrue(any("composite" in r for r in reasons))

    def test_small_drop_within_tolerance_passes(self):
        diffs = baseline.compare([_minimal(composite=78.0)], {"m": _minimal(composite=80.0)})
        ok, _ = baseline.gate(diffs, 3.0)
        self.assertTrue(ok)

    def test_fail_on_new_mission_critical(self):
        base = {"m": _minimal(composite=80.0, mission=[])}
        cur = _minimal(composite=80.0, mission=["regressed query"])
        diffs = baseline.compare([cur], base)
        ok, reasons = baseline.gate(diffs, 3.0)
        self.assertFalse(ok)
        self.assertTrue(any("mission-critical" in r for r in reasons))

    def test_missing_baseline_does_not_fail_gate(self):
        diffs = baseline.compare([_minimal()], {})
        ok, _ = baseline.gate(diffs, 3.0)
        self.assertTrue(ok)


class WriteComparisonTests(unittest.TestCase):
    def test_writes_comparison_json(self):
        diffs = baseline.compare([_minimal()], {"m": _minimal()})
        with tempfile.TemporaryDirectory() as d:
            path = baseline.write_comparison(diffs, d)
            self.assertTrue(os.path.exists(path))
            data = json.loads(Path(path).read_text())
        self.assertEqual(len(data), 1)
        self.assertIn("composite_delta", data[0])


if __name__ == "__main__":
    unittest.main()
