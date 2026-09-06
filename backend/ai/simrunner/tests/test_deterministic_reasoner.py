import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import deterministic_reasoner as dr
from backend.ai.simrunner.aria_simrunner import fake_health_bridge as bridge


class T:
    pass


def _ctx(
    *,
    sleep=5.5,
    ready=44,
    hrv=None,
    debt=6.0,
    trend="falling",
    hrv_trend="stable",
    over=False,
    streak=0,
    days=4,
    occ="teacher",
    chrono="bear",
    season="maintenance",
    last=None,
    logged=False,
    wtype=None,
    acwr=1.1,
    sparse=False,
):
    c = T()
    c.today = T()
    c.today.total_sleep_hours = sleep
    c.today.readiness_score = ready
    c.today.hrv = hrv
    c.today.workout_logged = logged
    c.today.workout_type = wtype
    c.today.acwr = acwr
    c.sleep_debt_7d_hours = debt
    c.readiness_trend = trend
    c.hrv_7d_trend = hrv_trend
    c.is_overtrained = over
    c.training_streak = streak
    c.days_since_last_workout = days
    c.has_sleep = sleep is not None
    c.has_hrv = hrv is not None
    c.is_data_sparse = sparse
    c.occupation = occ
    c.chronotype = chrono
    c.life_season = season
    c.last_workout_type = last
    c.has_notable_event = False
    c.notable_event_note = None
    c.acwr = acwr
    return c


class DeterministicReasonerTests(unittest.TestCase):
    def test_felt_bad_outranks_rebuilt_night(self):
        d, letter = dr.reason(
            _ctx(sleep=7.6, ready=70, debt=1.0, trend="stable"),
            "I slept badly last night",
            7,
        )
        self.assertEqual(d.action, "recover")
        self.assertGreater(letter.count("\n\n"), 3)

    def test_life_talk_does_not_become_a_workout(self):
        d, letter = dr.reason(
            _ctx(sleep=5.4, ready=44),
            "Work was brutal and I still have to show up for Sam and Maya. I am overwhelmed.",
            1,
        )
        self.assertEqual(d.action, "talk")
        self.assertIn("showing up", letter.lower())
        self.assertIn("44", letter)

    def test_letter_cites_real_figures(self):
        _, letter = dr.reason(
            _ctx(sleep=5.4, ready=44, occ="teacher"),
            "I slept badly — what should I train and eat?",
            1,
        )
        self.assertIn("5.4", letter)
        self.assertIn("44", letter)
        self.assertGreaterEqual(len(letter.split()), 180)

    def test_same_inputs_same_letter(self):
        a = dr.reason(_ctx(), "I slept badly", 9)
        b = dr.reason(_ctx(), "I slept badly", 9)
        self.assertEqual(a[0], b[0])
        self.assertEqual(a[1], b[1])

    def test_pack_bridge_feeds_reasoner(self):
        day = {
            "night": {"totalMinutes": 324, "deepMinutes": 48, "remMinutes": 62},
            "sleepScore": 44,
            "hrvMs": 39,
            "restingHR": 61,
            "workout": {"type": "strength", "name": "squat"},
            "social": [{"title": "Dinner out", "kind": "dinnerOut"}],
            "felt": "wrecked",
            "storyLine": "Late dinner, short night.",
            "personaLabel": "stressed",
            "acwr": 1.15,
            "sleepDebtHours": 6.2,
            "readinessTrend": "falling",
        }
        ctx = bridge.context_from_pack_day(day)
        self.assertAlmostEqual(ctx.today.total_sleep_hours, 5.4, places=1)
        self.assertEqual(ctx.today.hrv, 39.0)
        d, letter = dr.reason(ctx, "how was my day", 2)
        self.assertEqual(d.action, "talk")
        self.assertIn("5.4", letter)


if __name__ == "__main__":
    unittest.main()
