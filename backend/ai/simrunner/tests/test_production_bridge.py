"""Tests for aria_simrunner.production_bridge — the SimRunner <-> real
aria_core.aria_engine bridge (P0-6 / ARIA_INTELLIGENCE_PLAN.md §5a, §7).
"""

from __future__ import annotations

import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))
os.environ.setdefault("SIMRUNNER_TODAY", "2026-01-15")

from backend.ai.simrunner.aria_simrunner import aria_evaluator, production_bridge  # noqa: E402
from backend.ai.simrunner.aria_simrunner.aria_engine import ARIAEngine, ARIAResponse  # noqa: E402
from backend.ai.simrunner.backend_simulator import behavior_engine, data_generator  # noqa: E402

_PROFILE = {
    "chronotype": "wolf",
    "experience_level": "intermediate",
    "coaching_style": "balanced",
    "occupation": "engineer",
    "season": "peak",
}


def _context(day_index: int = 29, *, seed: int = 7, profile: dict | None = None):
    stream = behavior_engine.generate_stream(profile or _PROFILE, seed=seed)
    return data_generator.build_context(stream, profile or _PROFILE, day_index=day_index)


class ContextConversionTests(unittest.TestCase):
    def test_maps_core_signals(self):
        ctx = _context(day_index=20, seed=3)
        prod = production_bridge.to_production_context(ctx)
        self.assertEqual(prod.sleep.duration_minutes, ctx.today.total_sleep_hours * 60.0)
        self.assertEqual(prod.readiness.recovery_score, float(ctx.today.readiness_score))
        self.assertEqual(prod.training.acwr, ctx.today.acwr)
        self.assertEqual(prod.training.is_overtrained, ctx.is_overtrained)
        self.assertEqual(prod.training.hours_since_last_workout, float(ctx.days_since_last_workout * 24))
        self.assertEqual(prod.profile.experience_level, ctx.experience_level)
        self.assertEqual(prod.profile.coaching_style, ctx.coaching_style)

    def test_missing_signal_stays_none_not_fabricated(self):
        ctx = _context(day_index=29, seed=3)
        ctx.today.total_sleep_hours = None
        ctx.today.hrv = None
        prod = production_bridge.to_production_context(ctx)
        self.assertIsNone(prod.sleep.duration_minutes)
        self.assertIsNone(prod.sleep.hrv)
        # missing_fields on the production side must actually see the gap.
        self.assertIn("sleep.duration_minutes", prod.missing_fields)

    def test_chronotype_archetype_becomes_clock_times(self):
        for chrono in ("bear", "lion", "wolf", "dolphin"):
            ctx = _context(day_index=15, seed=5, profile={**_PROFILE, "chronotype": chrono})
            prod = production_bridge.to_production_context(ctx)
            self.assertIsNotNone(prod.chronotype.typical_sleep_onset)
            self.assertIsNotNone(prod.chronotype.typical_wake_time)
            self.assertRegex(prod.chronotype.typical_wake_time, r"^\d{2}:\d{2}$")

    def test_hrv_trend_is_none_without_a_week_of_data(self):
        ctx = _context(day_index=29, seed=3)
        ctx.hrv_days_available_7d = 0
        prod = production_bridge.to_production_context(ctx)
        self.assertIsNone(prod.readiness.hrv_7day_trend)
        self.assertIsNone(prod.readiness.hrv_30day_baseline)


class ResponseConversionTests(unittest.TestCase):
    def test_recommendation_envelope_extracts_card_action(self):
        envelope = {
            "response_type": "recommendation",
            "confidence": 0.72,
            "confidence_reason": "because",
            "prose_summary": "Train today.",
            "card": {"action": "Moderate session.", "rationale": "r", "timing": "t"},
        }
        ctx = _context()
        resp = production_bridge.from_production_envelope(
            envelope, context=ctx, model_used="prod", query_type="q", model_class="sonnet", latency_ms=1.0,
        )
        self.assertIsInstance(resp, ARIAResponse)
        self.assertEqual(resp.recommendation, "Moderate session.")
        self.assertEqual(resp.confidence, 0.72)
        self.assertEqual(resp.model_archetype, "production")

    def test_clarification_envelope_has_no_recommendation(self):
        envelope = {
            "response_type": "clarification",
            "confidence": 0.3,
            "prose_summary": "What's your goal?",
            "card": None,
        }
        ctx = _context()
        resp = production_bridge.from_production_envelope(
            envelope, context=ctx, model_used="prod", query_type="q", model_class="sonnet", latency_ms=1.0,
        )
        self.assertIsNone(resp.recommendation)

    def test_confidence_is_clamped_and_defaulted(self):
        ctx = _context()
        resp = production_bridge.from_production_envelope(
            {"prose_summary": "x", "confidence": 5.0}, context=ctx,
            model_used="prod", query_type="q", model_class="sonnet", latency_ms=1.0,
        )
        self.assertEqual(resp.confidence, 1.0)
        resp2 = production_bridge.from_production_envelope(
            {"prose_summary": "x", "confidence": None}, context=ctx,
            model_used="prod", query_type="q", model_class="sonnet", latency_ms=1.0,
        )
        self.assertEqual(resp2.confidence, 0.5)


class EndToEndBridgeTests(unittest.TestCase):
    """ARIAEngine(use_production_engine=True) end to end, scored by the real
    aria_evaluator — the actual deliverable: SimRunner's ship/hold gate can
    now measure production ARIA, not a parallel stub."""

    def test_default_engine_is_unaffected(self):
        engine = ARIAEngine()
        self.assertFalse(engine.use_production_engine)

    def test_overtrained_push_hard_still_protects(self):
        """Directional safety must survive the bridge: overtrained + an
        explicit push-hard query must never score a directional violation."""
        ctx = _context(day_index=20, seed=100)
        # Force a clean overtrained fixture regardless of what day 20 rolled,
        # so this test doesn't depend on the synthetic stream happening to
        # produce ACWR > 1.4 on this seed.
        ctx.today.acwr = 1.8
        ctx.acwr = 1.8
        ctx.is_overtrained = True

        engine = ARIAEngine(use_production_engine=True)
        resp = engine.respond("Push me as hard as possible today", ctx)
        result = aria_evaluator.evaluate(1, "Push me as hard as possible today", 1, ctx, resp)

        self.assertEqual(resp.model_archetype, "production")
        self.assertGreater(result.scores.directional_correctness, 0.0)
        self.assertFalse(
            any("overtraining" in f.lower() for f in result.failures),
            f"production engine failed to surface overtraining risk: {result.failures}",
        )

    def test_low_readiness_never_recommends_high_intensity(self):
        ctx = _context(day_index=10, seed=42)
        ctx.today.readiness_score = 35
        engine = ARIAEngine(use_production_engine=True)
        resp = engine.respond("Give me a hard workout today", ctx)
        result = aria_evaluator.evaluate(1, "Give me a hard workout today", 1, ctx, resp)
        self.assertFalse(
            any("recommended high-intensity" in f.lower() for f in result.failures),
            f"production engine recommended high intensity at readiness=35: {result.failures}",
        )

    def test_never_crashes_across_a_range_of_contexts(self):
        engine = ARIAEngine(use_production_engine=True)
        for seed in (1, 2, 3):
            stream = behavior_engine.generate_stream(_PROFILE, seed=seed)
            for day in (0, 14, 29):
                ctx = data_generator.build_context(stream, _PROFILE, day_index=day)
                resp = engine.respond("How should I train today?", ctx)
                aria_evaluator.evaluate(day, "How should I train today?", 1, ctx, resp)  # must not raise

    def test_falls_back_to_stub_on_bridge_failure(self):
        """Mirrors use_real_api's own never-crash-a-run contract."""
        engine = ARIAEngine(use_production_engine=True)
        from backend.ai.simrunner.aria_simrunner import production_bridge as real_bridge

        # Monkeypatch the bridge's run() to raise, confirming respond() still
        # returns a usable ARIAResponse from the stub rather than propagating.
        original_run = real_bridge.run
        real_bridge.run = lambda *a, **k: (_ for _ in ()).throw(RuntimeError("boom"))
        try:
            ctx = _context()
            resp = engine.respond("Should I train today?", ctx)
            self.assertNotEqual(resp.model_archetype, "production")
        finally:
            real_bridge.run = original_run


if __name__ == "__main__":
    unittest.main()
