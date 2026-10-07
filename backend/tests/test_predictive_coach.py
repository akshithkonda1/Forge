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
            "lifestyleTags": [
                "living:hobby:cooking",
                "living:social:2",
                "people:Sam:partner",
                "people:5551212:friend",
                "people:sam@x.com:friend",
            ],
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
        self.assertEqual(out["tomorrowBudgets"]["constraint"], "people")
        self.assertIn("people-budget", out["tomorrowBudgets"]["coachingLine"].lower())
        self.assertIn("Sam", out["hobbyPath"]["coachingLine"])
        self.assertNotIn("555", out["hobbyPath"]["coachingLine"])
        self.assertNotIn("@", out["hobbyPath"]["coachingLine"])
        self.assertEqual(out["mentality_signal"], "quiet")
        self.assertEqual(out["hobbies"][0]["id"], "cooking")
        self.assertEqual(out["hobbies"][0]["kind"], "creative")
        self.assertNotIn("mentality:", " ".join(ctx["lifestyleTags"]))
        self.assertIn("quiet stretch", block)
        self.assertNotIn("drained_social", block)
        self.assertNotIn("mentality_signal", block)


class TomorrowBudgetTests(unittest.TestCase):
    def test_green_body_thin_people_is_a_split(self):
        from aria_core import tomorrow_budgets as tb

        snap = tb.snapshot("push", "keep_rhythm", "thin")
        self.assertEqual(snap.constraint, tb.PEOPLE)
        self.assertTrue(snap.is_split)
        self.assertIn("people-budget", snap.coaching_line.lower())

    def test_cap_heroics_thins_the_body_on_a_push_score(self):
        from aria_core import tomorrow_budgets as tb

        snap = tb.snapshot("push", "cap_heroics", "open")
        self.assertEqual(snap.constraint, tb.BODY)

    def test_reply_names_the_split(self):
        from aria_core import reply_shape as rs

        shape = rs.shape(
            "How should I train around tomorrow?",
            ["forecast:tomorrow:80:push", "tomorrow_budget:people"],
            False,
            False,
            False,
        )
        self.assertIn("shape:budget", shape.lanes)
        self.assertIn("people-budget", shape.detail.lower())


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


def _working(tendency, stance="keep_rhythm", feel="mixed"):
    return uwm.Snapshot(
        tendency=tendency,
        stance=stance,
        predicted_feel=feel,
        confidence="low",
        drivers=[],
        steering_line="",
    )


class HobbyFitTests(unittest.TestCase):
    def test_four_mentality_values_and_speak_phrases(self):
        from aria_core import hobby_fit as hf

        cases = [
            (hp.RESERVED, hp.THIN, _working(uwm.PROTECTOR), hf.QUIET, "quiet stretch"),
            (hp.SOCIABLE, hp.OPEN, _working(uwm.STEADY, feel=uwm.AVAILABLE), hf.OPEN, "up for a little more"),
            (hp.BURNED_OUT, hp.THIN, _working(uwm.OVERREACHER), hf.DRAINED_SOCIAL, "lots on lately"),
            (hp.MIXED, hp.ENOUGH, _working(uwm.REBUILDING, uwm.REBUILD_TRUST), hf.RESTORED, "a calmer patch"),
        ]
        for band, energy, working, signal, phrase in cases:
            got = hf.mentality_signal(band, energy, working)
            self.assertEqual(got, signal)
            self.assertEqual(hf.speak(got), phrase)
            line = hf.canon_line(got)
            self.assertTrue(hf.speech_is_clean(line), line)
            self.assertNotIn("drained_social", line)
            self.assertNotIn("introvert", line.lower())

    def test_canon_samples_and_dismissal(self):
        from aria_core import hobby_fit as hf

        self.assertIn("quieter stretch", hf.canon_line(hf.QUIET))
        self.assertIn("lumpy bowl", hf.canon_line(hf.QUIET, curious=True))
        self.assertIn("Lots on lately", hf.canon_line(hf.DRAINED_SOCIAL))
        self.assertIn("skip group stuff", hf.canon_line(hf.DRAINED_SOCIAL, skip_groups=True))
        cool = hf.cool_down_line("Hike club")
        self.assertEqual(
            cool,
            "Hike club's still around if you ever want another look. It's not going anywhere.",
        )
        self.assertEqual(hf.on_dismissal("Hike club"), "")
        self.assertNotIn("Hike", hf.on_dismissal("Hike club"))
        self.assertTrue(hf.speech_is_clean(cool))

    def test_hobbies_shape_drops_pii_and_stays_out_of_patterns(self):
        from aria_core import hobby_fit as hf
        from services import coach_context

        rows = hf.normalize_hobbies([
            {
                "id": "pottery",
                "label": "Pottery nights",
                "kind": "creative",
                "interest": "high",
                "last_engaged_at": "2026-10-01",
            },
            {"label": "sam@x.com", "kind": "social"},
            {"label": "Call 5551212"},
        ])
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["id"], "pottery")
        self.assertEqual(rows[0]["kind"], "creative")
        self.assertEqual(rows[0]["interest"], "high")
        self.assertEqual(rows[0]["last_engaged_at"], "2026-10-01")

        patterns = ["living:social:2", "mentality:drained_social"]
        ctx = {
            "readiness": {"overall": 70},
            "recentSleep": [],
            "recentWorkouts": [],
            "lifestyleTags": ["living:social:2", "living:hobby:reading"],
            "lifestyle": {"recentPatterns": list(patterns)},
            "hobbies": rows + [{"label": "partner_cycle:day secret book"}],
        }
        out = coach_context._attach_predictions(ctx)
        self.assertEqual(out["mentality_signal"], "quiet")
        self.assertEqual(out["hobbies"][0]["label"], "Pottery nights")
        self.assertNotIn("sam@", str(out["hobbies"]))
        result_patterns = out["lifestyle"]["recentPatterns"]
        for p in patterns:
            self.assertIn(p, result_patterns)
        self.assertTrue(
            any(p.startswith("forecast:tomorrow:") for p in result_patterns),
            "picture tags should be injected into recentPatterns",
        )
        block = coach_context.context_to_prompt_block(out)
        self.assertIn("quiet stretch", block)
        self.assertIn("Pottery nights", block)
        self.assertNotIn("drained_social", block)
        self.assertNotIn("@", block)

    def test_chat_speaks_phrase_and_memory_drops_enum(self):
        from aria_core import aria_engine
        from aria_core import hobby_fit as hf
        from routes.aria import sanitize_inbound_chat_payload

        line = hf.chat_line(
            "help me pick a hobby",
            ["hobby_social:burned_out", "hobby_people:thin", "people:Sam:partner", "people:5551212:friend"],
        )
        self.assertIn("Lots on lately", line)
        self.assertIn("Sam", line)
        self.assertNotIn("555", line)
        self.assertNotIn("drained_social", line)

        ctx = ARIAContext(
            lifestyle=LifestyleContext(
                tags=["hobby_social:reserved", "hobby_people:thin"],
                recent_patterns=["mentality:drained_social", "hobby_row:pottery"],
            )
        )
        resp = aria_engine.generate_response("help me pick a quiet hobby", ctx, seed=0)
        spoken = f"{resp.get('prose_summary', '')} {resp.get('message', '')}"
        self.assertIn("quieter stretch", spoken)
        self.assertNotIn("drained_social", spoken)
        self.assertTrue(hf.speech_is_clean(spoken) or "drained_social" not in spoken)

        memory = aria_engine._memory_block_from_ctx(ctx)
        self.assertNotIn("drained_social", memory)
        self.assertNotIn("hobby_row", memory)

        clean = sanitize_inbound_chat_payload({
            "message": "help me pick a hobby",
            "hobbies": [{"label": "Pottery nights", "kind": "creative", "interest": "low"}],
            "recentPatterns": ["mentality:open", "living:hobby:cooking"],
            "context": {"lifestyle": {"recentPatterns": ["mentality_signal:restored"]}},
        })
        self.assertEqual(clean["hobbies"][0]["label"], "Pottery nights")
        self.assertEqual(clean["hobbies"][0]["kind"], "creative")
        self.assertNotIn("mentality:open", clean["recentPatterns"])
        self.assertIn("living:hobby:cooking", clean["recentPatterns"])
        self.assertNotIn(
            "mentality_signal:restored",
            clean["context"]["lifestyle"]["recentPatterns"],
        )
        self.assertNotIn("hobbies", clean["recentPatterns"])


class PictureTagsFlowTests(unittest.TestCase):
    """Verify that PredictiveCoach.picture ariaTags thread into
    coach_context recentPatterns and aria_engine responses."""

    def test_attach_predictions_injects_picture_tags_into_patterns(self):
        from services import coach_context

        ctx = {
            "readiness": {"overall": 72, "hrv": 60, "restingHR": 55, "stressLevel": 30},
            "recentSleep": [{"totalHours": 8, "score": 80, "date": "2026-10-04"}],
            "recentWorkouts": [],
            "lifestyle": {"tags": [], "recentPatterns": []},
        }
        out = coach_context._attach_predictions(ctx)
        patterns = out["lifestyle"]["recentPatterns"]
        has_forecast = any(p.startswith("forecast:tomorrow:") for p in patterns)
        has_working = any(p.startswith("working:") for p in patterns)
        has_budget = any(p.startswith("tomorrow_budget:") for p in patterns)
        self.assertTrue(has_forecast, f"Missing forecast tag in {patterns}")
        self.assertTrue(has_working, f"Missing working tag in {patterns}")
        self.assertTrue(has_budget, f"Missing budget tag in {patterns}")
        has_hobby = any(
            p.startswith("hobby_path:") or p.startswith("hobby_social:")
            or p.startswith("hobby_window:") or p.startswith("hobby_people:")
            for p in patterns
        )
        self.assertFalse(has_hobby, f"Hobby tags must not be in recentPatterns: {patterns}")

    def test_coaching_line_strings_match_iris_copy(self):
        """Coaching lines must match the Iris-approved copy exactly."""
        from aria_core import tomorrow_budgets as tb

        self.assertEqual(
            tb.coaching_line(tb.BOTH),
            "Tomorrow both budgets are thin. A short walk or nothing \u2014 no hero session, no extra plans.",
        )
        self.assertEqual(
            tb.coaching_line(tb.PEOPLE),
            "Split day. Your body can take the session. Your people-budget can't take another packed calendar.",
        )
        self.assertIn("body-budget", tb.coaching_line(tb.BODY))
        self.assertNotIn("thin body.", tb.coaching_line(tb.BODY))
        self.assertIn("no need to burn both", tb.coaching_line(tb.NEITHER))
        self.assertNotIn("prove", tb.coaching_line(tb.NEITHER))

    def test_budget_tag_is_consistent_between_home_and_chat(self):
        """The budget tag in recentPatterns must match what Home shows
        from tomorrowBudgets."""
        from services import coach_context

        ctx = {
            "readiness": {"overall": 72, "hrv": 60, "restingHR": 55, "stressLevel": 30},
            "recentSleep": [{"totalHours": 8, "score": 80, "date": "2026-10-04"}],
            "recentWorkouts": [],
            "lifestyleTags": ["living:social:2"],
            "lifestyle": {"tags": ["living:social:2"], "recentPatterns": []},
            "chronotype": {"typicalWakeTime": "07:00"},
        }
        out = coach_context._attach_predictions(ctx)
        budget_dict = out["tomorrowBudgets"]
        expected_tag = f"tomorrow_budget:{budget_dict['constraint']}"
        patterns = out["lifestyle"]["recentPatterns"]
        self.assertIn(expected_tag, patterns)

    def test_chat_response_cites_budget_when_tag_present(self):
        """generate_response must include budget coaching line when
        tomorrow_budget: tag is in lifestyle.recent_patterns."""
        from aria_core import aria_engine
        from aria_core import tomorrow_budgets as tb

        ctx = ARIAContext(
            readiness=ReadinessContext(
                recovery_score=70,
                tomorrow_predicted_score=80,
                tomorrow_posture="push",
            ),
            lifestyle=LifestyleContext(
                recent_patterns=[
                    "working:steady:keep_rhythm",
                    "tomorrow_budget:people",
                ],
            ),
        )
        resp = aria_engine.generate_response("how should I train tomorrow", ctx, seed=0)
        blob = f"{resp.get('prose_summary', '')} {resp.get('message', '')}"
        self.assertIn("people", blob.lower())

    def test_chat_response_omits_budget_when_neither(self):
        """If budget is 'neither', the coaching line should NOT appear."""
        from aria_core import aria_engine

        ctx = ARIAContext(
            readiness=ReadinessContext(recovery_score=70),
            lifestyle=LifestyleContext(
                recent_patterns=[
                    "working:steady:keep_rhythm",
                    "tomorrow_budget:neither",
                ],
            ),
        )
        resp = aria_engine.generate_response("how should I train tomorrow", ctx, seed=0)
        blob = f"{resp.get('prose_summary', '')} {resp.get('message', '')}"
        self.assertNotIn("Split day", blob)

    def test_overreacher_budget_body_flows_through(self):
        """An overreacher with cap_heroics should produce a body budget
        that flows from picture through to the response."""
        from services import coach_context
        from aria_core import tomorrow_budgets as tb

        ctx = {
            "readiness": {"overall": 52, "hrv": 40, "restingHR": 72, "stressLevel": 70},
            "recentSleep": [
                {"totalHours": 5.5, "score": 58, "date": "2026-10-04"},
                {"totalHours": 6, "score": 62, "date": "2026-10-03"},
            ],
            "recentWorkouts": [
                {"date": "2026-10-04", "intensity": "high", "duration": 60},
                {"date": "2026-10-03", "intensity": "high", "duration": 55},
                {"date": "2026-10-02", "intensity": "high", "duration": 50},
            ],
            "recoveryTrend": {"delta": -5},
            "lifestyle": {"tags": [], "recentPatterns": []},
        }
        out = coach_context._attach_predictions(ctx)
        patterns = out["lifestyle"]["recentPatterns"]
        budget_tags = [p for p in patterns if p.startswith("tomorrow_budget:")]
        self.assertTrue(len(budget_tags) > 0, "No budget tag found")
        budget_val = budget_tags[0].split(":")[1]
        self.assertEqual(budget_val, out["tomorrowBudgets"]["constraint"])


class NyxFailClosedPinTests(unittest.TestCase):
    """Nyx eval harness: fail-closed pins that break the build when the
    engine leaks tokens, cites the wrong budget, or drifts from Iris copy."""

    _ENGINE_TOKENS = (
        "tomorrow_budget:", "working:", "forecast:", "hobby_path:",
        "hobby:", "hobby_social:", "hobby_people:", "hobby_window:",
        "mentality:", "mentality_signal:",
    )
    _VAULT_DUMPS = (
        "drained_social", "partner_cycle", "cycle_day",
        "meds:", "calendar_title:", "people:",
    )

    def _spoken(self, resp: dict) -> str:
        return f"{resp.get('prose_summary') or ''} {resp.get('message') or ''}"

    # ------------------------------------------------------------------
    # Pin 1 — Home↔chat budget mismatch must fail
    # ------------------------------------------------------------------
    def test_home_chat_budget_match_people(self):
        """Spoken message must cite the same budget that Home's picture
        computed — PEOPLE scenario."""
        from services import coach_context
        from aria_core import aria_engine
        from aria_core import tomorrow_budgets as tb

        ctx = {
            "readiness": {"overall": 72, "hrv": 60, "restingHR": 55, "stressLevel": 30},
            "recentSleep": [{"totalHours": 8, "score": 80, "date": "2026-10-04"}],
            "recentWorkouts": [],
            "lifestyleTags": ["living:social:2"],
            "lifestyle": {"tags": ["living:social:2"], "recentPatterns": []},
            "chronotype": {"typicalWakeTime": "07:00"},
        }
        out = coach_context._attach_predictions(ctx)
        home_constraint = out["tomorrowBudgets"]["constraint"]
        home_coaching = tb.coaching_line(home_constraint)
        patterns = out["lifestyle"]["recentPatterns"]
        aria_ctx = ARIAContext(
            readiness=ReadinessContext(
                recovery_score=72,
                tomorrow_predicted_score=75,
                tomorrow_posture="push",
            ),
            lifestyle=LifestyleContext(recent_patterns=list(patterns)),
        )
        resp = aria_engine.generate_response(
            "how should I train tomorrow", aria_ctx, seed=0,
        )
        spoken = self._spoken(resp)
        if home_constraint not in (tb.NEITHER,):
            self.assertIn(
                home_coaching, spoken,
                f"Chat cited a different budget than Home: "
                f"home={home_constraint!r}, spoken={spoken!r}",
            )

    def test_home_chat_budget_match_body(self):
        """Overreacher scenario: Home shows BODY budget; chat must agree."""
        from services import coach_context
        from aria_core import aria_engine
        from aria_core import tomorrow_budgets as tb

        ctx = {
            "readiness": {"overall": 52, "hrv": 40, "restingHR": 72, "stressLevel": 70},
            "recentSleep": [
                {"totalHours": 5.5, "score": 58, "date": "2026-10-04"},
                {"totalHours": 6, "score": 62, "date": "2026-10-03"},
            ],
            "recentWorkouts": [
                {"date": "2026-10-04", "intensity": "high", "duration": 60},
                {"date": "2026-10-03", "intensity": "high", "duration": 55},
                {"date": "2026-10-02", "intensity": "high", "duration": 50},
            ],
            "recoveryTrend": {"delta": -5},
            "lifestyle": {"tags": [], "recentPatterns": []},
        }
        out = coach_context._attach_predictions(ctx)
        home_constraint = out["tomorrowBudgets"]["constraint"]
        home_coaching = tb.coaching_line(home_constraint)
        patterns = out["lifestyle"]["recentPatterns"]
        aria_ctx = ARIAContext(
            readiness=ReadinessContext(
                recovery_score=52,
                tomorrow_predicted_score=45,
                tomorrow_posture="protect",
            ),
            lifestyle=LifestyleContext(recent_patterns=list(patterns)),
        )
        resp = aria_engine.generate_response(
            "how should I train tomorrow", aria_ctx, seed=0,
        )
        spoken = self._spoken(resp)
        if home_constraint not in (tb.NEITHER,):
            self.assertIn(
                home_coaching, spoken,
                f"Chat cited a different budget than Home: "
                f"home={home_constraint!r}, spoken={spoken!r}",
            )

    # ------------------------------------------------------------------
    # Pin 2 — engine tokens / vault dumps must never appear in spoken
    # ------------------------------------------------------------------
    def test_spoken_never_leaks_engine_tokens(self):
        """message/prose_summary must not contain raw engine token
        prefixes like tomorrow_budget:, working:, forecast:, hobby:."""
        from aria_core import aria_engine

        ctx = ARIAContext(
            readiness=ReadinessContext(
                recovery_score=70,
                tomorrow_predicted_score=80,
                tomorrow_posture="push",
            ),
            lifestyle=LifestyleContext(
                recent_patterns=[
                    "working:steady:keep_rhythm",
                    "tomorrow_budget:people",
                    "forecast:tomorrow:80:push",
                    "hobby_path:restore_quiet",
                    "hobby_people:thin",
                ],
                tags=[
                    "mentality:drained_social",
                    "people:Sam:partner",
                    "people:555-1212:friend",
                ],
            ),
        )
        resp = aria_engine.generate_response(
            "how should I train tomorrow", ctx, seed=0,
        )
        spoken = self._spoken(resp)
        for token in self._ENGINE_TOKENS:
            self.assertNotIn(
                token, spoken,
                f"Engine token {token!r} leaked into spoken: {spoken!r}",
            )

    def test_spoken_never_leaks_vault_dumps(self):
        """message/prose_summary must not contain raw vault terms like
        drained_social, partner_cycle, meds:, calendar_title:, people:."""
        from aria_core import aria_engine

        ctx = ARIAContext(
            readiness=ReadinessContext(recovery_score=70),
            lifestyle=LifestyleContext(
                recent_patterns=[
                    "working:overreacher:cap_heroics",
                    "tomorrow_budget:body",
                    "mentality:drained_social",
                ],
                tags=[
                    "people:Sam:partner",
                    "people:555-1212:friend",
                    "meds:ibuprofen",
                    "calendar_title:dentist 9am",
                    "partner_cycle:day_14",
                ],
            ),
        )
        resp = aria_engine.generate_response(
            "what should I do tomorrow", ctx, seed=0,
        )
        spoken = self._spoken(resp)
        for dump in self._VAULT_DUMPS:
            self.assertNotIn(
                dump, spoken,
                f"Vault dump {dump!r} leaked into spoken: {spoken!r}",
            )

    def test_spoken_no_mentality_enum_tokens(self):
        """Mentality enum values must never appear verbatim in spoken."""
        from aria_core import aria_engine

        for mentality in ("drained_social", "restored", "quiet", "open"):
            tag = f"mentality:{mentality}"
            ctx = ARIAContext(
                lifestyle=LifestyleContext(
                    recent_patterns=[tag, "working:steady:keep_rhythm"],
                ),
            )
            resp = aria_engine.generate_response(
                "help me pick a hobby", ctx, seed=0,
            )
            spoken = self._spoken(resp)
            self.assertNotIn(
                f"mentality:{mentality}", spoken,
                f"Raw mentality tag leaked: {tag!r} in {spoken!r}",
            )

    # ------------------------------------------------------------------
    # Pin 3 — Iris coaching_line exact match + _budget_notice skip
    # ------------------------------------------------------------------
    def test_iris_coaching_line_both_exact(self):
        from aria_core import tomorrow_budgets as tb
        self.assertEqual(
            tb.coaching_line(tb.BOTH),
            "Tomorrow both budgets are thin. A short walk or nothing "
            "\u2014 no hero session, no extra plans.",
        )

    def test_iris_coaching_line_people_includes_packed_calendar(self):
        from aria_core import tomorrow_budgets as tb
        line = tb.coaching_line(tb.PEOPLE)
        self.assertIn("can't take another packed calendar", line)

    def test_iris_coaching_line_body_exact(self):
        from aria_core import tomorrow_budgets as tb
        self.assertEqual(
            tb.coaching_line(tb.BODY),
            "Split day. People are fine if you want them. "
            "Don't stack a hard session on a thin body-budget.",
        )

    def test_iris_coaching_line_neither_includes_no_need_to_burn(self):
        from aria_core import tomorrow_budgets as tb
        line = tb.coaching_line(tb.NEITHER)
        self.assertIn("no need to burn both", line)
        self.assertNotIn("prove", line)

    def test_budget_notice_skips_neither(self):
        """_budget_notice must return None for NEITHER — fail closed."""
        from aria_core import aria_engine

        ctx = ARIAContext(
            lifestyle=LifestyleContext(
                recent_patterns=["tomorrow_budget:neither"],
            ),
        )
        result = aria_engine._budget_notice(ctx)
        self.assertIsNone(
            result, "_budget_notice must skip NEITHER, got: {!r}".format(result),
        )

    def test_budget_notice_returns_line_for_people(self):
        from aria_core import aria_engine
        from aria_core import tomorrow_budgets as tb

        ctx = ARIAContext(
            lifestyle=LifestyleContext(
                recent_patterns=["tomorrow_budget:people"],
            ),
        )
        result = aria_engine._budget_notice(ctx)
        self.assertEqual(result, tb.coaching_line(tb.PEOPLE))

    def test_budget_notice_returns_line_for_body(self):
        from aria_core import aria_engine
        from aria_core import tomorrow_budgets as tb

        ctx = ARIAContext(
            lifestyle=LifestyleContext(
                recent_patterns=["tomorrow_budget:body"],
            ),
        )
        result = aria_engine._budget_notice(ctx)
        self.assertEqual(result, tb.coaching_line(tb.BODY))

    def test_budget_notice_returns_none_when_no_tag(self):
        from aria_core import aria_engine

        ctx = ARIAContext(
            lifestyle=LifestyleContext(
                recent_patterns=["working:steady:keep_rhythm"],
            ),
        )
        result = aria_engine._budget_notice(ctx)
        self.assertIsNone(result)
