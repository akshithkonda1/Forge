"""Evidence-graph fusion + load-safety gates for production ARIA."""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from services import aria_engine, aria_evidence  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ARIAContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)


def _ctx(**kwargs) -> ARIAContext:
    base = dict(
        sleep=SleepContext(
            duration_minutes=360,
            deep_minutes=50,
            rem_minutes=70,
            efficiency=0.88,
            nights_available=10,
            sleep_debt_7d_hours=6.5,
        ),
        readiness=ReadinessContext(
            hrv_7day_trend=-14,
            hrv_30day_baseline=60,
            recovery_score=42,
            hrv_days_available=7,
        ),
        training=TrainingContext(
            last_workout_type="strength",
            hours_since_last_workout=10,
            weekly_load_score=88,
            acwr=1.62,
            is_overtrained=True,
        ),
    )
    base.update(kwargs)
    return ARIAContext(**base)


class DeriveLoadTests(unittest.TestCase):
    def test_prefers_payload_acwr_and_debt(self):
        load = aria_evidence.derive_load(_ctx())
        self.assertAlmostEqual(load.acwr or 0, 1.62, places=2)
        self.assertAlmostEqual(load.sleep_debt_7d_h or 0, 6.5, places=1)
        self.assertTrue(load.is_overtrained)

    def test_estimates_acwr_from_weekly_load(self):
        ctx = _ctx(
            training=TrainingContext(weekly_load_score=55, hours_since_last_workout=30),
            sleep=SleepContext(duration_minutes=480, nights_available=7),
            readiness=ReadinessContext(recovery_score=72, hrv_7day_trend=2),
        )
        # Clear payload ACWR / overtrained
        ctx.training.acwr = None
        ctx.training.is_overtrained = None
        load = aria_evidence.derive_load(ctx)
        self.assertIsNotNone(load.acwr)
        self.assertAlmostEqual(load.acwr or 0, 1.0, places=1)
        self.assertFalse(load.is_overtrained)

    def test_ratio_from_acute_chronic(self):
        ctx = _ctx(
            training=TrainingContext(acute_load=150, chronic_load=100),
            sleep=SleepContext(duration_minutes=480),
            readiness=ReadinessContext(recovery_score=70),
        )
        load = aria_evidence.derive_load(ctx)
        self.assertAlmostEqual(load.acwr or 0, 1.5, places=2)


class PatternSafetyTests(unittest.TestCase):
    def test_overreaching_blocks_intensity(self):
        ctx = _ctx()
        signals = aria_engine._gather_signals(ctx)
        pattern = aria_evidence.detect_pattern(ctx, signals, [])
        self.assertEqual(pattern.key, "overreaching")
        self.assertTrue(pattern.blocks_intensity)
        self.assertEqual(pattern.stance, "protect")

    def test_low_readiness_never_green_lights(self):
        ctx = _ctx(
            training=TrainingContext(hours_since_last_workout=48, weekly_load_score=40),
            sleep=SleepContext(duration_minutes=480, nights_available=10, sleep_debt_7d_hours=0),
            readiness=ReadinessContext(
                recovery_score=45, hrv_7day_trend=0, hrv_days_available=7
            ),
        )
        signals = aria_engine._gather_signals(ctx)
        pattern = aria_evidence.detect_pattern(ctx, signals, [])
        self.assertTrue(pattern.blocks_intensity)
        self.assertIn(pattern.key, {"low_readiness", "protect_cluster", "under_recovery"})

    def test_recommendation_surfaces_acwr_language(self):
        resp = aria_engine.generate_response("should I train hard today?", _ctx())
        self.assertEqual(resp["response_type"], "recommendation")
        blob = f"{resp['prose_summary']} {resp['message']} {resp.get('confidence_reason', '')}".lower()
        self.assertTrue(
            "acwr" in blob or "overreach" in blob or "workload" in blob or "deload" in blob,
            msg=blob,
        )
        self.assertTrue(resp["evidence"]["blocks_intensity"])
        self.assertLessEqual(resp["confidence"], 0.72)

    def test_sleep_debt_prioritized(self):
        ctx = _ctx(
            training=TrainingContext(hours_since_last_workout=40, weekly_load_score=50),
            sleep=SleepContext(
                duration_minutes=300,
                nights_available=10,
                sleep_debt_7d_hours=7.0,
                deep_minutes=40,
                rem_minutes=60,
                efficiency=0.85,
            ),
            readiness=ReadinessContext(
                hrv_7day_trend=-12,
                recovery_score=55,
                hrv_days_available=7,
            ),
        )
        resp = aria_engine.generate_response("what should I do today?", ctx)
        blob = f"{resp['prose_summary']} {resp['message']}".lower()
        self.assertTrue("sleep" in blob, msg=blob)
        self.assertTrue(resp["evidence"]["blocks_intensity"])


class PlanTypeTests(unittest.TestCase):
    def test_classify_emits_plan(self):
        ctx = _ctx(
            training=TrainingContext(hours_since_last_workout=48, weekly_load_score=50),
            sleep=SleepContext(duration_minutes=480, nights_available=10),
            readiness=ReadinessContext(recovery_score=72, hrv_7day_trend=3),
        )
        self.assertEqual(
            aria_engine.classify_request("plan my week around recovery", ctx),
            "plan",
        )

    def test_plan_response_has_outline(self):
        ctx = _ctx()
        resp = aria_engine.generate_response("build a plan for the next three days", ctx)
        self.assertEqual(resp["response_type"], "plan")
        self.assertIsNotNone(resp.get("card"))
        self.assertEqual(len(resp["card"]["days"]), 3)
        self.assertTrue(resp["evidence"]["blocks_intensity"])


class PayloadParseTests(unittest.TestCase):
    def test_rich_payload_parses_acwr_and_debt(self):
        ctx = ARIAContext.from_payload({
            "context": {
                "sleep": {"durationMinutes": 400, "sleepDebt7dHours": 5.5, "targetHours": 8},
                "training": {"acwr": 1.4, "isOvertrained": True, "weeklyLoadScore": 80},
                "readiness": {"recoveryScore": 48, "hrv7DayTrend": -9},
            }
        })
        self.assertAlmostEqual(ctx.sleep.sleep_debt_7d_hours or 0, 5.5)
        self.assertAlmostEqual(ctx.training.acwr or 0, 1.4)
        self.assertTrue(ctx.training.is_overtrained)


class LazyHandlerImportTests(unittest.TestCase):
    def test_handler_source_has_no_eager_route_imports(self):
        from pathlib import Path

        text = Path(__file__).resolve().parents[1].joinpath(
            "infra", "lambda", "handler.py"
        ).read_text(encoding="utf-8")
        head, _, _ = text.partition("def _route")
        self.assertNotIn("from routes import", head)
        self.assertNotIn("from ai_router import", head)
        self.assertIn("from routes import", text)  # still used lazily inside branches

    def test_fresh_handler_import_skips_aria_engine(self):
        import subprocess
        import sys
        from pathlib import Path

        root = Path(__file__).resolve().parents[1]
        script = (
            "import sys\n"
            f"sys.path.insert(0, {str(root / 'infra' / 'lambda')!r})\n"
            "import handler\n"
            "assert 'services.aria_engine' not in sys.modules\n"
            "print('ok')\n"
        )
        proc = subprocess.run(
            [sys.executable, "-c", script],
            check=False,
            capture_output=True,
            text=True,
        )
        self.assertEqual(proc.returncode, 0, msg=proc.stderr or proc.stdout)
        self.assertIn("ok", proc.stdout)


if __name__ == "__main__":
    unittest.main()
