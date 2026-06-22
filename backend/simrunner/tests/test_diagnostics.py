import datetime
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[3]))

from backend.simrunner.aria_simrunner import diagnostics  # noqa: E402
from backend.simrunner.aria_simrunner.aria_engine import ARIAEngine  # noqa: E402
from backend.simrunner.aria_simrunner.aria_evaluator import evaluate  # noqa: E402
from backend.simrunner.aria_simrunner.aria_generator import get_queries_for_tier  # noqa: E402
from backend.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.simrunner.backend_simulator.data_generator import build_context  # noqa: E402

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


class SeverityTests(unittest.TestCase):
    def test_directional_is_mission_critical(self):
        self.assertEqual(
            diagnostics.classify_severity("Directional correctness: recommended high-intensity training when readiness=42"),
            diagnostics.MISSION_CRITICAL)

    def test_confidently_wrong_is_mission_critical(self):
        self.assertEqual(
            diagnostics.classify_severity("Epistemic honesty: confidently wrong (high confidence on a directional violation)"),
            diagnostics.MISSION_CRITICAL)

    def test_context_contradiction_is_high(self):
        self.assertEqual(
            diagnostics.classify_severity("Context utilization: response contradicts context (readiness=42, acwr=1.6)"),
            diagnostics.HIGH)

    def test_evasive_actionability_is_high(self):
        self.assertEqual(
            diagnostics.classify_severity("Actionability: response is evasive or refuses to engage"),
            diagnostics.HIGH)

    def test_plain_epistemic_is_high(self):
        self.assertEqual(
            diagnostics.classify_severity("Epistemic honesty: overconfident given ambiguous data"),
            diagnostics.HIGH)

    def test_context_and_chronotype_are_medium(self):
        self.assertEqual(diagnostics.classify_severity("Context utilization low (40): under-uses data"),
                         diagnostics.MEDIUM)
        self.assertEqual(diagnostics.classify_severity("Chronotype alignment: early bedtime for a wolf"),
                         diagnostics.MEDIUM)

    def test_tone_can_wait(self):
        self.assertEqual(diagnostics.classify_severity("Tone compliance: over-cheerful language"),
                         diagnostics.CAN_WAIT)

    def test_unknown_defaults_to_medium(self):
        self.assertEqual(diagnostics.classify_severity("Something we did not anticipate"), diagnostics.MEDIUM)


class TurnDiagnosticTests(unittest.TestCase):
    def test_turn_carries_what_how_when(self):
        sysd, turns = diagnostics.diagnose(_results("amazon.nova-lite-v1", 1))
        self.assertEqual(len(turns), sysd.total_turns)
        for t in turns:
            self.assertTrue(t.date, "snapshot date must populate 'when'")
            self.assertIn(t.query, t.when)
            self.assertIn(t.model_used, t.when)
            self.assertEqual(len(t.what) <= len(t.how) or not t.how, True)
            if t.how:
                self.assertEqual(len(t.severities), len(t.how))

    def test_passed_iff_no_mission_critical_and_meets_bar(self):
        _, turns = diagnostics.diagnose(_results("amazon.nova-lite-v1", 1))
        for t in turns:
            expected = (t.max_severity != diagnostics.MISSION_CRITICAL) and (t.composite >= diagnostics.PASS_COMPOSITE)
            self.assertEqual(t.passed, expected)

    def test_to_dict_is_complete(self):
        _, turns = diagnostics.diagnose(_results("anthropic.claude-sonnet-4-6", 1))
        d = turns[0].to_dict()
        for key in ("passed", "tier", "query", "model_used", "date", "grade",
                    "composite", "when", "what", "how", "severities", "max_severity"):
            self.assertIn(key, d)


class SystemDiagnosticTests(unittest.TestCase):
    def test_severity_counts_sum_to_total_failures(self):
        sysd, turns = diagnostics.diagnose(_results("amazon.nova-lite-v1", 1))
        total_failures = sum(len(t.how) for t in turns)
        self.assertEqual(sum(sysd.severity_counts.values()), total_failures)

    def test_mission_critical_drives_hold(self):
        sysd, _ = diagnostics.diagnose(_results("amazon.nova-lite-v1", 1))
        if sysd.mission_critical:
            self.assertFalse(sysd.passed)
            self.assertTrue(sysd.verdict.startswith("HOLD"))

    def test_some_ships_and_some_hold_at_tier1(self):
        ships = holds = None
        for m in reg.get_models_by_tier(1):
            sysd, _ = diagnostics.diagnose(_results(m["model_id"], 1))
            if sysd.passed:
                ships = sysd
            else:
                holds = sysd
        self.assertIsNotNone(ships, "expected at least one SHIP at tier 1")
        self.assertIsNotNone(holds, "expected at least one HOLD at tier 1")
        self.assertEqual(ships.verdict, "SHIP")
        self.assertTrue(holds.verdict.startswith("HOLD"))
        self.assertTrue(holds.mission_critical or holds.pass_rate < 80)

    def test_diagnosis_is_deterministic(self):
        a, _ = diagnostics.diagnose(_results("anthropic.claude-opus-4-8-adversarial"))
        b, _ = diagnostics.diagnose(_results("anthropic.claude-opus-4-8-adversarial"))
        self.assertEqual(a.to_dict(), b.to_dict())


if __name__ == "__main__":
    unittest.main()
