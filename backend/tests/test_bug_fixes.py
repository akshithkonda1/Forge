"""Regression tests for bugs found in the Forge bug sweep.

Each test fails against the pre-fix code and passes after the fix. Grouped by
the subsystem the defect lived in.
"""

import json
import os
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


class ArchetypeLiveImportTests(unittest.TestCase):
    """routes/aria.py's handle_post_ai_archetype imported a transposed module path
    (backend.app.ai.routes.archetype instead of backend.ai.app.routes.archetype),
    caught by a bare except and silently falling through to a worse inline
    3-category fallback every single time. archetype.py's own _try_bedrock also
    imported two more nonexistent bedrock_client paths and probed for methods
    the real client doesn't expose, so even a corrected outer import alone
    wouldn't have reached live Bedrock."""

    def test_real_archetype_module_imports_cleanly(self):
        from backend.ai.app.routes.archetype import create_archetype  # must not raise
        self.assertTrue(callable(create_archetype))

    def test_handler_reaches_the_real_module_not_the_inline_fallback(self):
        from routes.aria import handle_post_ai_archetype

        result = handle_post_ai_archetype(
            {"description": "a calm, data-driven analyst"}, user_id="test-user"
        )
        body = json.loads(result["body"])
        # The inline fallback's signature is model == "local-forge" with a
        # top-level user_id key; the real module returns model == "backend"/
        # "claude" with no top-level user_id, and a richer 5-category match.
        self.assertNotEqual(body.get("model"), "local-forge")
        self.assertNotIn("user_id", body)
        self.assertEqual(body["archetype"]["relatedBuiltin"], "analyst")


class LastPromotedAtRoundTripTests(unittest.TestCase):
    """aria_context.UserContext.to_dict() omitted last_promoted_at, so it never
    survived a storage round-trip -- the 'promote at most once per 24h' guard
    in routes/aria.py never engaged, since every load saw None."""

    def test_last_promoted_at_survives_to_dict_from_dict_round_trip(self):
        from services.aria_context import UserContext

        ctx = UserContext(
            user_id="u1", relationship_level=3,
            last_promoted_at=datetime(2026, 9, 1, 12, 0, tzinfo=timezone.utc),
        )
        self.assertIn("last_promoted_at", ctx.to_dict())
        restored = UserContext.from_dict(ctx.to_dict())
        self.assertEqual(restored.last_promoted_at, ctx.last_promoted_at)

    def test_none_last_promoted_at_round_trips_as_none(self):
        from services.aria_context import UserContext

        ctx = UserContext(user_id="u1")
        self.assertIsNone(UserContext.from_dict(ctx.to_dict()).last_promoted_at)


class RelationshipPromotionThrottleTests(unittest.TestCase):
    """routes/aria.py's handle_post_ai_chat passed last_promoted_at as an
    already-stringified value (now.isoformat()) where UserContext declares a real
    datetime. Dormant while aria_context.to_dict() omitted the field entirely; once
    that omission was fixed (see LastPromotedAtRoundTripTests), every promoting chat
    started crashing with AttributeError: 'str' object has no attribute 'isoformat'
    the next time to_dict() ran. Drives the real route end-to-end so both the crash
    and the 24h throttle last_promoted_at exists to enforce are covered -- a round
    -trip test on UserContext alone can't see a caller passing the wrong type."""

    def test_promoting_chat_does_not_crash_and_bumps_relationship(self):
        from routes.aria import handle_post_ai_chat
        from services.aria_context import CoachContextEngine

        uid = f"promo-user-{id(self)}"
        result = handle_post_ai_chat(  # must not raise
            {"message": "hello", "recent_metrics": {"readiness": 80}}, user_id=uid
        )
        self.assertEqual(result["statusCode"], 200)
        self.assertEqual(CoachContextEngine().get_or_create_context(uid).relationship_level, 2)

    def test_second_promoting_chat_within_24h_is_throttled(self):
        from routes.aria import handle_post_ai_chat
        from services.aria_context import CoachContextEngine

        uid = f"throttle-user-{id(self)}"
        handle_post_ai_chat({"message": "hello", "recent_metrics": {"readiness": 80}}, user_id=uid)
        handle_post_ai_chat({"message": "hello again", "recent_metrics": {"readiness": 80}}, user_id=uid)
        # Still 2, not 3: the second promotion is suppressed by the <24h guard,
        # which only engages if last_promoted_at actually survived the first save.
        self.assertEqual(CoachContextEngine().get_or_create_context(uid).relationship_level, 2)


class ReadinessNullScoreTests(unittest.TestCase):
    """readiness.compute_readiness crashed with TypeError on a stored sleep
    record with score: null -- dict.get's default only applies when the key is
    absent, not when it's present and explicitly None."""

    def test_null_score_does_not_crash(self):
        from services import readiness

        result = readiness.compute_readiness(
            [{"date": "2026-09-02", "source": "manual", "score": None, "totalHours": 7.5}]
        )
        self.assertIsInstance(result["overall"], int)

    def test_null_score_falls_back_to_the_same_default_as_a_missing_key(self):
        from services import readiness

        with_null = readiness.compute_readiness([{"score": None}])
        missing_key = readiness.compute_readiness([{}])
        for key in ("overall", "sleepQuality", "recoveryScore", "stressLevel", "energyBank"):
            self.assertEqual(with_null[key], missing_key[key])


class WorkoutPlanPersistenceTests(unittest.TestCase):
    """routes/coach.py's handle_post_coach_workout_plan generated a plan via the
    AI router but never persisted it -- keys.workout_plan_key/PLAN#{date} was
    read in 4 places and written nowhere, so GET /workouts/today always
    returned nothing for a real account."""

    def _toggle_demo_data(self, value: str | None):
        previous = os.environ.get("FORGE_DEMO_DATA")
        if value is None:
            os.environ.pop("FORGE_DEMO_DATA", None)
        else:
            os.environ["FORGE_DEMO_DATA"] = value
        self.addCleanup(
            lambda: os.environ.pop("FORGE_DEMO_DATA", None) if previous is None
            else os.environ.__setitem__("FORGE_DEMO_DATA", previous)
        )

    def test_generated_plan_is_readable_via_workouts_today(self):
        from routes.coach import handle_post_coach_workout_plan
        from routes.workouts import handle_get_workouts_today

        self._toggle_demo_data("true")
        uid = f"test-workout-plan-{id(self)}"
        posted = json.loads(handle_post_coach_workout_plan(uid, {})["body"])["todayPlan"]
        self.assertIsNotNone(posted)

        fetched = json.loads(handle_get_workouts_today(uid)["body"])["workout"]
        self.assertEqual(fetched["id"], posted["id"])
        self.assertEqual(fetched["duration"], posted["duration"])

    def test_never_fabricates_a_duration_with_no_logged_workout_history(self):
        from routes.coach import handle_post_coach_workout_plan
        from routes.workouts import handle_get_workouts_today

        self._toggle_demo_data("false")
        uid = f"test-no-history-{id(self)}"
        handle_post_coach_workout_plan(uid, {})
        fetched = json.loads(handle_get_workouts_today(uid)["body"])["workout"]
        self.assertIsNone(fetched)


if __name__ == "__main__":
    unittest.main()
