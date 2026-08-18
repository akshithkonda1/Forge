"""Regression tests for bugs found in the Forge bug sweep.

Each test fails against the pre-fix code and passes after the fix. Grouped by
the subsystem the defect lived in.
"""

import sys
import unittest
from datetime import datetime, timezone
from pathlib import Path

import _bootstrap  # noqa: F401

from services import aria_engine  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ActivityContext,
    ARIAContext,
    BodyContext,
    ChronotypeContext,
    ProgressContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
    _interpret_sleep,
    apply_permissions,
    classify_request,
)
from services.biometrics import BodyModel, classify_batch, classify_sample  # noqa: E402
from services.biometrics.body_model import redact_snapshot  # noqa: E402
from services.biometrics.types import Observation  # noqa: E402


def _ctx(**overrides) -> ARIAContext:
    ctx = ARIAContext(
        sleep=SleepContext(duration_minutes=450, efficiency=0.9, rem_minutes=95,
                           deep_minutes=90, hrv=58, resting_hr=52, nights_available=14),
        readiness=ReadinessContext(hrv_7day_trend=-4, hrv_30day_baseline=62,
                                   recovery_score=68, hrv_days_available=7),
        training=TrainingContext(last_workout_type="strength", last_workout_duration_minutes=60,
                                 hours_since_last_workout=14, weekly_load_score=70),
        activity=ActivityContext(steps_3day_avg=8200, active_calories_3day_avg=540),
        chronotype=ChronotypeContext(typical_sleep_onset="23:30", typical_wake_time="07:00",
                                     consistency_score=0.82),
    )
    for key, value in overrides.items():
        setattr(ctx, key, value)
    return ctx


class SleepDurationThresholdTests(unittest.TestCase):
    """aria_engine: 6–7 h nights were silently unflagged while the message
    claimed a '7 h floor'."""

    def test_six_and_a_half_hours_is_flagged(self):
        sig = _interpret_sleep(_ctx(sleep=SleepContext(
            duration_minutes=390, efficiency=0.95, rem_minutes=95,
            deep_minutes=95, hrv=58, resting_hr=52, nights_available=14)))
        self.assertIsNotNone(sig)
        self.assertIn("7 h floor", sig.interpretation)
        self.assertEqual(sig.direction, "negative")

    def test_eight_hours_is_not_flagged_for_duration(self):
        sig = _interpret_sleep(_ctx(sleep=SleepContext(
            duration_minutes=480, efficiency=0.95, rem_minutes=110,
            deep_minutes=110, hrv=58, resting_hr=52, nights_available=14)))
        self.assertIsNotNone(sig)
        self.assertNotIn("7 h floor", sig.interpretation)


class DomainKeywordTests(unittest.TestCase):
    """aria_engine: the bare 'pr' progress keyword substring-matched ordinary
    words like 'press', misrouting questions into a progress summary."""

    def test_bench_press_is_not_a_progress_summary(self):
        ctx = _ctx(progress=ProgressContext(
            workouts_completed_30d=12, new_personal_records=1,
            training_load_trend="up", recovery_consistency_delta=0.1))
        self.assertNotEqual(classify_request("how did my bench press feel?", ctx), "summary")

    def test_real_progress_question_still_summarizes(self):
        ctx = _ctx(progress=ProgressContext(
            workouts_completed_30d=12, new_personal_records=1,
            training_load_trend="up", recovery_consistency_delta=0.1))
        self.assertEqual(classify_request("show my progress this month", ctx), "summary")


class ObserveTimestampTests(unittest.TestCase):
    """biometrics.classify: fusing a tz-naive sample with a tz-aware one crashed
    the chronological sort with a TypeError."""

    def test_mixed_naive_and_aware_timestamps_do_not_crash(self):
        raw = [
            {"type": "hrv", "value": 55, "unit": "ms", "timestamp": "2026-06-10T23:30:00"},  # naive
            {"type": "heart_rate", "value": 60, "unit": "bpm"},                               # no ts -> aware
        ]
        result = classify_batch(raw)  # must not raise
        self.assertEqual(len(result.observations), 2)
        self.assertTrue(all(o.timestamp.tzinfo is not None for o in result.observations))


class SnapshotRedactionTests(unittest.TestCase):
    """biometrics route: /ai/observe leaked denied domains through `snapshot`
    even though the ARIA context redacted them."""

    def _model(self) -> BodyModel:
        raw = [
            {"type": "weight", "value": 82, "unit": "kg", "timestamp": "2026-06-10T08:00:00Z"},
            {"type": "hrv", "value": 55, "unit": "ms", "timestamp": "2026-06-10T08:00:00Z"},
            {"type": "heart_rate", "value": 54, "unit": "bpm", "timestamp": "2026-06-10T08:00:00Z"},
        ]
        obs = [o for o in (classify_sample(r) for r in raw) if isinstance(o, Observation)]
        return BodyModel.from_observations(obs)

    def test_denied_body_domain_is_absent_from_snapshot(self):
        snap = self._model().snapshot().to_dict()
        self.assertIn("body", snap["systems"])  # present before redaction
        perms = aria_engine.DataPermissions.from_payload({"body": False})
        red = redact_snapshot(snap, perms)
        self.assertNotIn("body", red["systems"])          # body system dropped
        self.assertEqual(red["derived"], {})              # cross-signal estimates dropped
        # an allowed domain's system survives
        self.assertTrue(any(s in red["systems"] for s in ("autonomic", "cardiovascular")))

    def test_allow_all_leaves_snapshot_untouched(self):
        snap = self._model().snapshot().to_dict()
        red = redact_snapshot(snap, aria_engine.DataPermissions.allow_all())
        self.assertIn("body", red["systems"])


class MissingFieldsRedactionTests(unittest.TestCase):
    """aria route: missing_fields was computed on the un-redacted context, so a
    denied-but-populated domain's fields were omitted (existence leak)."""

    def test_denied_domain_fields_reported_missing_after_sanitize(self):
        ctx = _ctx(body=BodyContext(weight_kg=80, weight_trend_kg=-1.2,
                                    body_fat_pct=0.18, vo2_max=48))
        perms = aria_engine.DataPermissions.from_payload({"body": False})
        raw_missing = set(ctx.missing_fields)
        sanitized_missing = set(apply_permissions(ctx, perms)[0].missing_fields)
        self.assertNotIn("body.weight_kg", raw_missing)       # leak: present data hidden from missing
        self.assertIn("body.weight_kg", sanitized_missing)    # fixed: reported unavailable


if __name__ == "__main__":
    unittest.main()
