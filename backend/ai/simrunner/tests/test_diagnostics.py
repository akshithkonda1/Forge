import datetime
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import diagnostics  # noqa: E402
from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner import speak_quality as sq  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_engine import ARIAResponse  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_evaluator import (  # noqa: E402
    DimensionScores, EvaluationResult, evaluate, grade,
)
from backend.ai.simrunner.aria_simrunner.aria_generator import get_queries_for_tier  # noqa: E402
from backend.ai.simrunner.aria_simrunner.dummy_orchestrator import (  # noqa: E402
    DummyARIAEngine, ENGINE_STUB,
)
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import build_context  # noqa: E402

PIN = datetime.date(2026, 1, 15)


def _results(model_id, tier=None):
    model = reg.get_model(model_id)
    profile = model["behavioral_profile"]
    t = tier or model["difficulty_tier"]
    stream = generate_stream(profile, 42, PIN)
    engine = DummyARIAEngine()
    out, rid = [], 0
    for day in (7, 14, 21, 29):
        ctx = build_context(stream, profile, day)
        for q in get_queries_for_tier(t):
            out.append(evaluate(rid, q, t, ctx, engine.respond(q, ctx, 42, engine=ENGINE_STUB)))
            rid += 1
    return out


def _fake_result(composite: float, failures: list[str] | None = None) -> EvaluationResult:
    """Minimal EvaluationResult so diagnose() can be unit-tested without a live run."""
    return EvaluationResult(
        run_id=0,
        query="should I train today?",
        tier=1,
        context_snapshot={"date": "2026-01-15"},
        response=ARIAResponse(
            prose_summary="ok", recommendation="zone 2", confidence=0.7,
            used_context=True, model_used="stub", query_type="training_decision",
            latency_ms=1.0,
        ),
        scores=DimensionScores(composite, composite, composite, composite, composite, composite),
        composite_score=composite,
        grade=grade(composite),
        failures=list(failures or []),
        recommendations=[],
    )


def _run(composites, failures_by_turn=None):
    fails = failures_by_turn or [[] for _ in composites]
    return diagnostics.diagnose([
        _fake_result(c, f) for c, f in zip(composites, fails)
    ])[0]


class QualityLevelTests(unittest.TestCase):
    """Human bands reuse the letter-grade floors. Only good/excellent may SHIP."""

    def test_bands_match_letter_grades(self):
        cases = {
            95.0: "excellent",  # A+
            88.0: "excellent",  # A
            87.9: "good",       # B+
            80.0: "good",       # B+
            79.9: "ok",         # B
            72.0: "ok",         # B
            71.9: "ok",         # B-
            65.0: "ok",         # B-
            64.9: "poor",       # C
            55.0: "poor",       # C
            45.0: "poor",       # C-
            44.9: "poor",       # F
        }
        for composite, expected in cases.items():
            self.assertEqual(
                diagnostics.quality_level(composite), expected,
                f"{composite} ({grade(composite)}) should be {expected}",
            )

    def test_ship_quality_is_good_or_excellent(self):
        self.assertEqual(diagnostics.SHIP_QUALITY, frozenset({"good", "excellent"}))
        self.assertNotIn("ok", diagnostics.SHIP_QUALITY)
        self.assertNotIn("poor", diagnostics.SHIP_QUALITY)


class QualityShipGateTests(unittest.TestCase):
    """Only good or excellent ships. OK HOLDs even with a clean honesty axis."""

    def test_ok_band_holds_despite_no_mission_critical_and_high_pass_rate(self):
        # 75–79 / B: every turn PASSes the B floor, pass rate 100%, no MC.
        sysd = _run([76.0] * 5)
        self.assertEqual(sysd.quality_level, "ok")
        self.assertEqual(sysd.overall_grade, "B")
        self.assertFalse(sysd.mission_critical)
        self.assertGreaterEqual(sysd.pass_rate, diagnostics.PASS_RATE_THRESHOLD * 100)
        self.assertFalse(sysd.passed)
        self.assertEqual(
            sysd.verdict,
            "HOLD — quality ok (B), ship requires good or excellent",
        )

    def test_b_minus_ok_holds_when_pass_rate_clears(self):
        # 8 × 72 (turn pass) + 2 × 40 (turn fail, not MC) → pass rate 80%, mean 65.6 = B- = ok.
        sysd = _run([72.0] * 8 + [40.0] * 2)
        self.assertEqual(sysd.pass_rate, 80.0)
        self.assertFalse(sysd.mission_critical)
        self.assertEqual(sysd.quality_level, "ok")
        self.assertEqual(sysd.overall_grade, "B-")
        self.assertFalse(sysd.passed)
        self.assertEqual(
            sysd.verdict,
            "HOLD — quality ok (B-), ship requires good or excellent",
        )

    def test_poor_holds(self):
        sysd = _run([50.0] * 5)
        self.assertEqual(sysd.quality_level, "poor")
        self.assertFalse(sysd.passed)
        self.assertTrue(sysd.verdict.startswith("HOLD"))

    def test_good_b_plus_ships_when_honesty_passes(self):
        sysd = _run([82.0] * 5)
        self.assertEqual(sysd.quality_level, "good")
        self.assertEqual(sysd.overall_grade, "B+")
        self.assertFalse(sysd.mission_critical)
        self.assertTrue(sysd.passed)
        self.assertEqual(sysd.verdict, "SHIP")

    def test_excellent_a_ships_when_honesty_passes(self):
        sysd = _run([90.0] * 5)
        self.assertEqual(sysd.quality_level, "excellent")
        self.assertEqual(sysd.overall_grade, "A")
        self.assertTrue(sysd.passed)
        self.assertEqual(sysd.verdict, "SHIP")

    def test_good_still_holds_on_mission_critical(self):
        sysd = _run(
            [85.0] * 5,
            failures_by_turn=[["Directional correctness: recommended high-intensity"]] + [[] for _ in range(4)],
        )
        self.assertEqual(sysd.quality_level, "good")
        self.assertTrue(sysd.mission_critical)
        self.assertFalse(sysd.passed)
        self.assertIn("mission-critical", sysd.verdict)

    def test_good_still_holds_on_low_pass_rate(self):
        # 4 × 90 (pass) + 6 × 50 (fail, not mission-critical) → 40% pass, mean 66.
        # Honesty (pass rate) wins the reason; quality is not the ship bar here.
        sysd = _run([90.0] * 4 + [50.0] * 6)
        self.assertFalse(sysd.passed)
        self.assertTrue(sysd.verdict.startswith("HOLD — pass rate"))

    def test_quality_gate_does_not_change_turn_pass_floor(self):
        self.assertEqual(diagnostics.PASS_COMPOSITE, 72.0)
        sysd, turns = diagnostics.diagnose([_fake_result(72.0)] * 5)
        self.assertTrue(all(t.passed for t in turns))
        self.assertEqual(sysd.quality_level, "ok")
        self.assertFalse(sysd.passed)


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
        sysd, turns = diagnostics.diagnose(_results("anthropic.claude-sonnet-4-6", 1))
        d = turns[0].to_dict()
        for key in ("passed", "tier", "query", "model_used", "date", "grade",
                    "composite", "when", "what", "how", "severities", "max_severity"):
            self.assertIn(key, d)
        for key in ("overall_composite", "overall_grade", "quality_level"):
            self.assertIn(key, sysd.to_dict())


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

    def test_tier1_honesty_axis_still_clean(self):
        """Tier-1 HOLD gate is unchanged: easy lives cannot HOLD for
        mission-critical or pass-rate. Quality below good may HOLD."""
        for m in reg.get_models_by_tier(1):
            sysd, _ = diagnostics.diagnose(_results(m["model_id"], 1))
            self.assertFalse(
                sysd.mission_critical,
                f"{m['model_id']} tier-1 must not HOLD for mission-critical: {sysd.verdict}",
            )
            self.assertGreaterEqual(
                sysd.pass_rate, diagnostics.PASS_RATE_THRESHOLD * 100,
                f"{m['model_id']} tier-1 must not HOLD for pass rate: {sysd.verdict}",
            )
            if sysd.quality_level in diagnostics.SHIP_QUALITY:
                self.assertTrue(sysd.passed, f"{m['model_id']} should SHIP: {sysd.verdict}")
                self.assertEqual(sysd.verdict, "SHIP")
            else:
                self.assertFalse(sysd.passed, f"{m['model_id']} ok/poor must HOLD")
                self.assertIn("quality", sysd.verdict)

    def test_diagnosis_is_deterministic(self):
        a, _ = diagnostics.diagnose(_results("anthropic.claude-opus-4-8-adversarial"))
        b, _ = diagnostics.diagnose(_results("anthropic.claude-opus-4-8-adversarial"))
        self.assertEqual(a.to_dict(), b.to_dict())


class StubVitalsScrubTests(unittest.TestCase):
    """Dummy stub must drop quoted vitals and still clear the 80% honesty bar."""

    def test_stub_scrubs_quoted_vitals_and_diagnostics_clear_80(self):
        dirty = (
            "Readiness is 95, HRV 54ms, ACWR 0.85. Resting 48 bpm. Deep sleep is 21%."
        )
        dirty_rec = (
            "Hold — readiness is 40, HRV 12ms, ACWR 1.6, 62 bpm. Deep sleep is 19%."
        )
        dirty_card = {"action": "Easy walk — HRV 12ms.", "why": "Deep sleep is 19%."}

        class FakeStub:
            confidence = 0.74
            recommendation = dirty_rec
            prose_summary = dirty
            latency_ms = 1
            raw = {"scenario": "train", "card": dirty_card}

        with patch.object(dummy, "humanize_prose", return_value=dirty), patch.object(
            dummy, "_offline_stub", return_value=FakeStub()
        ):
            row = dummy.respond("What should I train today?", seed=42, engine="stub")

        blob = sq.user_visible_blob(row)
        self.assertEqual(sq.vitals_hits(blob), [], blob)
        lowered = blob.lower()
        for token in ("readiness is 95", "hrv", "acwr", "bpm", "21%", "19%"):
            self.assertNotIn(token, lowered, blob)
        allowed = dummy._speak_without_vitals(
            "Last night was 7 hours. Zone 2 cardio 20–30 min."
        )
        self.assertIn("7 hours", allowed.lower())
        self.assertIn("zone 2", allowed.lower())

        for m in reg.get_models_by_tier(1):
            sysd, _ = diagnostics.diagnose(_results(m["model_id"], 1))
            self.assertGreaterEqual(
                sysd.pass_rate, diagnostics.PASS_RATE_THRESHOLD * 100,
                f"{m['model_id']} stub diagnostics: {sysd.verdict}",
            )
            self.assertFalse(sysd.mission_critical, sysd.verdict)


if __name__ == "__main__":
    unittest.main()
