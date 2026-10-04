"""Dummy perception: signals, case-by-case conflicts, posture, research needs."""

import sys
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner import perception as p  # noqa: E402
from backend.ai.simrunner.aria_simrunner import web_research  # noqa: E402

FEELS_GOOD_SHORT_NIGHT = (
    "You feel good, but last night ran short — I'll trust the feeling and cap the ceiling."
)
FEELS_LOW_NUMBERS_READY = (
    "Everything looks ready on paper, but you don't feel it — how you feel wins today."
)
HARD_DAY_EASY_BODY = (
    "You want a hard day on a body that's asking for an easy one — we'll bank the effort instead of spending it."
)


def ctx(sleep=7.8, readiness=80, debt=0.0, overtrained=False, trend="steady", streak=0, rest_days=1, chrono="lark"):
    return SimpleNamespace(
        today=SimpleNamespace(
            total_sleep_hours=sleep,
            readiness_score=readiness,
            workout_logged=False,
            workout_type="rest",
            deep_sleep_minutes=55,
            rem_sleep_minutes=90,
            hrv=58,
        ),
        sleep_debt_7d_hours=debt,
        is_overtrained=overtrained,
        readiness_trend=trend,
        training_streak=streak,
        days_since_last_workout=rest_days,
        chronotype=chrono,
    )


HOT = p.EnvironmentRead(apparent_temp_c=36, uv_index=9, us_aqi=40, precipitation_mm=0, is_day=True, source="open-meteo")
SMOKE = p.EnvironmentRead(apparent_temp_c=20, us_aqi=180, source="open-meteo")


class MatchingTests(unittest.TestCase):
    def test_word_boundaries(self):
        s = p.perceive("had brunch and protein, meeting at noon")
        self.assertEqual(s.conflicts, [])
        self.assertIsNone(s.signal("event"))

    def test_sick_of_is_not_illness(self):
        s = p.perceive("I'm sick of my job, want to go hard at the gym", ctx=ctx())
        self.assertIsNone(s.signal("illness"))
        self.assertEqual(s.posture, "push")


class ConflictTests(unittest.TestCase):
    def test_feels_great_but_short_night(self):
        s = p.perceive("I feel great, let's go hard on leg day", ctx=ctx(sleep=5.2, readiness=45))
        kinds = [c.kind for c in s.conflicts]
        self.assertIn("said_vs_measured", kinds)
        self.assertIn("intent_vs_recovery", kinds)
        self.assertTrue(s.decisions.keep_light)
        self.assertEqual(s.posture, "protect")
        self.assertEqual(s.spoken_line, FEELS_GOOD_SHORT_NIGHT)
        said = next(c.line for c in s.conflicts if c.kind == "said_vs_measured")
        intent = next(c.line for c in s.conflicts if c.kind == "intent_vs_recovery")
        self.assertEqual(said, FEELS_GOOD_SHORT_NIGHT)
        self.assertEqual(intent, HARD_DAY_EASY_BODY)
        self.assertEqual(dummy._apply_speak_guard(FEELS_GOOD_SHORT_NIGHT), FEELS_GOOD_SHORT_NIGHT)

    def test_feels_low_but_numbers_ready(self):
        s = p.perceive("I'm exhausted, what should I train?", ctx=ctx())
        self.assertIn("said_vs_measured", [c.kind for c in s.conflicts])
        self.assertEqual(s.spoken_line, FEELS_LOW_NUMBERS_READY)
        self.assertEqual(dummy._apply_speak_guard(FEELS_LOW_NUMBERS_READY), FEELS_LOW_NUMBERS_READY)

    def test_said_vs_measured_lines_survive_speak_guard_as_message_lead(self):
        rows = (
            (
                "I feel great, let's go hard on leg day",
                ctx(sleep=5.2, readiness=45),
                FEELS_GOOD_SHORT_NIGHT,
            ),
            (
                "I'm exhausted, what should I train?",
                ctx(),
                FEELS_LOW_NUMBERS_READY,
            ),
        )
        for prompt, body, line in rows:
            with self.subTest(prompt=prompt):
                with patch.object(web_research, "research", return_value=None):
                    row = dummy.respond(prompt, seed=3, engine="lambda", context=body)
                spoken = str(row.get("message") or "")
                guarded = dummy._apply_speak_guard(spoken)
                self.assertEqual(dummy._apply_speak_guard(line), line, prompt)
                self.assertTrue(spoken.startswith(line), spoken)
                self.assertTrue(guarded.startswith(line), guarded)
                self.assertEqual(guarded.split("\n", 1)[0][: len(line)], line)

    def test_banned_spoken_line_is_dropped_and_turn_still_leads(self):
        banned = "Your body is still paying for a short night — I'll trust the feeling."
        sit = SimpleNamespace(
            spoken_line=banned,
            decisions=SimpleNamespace(rest=False, refer_out=False, keep_light=True),
        )
        with patch.object(dummy, "_perceive_turn", return_value=(sit, None)):
            with patch.object(web_research, "research", return_value=None):
                row = dummy.respond(
                    "I'm exhausted, what should I train?",
                    seed=3,
                    engine="lambda",
                    context=ctx(),
                )
        spoken = str(row.get("message") or "")
        self.assertNotIn("your body is", spoken.lower(), spoken)
        self.assertTrue(spoken.strip(), spoken)
        self.assertFalse(spoken.startswith(banned), spoken)
        self.assertEqual(dummy._apply_speak_guard(banned), "")

    def test_illness_and_red_flags(self):
        sick = p.perceive("I have a fever, can I still run?", ctx=ctx())
        self.assertEqual(sick.posture, "rest")
        self.assertTrue(sick.decisions.rest)
        self.assertEqual(sick.research[0].topic, "fever")
        flag = p.perceive(
            "chest pain when I run", ctx=ctx(), guidance_band="emergency"
        )
        self.assertEqual(flag.posture, "refer")
        self.assertTrue(flag.decisions.refer_out)
        triage = p.perceive(
            "chest pain when I run", ctx=ctx(), guidance_band="triage"
        )
        self.assertFalse(triage.decisions.refer_out)
        coach = p.perceive("chest pain when I run", ctx=ctx())
        self.assertFalse(coach.decisions.refer_out)

    def test_event_taper(self):
        s = p.perceive("Wedding tomorrow, what should I train?", ctx=ctx())
        self.assertTrue(s.decisions.keep_light and s.decisions.shorten)
        self.assertEqual(s.signal("event").band, "tomorrow")
        self.assertEqual(p.event_days("race in three days"), 3)
        self.assertEqual(p.event_days("my marathon is next week"), 7)

    def test_injury(self):
        s = p.perceive("my knee hurts, can we still do a workout", ctx=ctx())
        self.assertIn("injury_vs_training", [c.kind for c in s.conflicts])
        self.assertIn("knee", s.spoken_line)

    def test_world_moves_training_inside(self):
        hot = p.perceive("going for a long run this afternoon", ctx=ctx(), environment=HOT)
        self.assertTrue(hot.decisions.move_indoors)
        self.assertIn("heat", [r.topic for r in hot.research])
        smoky = p.perceive("want to run outside", ctx=ctx(), environment=SMOKE)
        self.assertIn("air", smoky.spoken_line)
        calm = p.perceive("want to run outside", ctx=ctx(), environment=p.EnvironmentRead(apparent_temp_c=18, source="open-meteo"))
        self.assertFalse(calm.decisions.move_indoors)

    def test_late_hard_session(self):
        s = p.perceive("let's go hard in the gym", ctx=ctx(), local_hour=22)
        self.assertTrue(s.decisions.shorten)
        self.assertEqual(s.signal("time").band, "night")

    def test_missing_sleep_asks_first(self):
        s = p.perceive("what should I train?", ctx=ctx(sleep=None))
        self.assertTrue(s.decisions.ask_first)
        self.assertIn("last night's sleep", s.unknowns)


class FeedTests(unittest.TestCase):
    def test_feed_and_brief_carry_no_raw_numbers(self):
        s = p.perceive("I feel great, go hard today", ctx=ctx(sleep=5.0, readiness=40), environment=HOT, local_hour=7)
        feed = s.feed()
        self.assertEqual(feed["posture"], "protect")
        self.assertTrue(feed["signals"])
        brief = s.brief()
        self.assertIn("Posture: protect.", brief)
        self.assertNotRegex(brief, r"\d")

    def test_research_query_is_scrubbed(self):
        s = p.perceive("my name is Lee and I'm 34 — how much protein should I eat?")
        self.assertEqual(s.research[0].topic, "nutrition")
        self.assertNotIn("lee", s.research[0].query)
        self.assertNotIn("34", s.research[0].query)

    def test_plain_turn_needs_nothing(self):
        s = p.perceive("thanks!")
        self.assertEqual((s.posture, s.conflicts, s.research), ("steady", [], []))


if __name__ == "__main__":
    unittest.main()
