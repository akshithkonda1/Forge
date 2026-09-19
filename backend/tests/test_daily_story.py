"""Tests for services.daily_story — the narrative + insights layer built on
top of an already-fused ARIAContext. Pure function, no storage."""

from __future__ import annotations

import unittest
from datetime import datetime, timezone

import _bootstrap  # noqa: F401

from services import aria_engine  # noqa: E402
from services import daily_story  # noqa: E402
from services import fusion  # noqa: E402

NOW = datetime(2026, 6, 1, 9, 0, tzinfo=timezone.utc)


def _ctx(**overrides) -> aria_engine.ARIAContext:
    return aria_engine.ARIAContext(
        sleep=overrides.get("sleep", aria_engine.SleepContext()),
        readiness=overrides.get("readiness", aria_engine.ReadinessContext()),
        activity=overrides.get("activity", aria_engine.ActivityContext()),
        aging=overrides.get("aging", aria_engine.AgingContext()),
    )


class DailyStoryTests(unittest.TestCase):
    def test_empty_context_returns_none(self):
        self.assertIsNone(daily_story.build_daily_story(_ctx(), fusion.PersonalBaselines(), now=NOW))

    def test_aging_delta_from_apple_health_signals_cites_hrv(self):
        ctx = _ctx(aging=aria_engine.AgingContext(
            chronological_age_years=34, biological_age_years=32.5, delta_years=-1.5,
            state="younger", sources=["hrv", "vo2"],
        ))
        story = daily_story.build_daily_story(ctx, fusion.PersonalBaselines(), now=NOW)
        self.assertIsNotNone(story)
        self.assertEqual(story.insights[0].domain, "aging")
        self.assertIn("1.5", story.insights[0].text)
        self.assertIn("younger", story.insights[0].text)
        self.assertIn("recovery (HRV)", story.insights[0].text)
        self.assertIn("apple-health", story.sources)

    def test_vendor_aging_source_is_named_directly(self):
        """Once a vendor age (Whoop, Terra, ...) contributes, the source list
        carries "<vendor>:<kind>" and the narrative should name the vendor —
        no code change needed here when that day comes."""
        ctx = _ctx(aging=aria_engine.AgingContext(
            chronological_age_years=34, biological_age_years=32.5, delta_years=-1.5,
            state="younger", sources=["whoop:biological"],
        ))
        story = daily_story.build_daily_story(ctx, fusion.PersonalBaselines(), now=NOW)
        self.assertIsNotNone(story)
        self.assertIn("whoop", story.insights[0].text)
        self.assertIn("whoop", story.sources)

    def test_small_aging_delta_is_not_an_insight(self):
        ctx = _ctx(aging=aria_engine.AgingContext(
            chronological_age_years=34, biological_age_years=34.2, delta_years=0.2,
            state="matched", sources=["hrv"],
        ))
        self.assertIsNone(daily_story.build_daily_story(ctx, fusion.PersonalBaselines(), now=NOW))

    def test_falling_hrv_trend_is_a_readiness_insight(self):
        ctx = _ctx(readiness=aria_engine.ReadinessContext(hrv_7day_trend=-12, hrv_30day_baseline=55))
        story = daily_story.build_daily_story(ctx, fusion.PersonalBaselines(), now=NOW)
        self.assertIsNotNone(story)
        self.assertEqual(story.insights[0].domain, "readiness")
        self.assertIn("down", story.insights[0].text)

    def test_rising_hrv_trend_is_a_positive_readiness_insight(self):
        ctx = _ctx(readiness=aria_engine.ReadinessContext(hrv_7day_trend=11, hrv_30day_baseline=55))
        story = daily_story.build_daily_story(ctx, fusion.PersonalBaselines(), now=NOW)
        self.assertIsNotNone(story)
        self.assertIn("up", story.insights[0].text)

    def test_small_hrv_trend_is_not_an_insight(self):
        ctx = _ctx(readiness=aria_engine.ReadinessContext(hrv_7day_trend=2, hrv_30day_baseline=55))
        self.assertIsNone(daily_story.build_daily_story(ctx, fusion.PersonalBaselines(), now=NOW))

    def test_activity_above_personal_baseline(self):
        ctx = _ctx(activity=aria_engine.ActivityContext(steps_3day_avg=13000))
        baselines = fusion.PersonalBaselines(steps=8000, steps_n=10)
        story = daily_story.build_daily_story(ctx, baselines, now=NOW)
        self.assertIsNotNone(story)
        self.assertEqual(story.insights[0].domain, "activity")
        self.assertIn("more", story.insights[0].text)

    def test_activity_needs_a_personal_baseline_to_compare_against(self):
        ctx = _ctx(activity=aria_engine.ActivityContext(steps_3day_avg=13000))
        self.assertIsNone(daily_story.build_daily_story(ctx, fusion.PersonalBaselines(), now=NOW))

    def test_short_sleep_vs_personal_baseline(self):
        ctx = _ctx(sleep=aria_engine.SleepContext(duration_minutes=300))
        baselines = fusion.PersonalBaselines(sleep_duration_min=440, sleep_n=10)
        story = daily_story.build_daily_story(ctx, baselines, now=NOW)
        self.assertIsNotNone(story)
        self.assertEqual(story.insights[0].domain, "sleep")

    def test_narrative_leads_with_aging_over_activity(self):
        ctx = _ctx(
            aging=aria_engine.AgingContext(
                chronological_age_years=34, biological_age_years=32, delta_years=-2,
                state="younger", sources=["hrv"],
            ),
            activity=aria_engine.ActivityContext(steps_3day_avg=13000),
        )
        baselines = fusion.PersonalBaselines(steps=8000, steps_n=10)
        story = daily_story.build_daily_story(ctx, baselines, now=NOW)
        self.assertIsNotNone(story)
        self.assertTrue(story.narrative.startswith("Your training age"))

    def test_generated_at_defaults_to_now(self):
        ctx = _ctx(readiness=aria_engine.ReadinessContext(hrv_7day_trend=-12, hrv_30day_baseline=55))
        story = daily_story.build_daily_story(ctx, fusion.PersonalBaselines())
        self.assertIsNotNone(story)
        self.assertIsNotNone(story.generated_at)

    def test_to_dict_roundtrips_shape(self):
        ctx = _ctx(readiness=aria_engine.ReadinessContext(hrv_7day_trend=-12, hrv_30day_baseline=55))
        story = daily_story.build_daily_story(ctx, fusion.PersonalBaselines(), now=NOW)
        payload = story.to_dict()
        self.assertEqual(payload["generated_at"], NOW.isoformat())
        self.assertIsInstance(payload["insights"], list)
        self.assertEqual(payload["insights"][0]["domain"], "readiness")


if __name__ == "__main__":
    unittest.main()
