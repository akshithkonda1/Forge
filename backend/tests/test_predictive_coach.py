"""Tests for aria_core.readiness_forecast, user_working_model, and hobby_path.

Translated from ForgeCore ReadinessForecastTests / UserWorkingModelTests /
HobbyPathEngineTests so iOS and the ARIA engine cannot drift.
"""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core import hobby_path as hp  # noqa: E402
from aria_core import readiness_forecast as rf  # noqa: E402
from aria_core import user_working_model as uwm  # noqa: E402
from aria_core.aria_engine import (  # noqa: E402
    ARIAContext,
    LifestyleContext,
    ReadinessContext,
)


def _base_forecast(**overrides) -> rf.ForecastInput:
    data = dict(
        current_readiness=75,
        sleep_minutes=480,
        hrv_ms=60,
        hrv_baseline_ms=60,
        resting_hr=55,
        resting_hr_baseline=55,
        today_strain=8,
        stress_level=30,
    )
    data.update(overrides)
    return rf.ForecastInput(**data)


class ReadinessForecastTests(unittest.TestCase):
    def test_steady_day_holds(self):
        forecast = rf.forecast(_base_forecast())
        self.assertEqual(forecast.predicted_score, 75)
        self.assertEqual(forecast.posture, rf.STEADY)
        self.assertEqual(forecast.confidence, "medium")

    def test_heavy_load_and_sleep_debt_drags(self):
        forecast = rf.forecast(_base_forecast(sleep_minutes=360, today_strain=18))
        self.assertLess(forecast.predicted_score, 60)
        self.assertIn(forecast.posture, (rf.PROTECT, rf.REST))
        self.assertTrue(any(d.title == "Sleep debt" for d in forecast.drivers))
        self.assertTrue(any(d.title == "Heavy load today" for d in forecast.drivers))

    def test_chat_prompt_is_what_clients_send(self):
        forecast = rf.forecast(_base_forecast(
            current_readiness=40, sleep_minutes=300, today_strain=19, stress_level=80,
            hrv_ms=40,
        ))
        self.assertIn(str(forecast.predicted_score), forecast.chat_prompt)
        self.assertIn("How should I train around that?", forecast.chat_prompt)
        self.assertTrue(any(t.startswith("forecast:tomorrow:") for t in forecast.aria_tags))
        self.assertTrue(rf.keep_light(forecast.posture))

    def test_parse_tag(self):
        self.assertEqual(rf.parse_tag("forecast:tomorrow:61:protect"), (61, "protect"))
        self.assertIsNone(rf.parse_tag("habit:sleep:80"))


class UserWorkingModelTests(unittest.TestCase):
    def test_overreacher_caps_heroics(self):
        snap = uwm.snapshot(uwm.WorkingInput(
            habit_streak_days=6,
            today_habit_completion=1,
            weekly_mood_0_to_10=6,
            acwr=1.7,
            sleep_scores=[62, 58],
            readiness_today=52,
            high_strain_low_recovery_days=4,
        ))
        self.assertEqual(snap.tendency, uwm.OVERREACHER)
        self.assertEqual(snap.stance, uwm.CAP_HEROICS)
        self.assertIn("working:overreacher:cap_heroics", snap.aria_tags)
        self.assertIn("cap heroics", snap.steering_line.lower())

    def test_copy_never_claims_clinical_mental_health(self):
        snap = uwm.snapshot(uwm.WorkingInput(
            weekly_mood_0_to_10=2, high_strain_low_recovery_days=4,
        ))
        blob = (snap.steering_line + " " + " ".join(d.detail for d in snap.drivers)).lower()
        for needle in ("diagnos", "depress", "disorder", "prescrib", "therap", "clinical"):
            self.assertNotIn(needle, blob)


class HobbyPathTests(unittest.TestCase):
    def test_reserved_opens_gently(self):
        working = uwm.snapshot(uwm.WorkingInput(
            habit_streak_days=6, weekly_mood_0_to_10=7, acwr=1.05,
        ))
        snap = hp.snapshot(2, [], working)
        self.assertEqual(snap.social_band, hp.RESERVED)
        self.assertEqual(snap.path, hp.OPEN_GENTLY)
        self.assertTrue(any(s.hobby in ("cooking", "outdoors") for s in snap.suggestions))
        self.assertIn("alone", snap.coaching_line.lower())
        self.assertIn("hobby_path:open_gently", snap.aria_tags)
        self.assertEqual(snap.people_energy, hp.THIN)
        self.assertEqual(snap.free_day_window, hp.EVENING)

    def test_over_social_overreach_restores_quiet(self):
        working = uwm.snapshot(uwm.WorkingInput(
            habit_streak_days=6, acwr=1.7, high_strain_low_recovery_days=4,
            weekly_mood_0_to_10=3,
        ))
        snap = hp.snapshot(9, ["gym", "outdoors"], working)
        self.assertEqual(snap.social_band, hp.BURNED_OUT)
        self.assertEqual(snap.path, hp.RESTORE_QUIET)
        self.assertTrue(any(s.hobby in ("reading", "rest") for s in snap.suggestions))
        self.assertFalse(any(s.hobby == "gym" for s in snap.suggestions))
        self.assertEqual(snap.people_energy, hp.THIN)
        self.assertEqual(snap.free_day_window, hp.AFTERNOON)

    def test_night_owl_gets_evening_not_a_morning_club(self):
        working = uwm.snapshot(uwm.WorkingInput(
            habit_streak_days=6, weekly_mood_0_to_10=7, acwr=1.05,
        ))
        snap = hp.snapshot(6, ["music"], working, tomorrow_posture="steady", wake_hour=10.5)
        self.assertEqual(snap.free_day_window, hp.EVENING)
        self.assertIn("hobby_window:evening", snap.aria_tags)

    def test_protect_tomorrow_caps_people_energy(self):
        working = uwm.snapshot(uwm.WorkingInput(
            habit_streak_days=6, weekly_mood_0_to_10=7, acwr=1.05,
        ))
        snap = hp.snapshot(8, ["music"], working, tomorrow_posture="protect", wake_hour=7)
        self.assertEqual(snap.people_energy, hp.THIN)


class AriaEnginePredictionTests(unittest.TestCase):
    def test_user_model_block_names_tomorrow_forecast(self):
        ctx = ARIAContext(
            readiness=ReadinessContext(
                recovery_score=70,
                tomorrow_predicted_score=54,
                tomorrow_posture="protect",
                tomorrow_confidence="medium",
                tomorrow_recommendation="Cap intensity tomorrow.",
            )
        )
        block = ctx.user_model_block()
        self.assertIn("readiness.tomorrow: 54/100", block)
        self.assertIn("posture=protect", block)
        self.assertIn("never a medical claim", block)

    def test_working_and_hobby_tags_steer_lifestyle_signal(self):
        from aria_core import aria_engine as engine

        ctx = ARIAContext(
            lifestyle=LifestyleContext(
                recent_patterns=[
                    "working:overreacher:cap_heroics",
                    "hobby_path:restore_quiet",
                    "hobby_people:thin",
                ]
            )
        )
        signal = engine._working_model_signal(ctx)
        self.assertIsNotNone(signal)
        self.assertIn("cap heroics", signal.interpretation.lower())
        self.assertIn("quiet", signal.interpretation.lower())
        self.assertIn("people-energy", signal.interpretation.lower())


class CoachContextHobbyTests(unittest.TestCase):
    def test_living_chips_steer_hobby_path(self):
        from services import coach_context

        ctx = {
            "readiness": {"overall": 72, "hrv": 60, "restingHR": 55, "stressLevel": 30},
            "recentSleep": [{"totalHours": 8, "score": 80, "date": "2026-10-04"}],
            "recentWorkouts": [],
            "lifestyleTags": ["living:hobby:cooking", "living:social:2"],
            "chronotype": {"typicalWakeTime": "10:30"},
        }
        out = coach_context._attach_predictions(ctx)
        hobby = out["hobbyPath"]
        self.assertEqual(hobby["path"], "open_gently")
        self.assertEqual(hobby["peopleEnergy"], "thin")
        self.assertEqual(hobby["freeDayWindow"], "evening")
        block = coach_context.context_to_prompt_block(out)
        self.assertIn("open_gently", block)
        self.assertIn("peopleEnergy", block)


class ReplyShapeTests(unittest.TestCase):
    def test_estimate_wins_and_stays_non_clinical(self):
        from aria_core import reply_shape as rs

        shape = rs.shape(
            "what should I train tomorrow",
            ["working:overreacher:cap_heroics", "hobby_people:thin"],
            True,
            True,
            True,
        )
        self.assertEqual(shape.lanes, [rs.ESTIMATE])
        self.assertIn("estimate", shape.chip_label.lower())
        blob = (shape.headline + shape.detail).lower()
        for needle in ("diagnos", "disorder", "prescrib", "therap", "clinical"):
            self.assertNotIn(needle, blob)

    def test_hobby_ask_names_people_energy(self):
        from aria_core import reply_shape as rs

        shape = rs.shape(
            "help me pick a hobby",
            ["hobby_path:restore_quiet", "hobby_people:thin"],
            True,
            False,
            False,
        )
        self.assertIn(rs.HOBBY, shape.lanes)
        self.assertIn(rs.LOCAL, shape.lanes)
        self.assertTrue(shape.chip_label.startswith("What shaped this"))
        self.assertTrue(
            "people-energy" in shape.headline.lower()
            or "people-energy" in shape.detail.lower()
            or "quiet" in shape.detail.lower()
        )


