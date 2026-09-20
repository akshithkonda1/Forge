"""Regression tests for the sleep-debt directional-safety gaps found while
pointing SimRunner's dummy orchestrator at the real engine (see
dummy_orchestrator.DummyARIAEngine and ARIA_INTELLIGENCE_PLAN.md P0-6):

1. BodyModel.to_aria_context() never projected sleep_debt_7d_hours/
   target_hours at all -- fusion.fuse_turn's overlay_context makes BodyModel
   *own* the sleep domain whenever fresh sleep observations exist (the
   normal case for any real user, not a SimRunner-only artifact), so a
   client-sent 7-day debt figure was silently discarded and replaced with
   None every time.
2. fusion.stance_for_plan() forced "protect" for overtraining/low-readiness/
   personal-deficit but never checked the same sleep-debt/under-recovery
   thresholds aria_evidence.detect_pattern() already used -- so the evidence
   graph could correctly pick the "sleep_debt" pattern while the actual
   spoken stance (and therefore the actual next_step text a user reads)
   still came from contextual_learner's independent, unrelated stance model.
3. context_plan.evaluate_aging() only looked at tonight's single-night hours,
   never the accumulated 7-day debt, so a high-debt week with one
   unremarkable night could still resolve to "train_through".
"""

from __future__ import annotations

import datetime
import unittest

import _bootstrap  # noqa: F401

from services import aria_engine, context_plan, fusion  # noqa: E402
from services.aria_engine import (  # noqa: E402
    ARIAContext,
    ReadinessContext,
    SleepContext,
    TrainingContext,
)
from services.biometrics import BodyModel  # noqa: E402
from services.biometrics.types import MetricType, Observation  # noqa: E402


class BodyModelSleepDebtProjectionTests(unittest.TestCase):
    def test_projects_7d_debt_from_the_observation_series(self):
        # 7 nights at 6.0h against an 8.0h target = 14.0h debt.
        obs = [
            Observation(
                metric=MetricType.SLEEP_DURATION, value=6.0 * 60.0, unit="min",
                timestamp=datetime.datetime.now(datetime.timezone.utc) - datetime.timedelta(days=d),
            )
            for d in range(7)
        ]
        model = BodyModel.from_observations(obs)
        ctx = model.to_aria_context()
        self.assertEqual(ctx.sleep.sleep_debt_7d_hours, 14.0)
        self.assertEqual(ctx.sleep.target_hours, 8.0)

    def test_none_with_no_sleep_observations(self):
        model = BodyModel.from_observations([])
        ctx = model.to_aria_context()
        self.assertIsNone(ctx.sleep.sleep_debt_7d_hours)

    def test_only_the_last_7_nights_count(self):
        # 7 short nights (6h) then 7 full nights (8h, no debt) -- most recent
        # 7 observations should win, not the whole 14-night history.
        obs = []
        now = datetime.datetime.now(datetime.timezone.utc)
        for d in range(13, 6, -1):  # 7 short nights, oldest first
            obs.append(Observation(metric=MetricType.SLEEP_DURATION, value=6.0 * 60.0, unit="min",
                                    timestamp=now - datetime.timedelta(days=d)))
        for d in range(6, -1, -1):  # 7 full nights, most recent
            obs.append(Observation(metric=MetricType.SLEEP_DURATION, value=8.0 * 60.0, unit="min",
                                    timestamp=now - datetime.timedelta(days=d)))
        model = BodyModel.from_observations(obs)
        ctx = model.to_aria_context()
        self.assertEqual(ctx.sleep.sleep_debt_7d_hours, 0.0)

    def test_permission_denied_sleep_projects_no_debt(self):
        obs = [Observation(metric=MetricType.SLEEP_DURATION, value=300.0, unit="min",
                            timestamp=datetime.datetime.now(datetime.timezone.utc))]
        model = BodyModel.from_observations(obs)
        ctx = model.to_aria_context(aria_engine.DataPermissions({"sleep": False}))
        self.assertIsNone(ctx.sleep.sleep_debt_7d_hours)


def _ctx(**overrides) -> ARIAContext:
    base = dict(
        sleep=SleepContext(duration_minutes=420.0),
        readiness=ReadinessContext(recovery_score=80.0, hrv_7day_trend=1.0),
        training=TrainingContext(acwr=0.9, is_overtrained=False),
    )
    base.update(overrides)
    return ARIAContext(**base)


class StanceForPlanSleepDebtTests(unittest.TestCase):
    """brief=None is valid: stance_for_plan only reads getattr(brief, "stance", "")."""

    def test_high_7d_debt_forces_protect_even_with_a_proceed_brief(self):
        ctx = _ctx(sleep=SleepContext(duration_minutes=420.0, sleep_debt_7d_hours=6.0))
        self.assertEqual(fusion.stance_for_plan(None, ctx), "protect")

    def test_7d_debt_at_or_below_threshold_does_not_force_protect(self):
        ctx = _ctx(sleep=SleepContext(duration_minutes=420.0, sleep_debt_7d_hours=5.0))
        self.assertEqual(fusion.stance_for_plan(None, ctx), "proceed")

    def test_hrv_falling_plus_tonight_debt_forces_protect(self):
        ctx = _ctx(
            sleep=SleepContext(duration_minutes=300.0, sleep_debt_7d_hours=1.0),  # 5h tonight -> 3h tonight-debt
            readiness=ReadinessContext(recovery_score=80.0, hrv_7day_trend=-10.0),
        )
        self.assertEqual(fusion.stance_for_plan(None, ctx), "protect")

    def test_hrv_falling_alone_without_debt_does_not_force_protect(self):
        ctx = _ctx(
            sleep=SleepContext(duration_minutes=480.0, sleep_debt_7d_hours=0.0),
            readiness=ReadinessContext(recovery_score=80.0, hrv_7day_trend=-10.0),
        )
        self.assertEqual(fusion.stance_for_plan(None, ctx), "proceed")

    def test_still_protects_on_overtraining_unchanged(self):
        ctx = _ctx(training=TrainingContext(acwr=1.6, is_overtrained=True))
        self.assertEqual(fusion.stance_for_plan(None, ctx), "protect")


class ContextPlanSleepDebtTests(unittest.TestCase):
    def test_high_7d_debt_adds_wear_like_every_other_factor(self):
        # Tonight (7.0h) is deliberately neutral -- between the 6.5h/7.5h
        # single-night thresholds, so it contributes no wear of its own and
        # the 7-day figure's own contribution is isolated. evaluate_aging
        # combines factors (a single elevated RHR or conversation cue alone
        # doesn't unilaterally flip pace either); this checks the factor
        # itself fires and adds real weight, not that it overrides every
        # other signal single-handedly.
        base = _ctx(
            sleep=SleepContext(duration_minutes=420.0, sleep_debt_7d_hours=0.0),
            readiness=ReadinessContext(recovery_score=70.0, hrv_7day_trend=0.0),
        )
        with_debt = _ctx(
            sleep=SleepContext(duration_minutes=420.0, sleep_debt_7d_hours=8.0),
            readiness=ReadinessContext(recovery_score=70.0, hrv_7day_trend=0.0),
        )
        aging_base = context_plan.evaluate_aging(base)
        aging_debt = context_plan.evaluate_aging(with_debt)
        self.assertNotIn("sleep_debt_7d", [f.id for f in aging_base.factors])
        self.assertIn("sleep_debt_7d", [f.id for f in aging_debt.factors])
        self.assertGreater(aging_debt.wear, aging_base.wear)

    def test_low_7d_debt_does_not_trigger_the_factor(self):
        ctx = _ctx(sleep=SleepContext(duration_minutes=420.0, sleep_debt_7d_hours=2.0))
        aging = context_plan.evaluate_aging(ctx)
        self.assertNotIn("sleep_debt_7d", [f.id for f in aging.factors])

    def test_high_debt_week_combined_with_a_short_night_picks_a_protective_choice(self):
        """The exact shape of the scenario this gap was found from: a short
        single night (6.33h) plus a genuinely high 7-day debt (11.7h) --
        together they must cross the "faster" pace threshold and resolve to
        a protective plan choice, not train_through."""
        ctx = _ctx(
            sleep=SleepContext(duration_minutes=6.33 * 60.0, sleep_debt_7d_hours=11.7),
            readiness=ReadinessContext(recovery_score=65.0, hrv_7day_trend=-1.5),
            training=TrainingContext(acwr=0.63, is_overtrained=False),
        )
        aging = context_plan.evaluate_aging(ctx, "How's my recovery looking?")
        self.assertEqual(aging.pace, "faster")
        plan = context_plan.draft_plan("How's my recovery looking?", ctx, None)
        self.assertIn(plan.choice, ("sleep_first", "protect_load"))
        self.assertNotEqual(plan.choice, "train_through")


if __name__ == "__main__":
    unittest.main()
