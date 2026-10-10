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

    def test_heavy_load_after_a_short_night_drags(self):
        # A 6h night already shows up as today's 58 — it is not charged twice.
        forecast = rf.forecast(_base_forecast(
            current_readiness=58, sleep_minutes=360, today_strain=18,
        ))
        self.assertLess(forecast.predicted_score, 60)
        self.assertIn(forecast.posture, (rf.PROTECT, rf.REST))
        self.assertTrue(any(d.title == "Heavy load today" for d in forecast.drivers))
        self.assertFalse(any(d.title == "Sleep debt" for d in forecast.drivers))

    def test_last_night_is_not_double_counted(self):
        # Same readiness today, different last night: tomorrow does not move,
        # because today's score already holds last night.
        rested = rf.forecast(_base_forecast(current_readiness=60, sleep_minutes=480))
        short = rf.forecast(_base_forecast(current_readiness=60, sleep_minutes=330))
        self.assertEqual(rested.predicted_score, short.predicted_score)

    def test_low_day_bounces_partway_back(self):
        forecast = rf.forecast(_base_forecast(
            current_readiness=45, sleep_minutes=300, today_strain=5,
        ))
        # 75 + 0.5 * (45 - 75) = 60: halfway home, not all the way.
        self.assertEqual(forecast.predicted_score, 60)
        bounce = next(d for d in forecast.drivers if d.title == "Bounce-back")
        self.assertEqual(bounce.impact, 15)
        self.assertIn("short sleep", bounce.detail)

    def test_high_day_eases_back(self):
        forecast = rf.forecast(_base_forecast(current_readiness=95, today_strain=5))
        self.assertEqual(forecast.predicted_score, 85)
        self.assertTrue(any(d.title == "Easing to your usual" for d in forecast.drivers))

    def test_personal_baseline_is_the_anchor(self):
        forecast = rf.forecast(_base_forecast(
            current_readiness=70, readiness_baseline=82, today_strain=5,
        ))
        self.assertEqual(forecast.predicted_score, 76)

    def test_unknown_sleep_is_not_zero_sleep(self):
        # Clients send 0 minutes when the night never synced. That used to
        # read as an 8h debt (-20) and a "Take the rest day" on no evidence.
        unknown = rf.forecast(_base_forecast(sleep_minutes=0))
        known = rf.forecast(_base_forecast())
        self.assertEqual(unknown.predicted_score, known.predicted_score)
        self.assertNotEqual(unknown.posture, rf.REST)

    def test_unknown_readiness_starts_from_usual_with_low_confidence(self):
        forecast = rf.forecast(_base_forecast(current_readiness=0))
        self.assertEqual(forecast.predicted_score, rf.DEFAULT_READINESS_BASELINE)
        self.assertEqual(forecast.confidence, "low")
        self.assertNotEqual(forecast.posture, rf.REST)

    def test_new_user_with_nothing_is_not_told_to_rest(self):
        forecast = rf.forecast(rf.ForecastInput(current_readiness=0, sleep_minutes=0))
        self.assertEqual(forecast.posture, rf.STEADY)
        self.assertEqual(forecast.confidence, "low")

    def test_unreported_stress_is_unknown_not_moderate(self):
        said = rf.forecast(_base_forecast(stress_level=80))
        unsaid = rf.forecast(_base_forecast(stress_level=None))
        self.assertTrue(any(d.title == "High stress" for d in said.drivers))
        self.assertFalse(any("stress" in d.title.lower() for d in unsaid.drivers))
        self.assertEqual(unsaid.confidence, "low")  # 4 of 7 signals

    def test_full_signal_is_high_confidence(self):
        forecast = rf.forecast(_base_forecast(acwr=1.0, readiness_baseline=78))
        self.assertEqual(forecast.confidence, "high")

    def test_drivers_sorted_by_impact(self):
        forecast = rf.forecast(_base_forecast(
            current_readiness=50, today_strain=18, stress_level=80, acwr=1.7,
        ))
        impacts = [abs(d.impact) for d in forecast.drivers]
        self.assertEqual(impacts, sorted(impacts, reverse=True))

    def test_swift_parity_vectors(self):
        # Same vectors as ReadinessForecastTests.testParityVectors in Swift.
        cases = [
            (_base_forecast(), 75, rf.STEADY, "medium"),
            (_base_forecast(current_readiness=45, sleep_minutes=300, today_strain=5), 60, rf.PROTECT, "medium"),
            (_base_forecast(current_readiness=58, sleep_minutes=360, today_strain=18), 55, rf.PROTECT, "medium"),
            (_base_forecast(current_readiness=0, sleep_minutes=0), 75, rf.STEADY, "low"),
            (_base_forecast(current_readiness=90, today_strain=2, stress_level=20, acwr=0.7,
                            readiness_baseline=80), 97, rf.PUSH, "high"),
        ]
        for inp, score, posture, confidence in cases:
            fc = rf.forecast(inp)
            self.assertEqual((fc.predicted_score, fc.posture, fc.confidence), (score, posture, confidence), inp)

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


# ──────────────────────────────────────────────────────────────────────
# Slice 4 — coach path ariaTags match picture vocab (fail-closed)
# ──────────────────────────────────────────────────────────────────────

_ALLOWED_PICTURE_PREFIXES = ("forecast:", "working:", "tomorrow_budget:")
_HOBBY_PREFIXES = (
    "hobby_path:", "hobby_social:", "hobby_window:", "hobby_people:", "hobby:",
)


class CoachPictureVocabTests(unittest.TestCase):
    """_attach_predictions must emit pictureAriaTags matching the Home
    picture vocab: forecast: / working: / tomorrow_budget: only."""

    def _run_attach(self, **ctx_overrides):
        from services import coach_context

        base = {
            "readiness": {"overall": 72, "hrv": 60, "restingHR": 55, "stressLevel": 30},
            "recentSleep": [{"totalHours": 8, "score": 80, "date": "2026-10-04"}],
            "recentWorkouts": [],
        }
        base.update(ctx_overrides)
        return coach_context._attach_predictions(base)

    def test_picture_tags_present_and_non_empty(self):
        out = self._run_attach()
        tags = out.get("pictureAriaTags")
        self.assertIsInstance(tags, list)
        self.assertTrue(len(tags) >= 3, f"Expected >=3 picture tags, got {tags}")

    def test_picture_tags_only_allowed_prefixes(self):
        out = self._run_attach()
        for tag in out["pictureAriaTags"]:
            self.assertTrue(
                any(tag.startswith(p) for p in _ALLOWED_PICTURE_PREFIXES),
                f"Tag {tag!r} has disallowed prefix; only {_ALLOWED_PICTURE_PREFIXES} permitted",
            )

    def test_no_hobby_tags_in_picture(self):
        out = self._run_attach(
            lifestyleTags=["living:hobby:cooking", "living:social:2"],
            chronotype={"typicalWakeTime": "07:00"},
        )
        for tag in out["pictureAriaTags"]:
            self.assertFalse(
                any(tag.startswith(h) for h in _HOBBY_PREFIXES),
                f"Hobby tag {tag!r} must not appear in pictureAriaTags",
            )

    def test_forecast_tag_format(self):
        out = self._run_attach()
        forecast_tags = [t for t in out["pictureAriaTags"] if t.startswith("forecast:tomorrow:")]
        self.assertTrue(len(forecast_tags) >= 1, "Must have at least one forecast:tomorrow: tag")
        from aria_core import readiness_forecast as rf
        parsed = rf.parse_tag(forecast_tags[0])
        self.assertIsNotNone(parsed, f"forecast tag {forecast_tags[0]!r} must be parseable")

    def test_working_tag_uses_picture_stance_vocab(self):
        out = self._run_attach()
        from aria_core import user_working_model as uwm
        working_tags = [t for t in out["pictureAriaTags"] if t.startswith("working:") and not t.startswith("working:feel:") and not t.startswith("working:confidence:")]
        self.assertTrue(len(working_tags) >= 1, "Must have at least one working:{tendency}:{stance} tag")
        for tag in working_tags:
            parsed = uwm.parse_tag(tag)
            self.assertIsNotNone(parsed, f"working tag {tag!r} must be parseable by uwm.parse_tag")
            _, stance = parsed
            self.assertIn(
                stance,
                (uwm.CAP_HEROICS, uwm.HOLD_THE_LINE, uwm.REBUILD_TRUST, uwm.KEEP_RHYTHM),
                f"Stance {stance!r} is not in picture vocab",
            )

    def test_budget_tag_matches_context(self):
        out = self._run_attach()
        budget_tags = [t for t in out["pictureAriaTags"] if t.startswith("tomorrow_budget:")]
        self.assertEqual(len(budget_tags), 1, f"Expected exactly 1 budget tag, got {budget_tags}")
        expected = f"tomorrow_budget:{out['tomorrowBudgets']['constraint']}"
        self.assertEqual(budget_tags[0], expected)

    def test_overreacher_gets_cap_heroics_in_tags(self):
        out = self._run_attach(
            readiness={"overall": 52, "hrv": 40, "restingHR": 72, "stressLevel": 70},
            recentSleep=[
                {"totalHours": 5.5, "score": 58, "date": "2026-10-04"},
                {"totalHours": 6, "score": 62, "date": "2026-10-03"},
            ],
            recentWorkouts=[
                {"date": "2026-10-04", "intensity": "high", "duration": 60},
                {"date": "2026-10-03", "intensity": "high", "duration": 55},
                {"date": "2026-10-02", "intensity": "high", "duration": 50},
            ],
            recoveryTrend={"delta": -5},
        )
        working_tags = [t for t in out["pictureAriaTags"] if t.startswith("working:") and not t.startswith("working:feel:") and not t.startswith("working:confidence:")]
        self.assertTrue(
            any("cap_heroics" in t for t in working_tags),
            f"Overreacher scenario must produce cap_heroics tag, got {working_tags}",
        )

    def test_prompt_block_includes_picture_tags(self):
        from services import coach_context

        out = self._run_attach()
        block = coach_context.context_to_prompt_block(out)
        self.assertIn("pictureAriaTags", block)
        self.assertIn("forecast:tomorrow:", block)
        self.assertIn("working:", block)
        self.assertIn("tomorrow_budget:", block)

    def test_prompt_block_no_hobby_tags(self):
        from services import coach_context

        out = self._run_attach(
            lifestyleTags=["living:hobby:cooking", "living:social:2"],
            chronotype={"typicalWakeTime": "07:00"},
        )
        block = coach_context.context_to_prompt_block(out)
        for prefix in _HOBBY_PREFIXES:
            self.assertNotIn(prefix, block, f"Hobby prefix {prefix!r} must not appear in prompt block pictureAriaTags")


class NormalizeStanceTests(unittest.TestCase):
    """user_working_model.normalize_stance maps legacy stances to picture vocab."""

    def test_legacy_protect_maps_to_cap_heroics(self):
        from aria_core import user_working_model as uwm
        self.assertEqual(uwm.normalize_stance("protect"), uwm.CAP_HEROICS)

    def test_legacy_proceed_maps_to_keep_rhythm(self):
        from aria_core import user_working_model as uwm
        self.assertEqual(uwm.normalize_stance("proceed"), uwm.KEEP_RHYTHM)

    def test_legacy_fuel_maps_to_keep_rhythm(self):
        from aria_core import user_working_model as uwm
        self.assertEqual(uwm.normalize_stance("fuel"), uwm.KEEP_RHYTHM)

    def test_legacy_clarify_maps_to_hold_the_line(self):
        from aria_core import user_working_model as uwm
        self.assertEqual(uwm.normalize_stance("clarify"), uwm.HOLD_THE_LINE)

    def test_picture_vocab_passes_through(self):
        from aria_core import user_working_model as uwm
        for stance in (uwm.CAP_HEROICS, uwm.HOLD_THE_LINE, uwm.REBUILD_TRUST, uwm.KEEP_RHYTHM):
            self.assertEqual(uwm.normalize_stance(stance), stance)

    def test_unknown_defaults_to_keep_rhythm(self):
        from aria_core import user_working_model as uwm
        self.assertEqual(uwm.normalize_stance("banana"), uwm.KEEP_RHYTHM)


# ──────────────────────────────────────────────────────────────────────
# Spoken leak deny pin — Dummy / generate_response only (no Bedrock)
# ──────────────────────────────────────────────────────────────────────

def _forecast_ctx(posture: str, score: int = 52) -> ARIAContext:
    return ARIAContext(
        readiness=ReadinessContext(
            recovery_score=float(score),
            hrv_7day_trend=-2.0,
            tomorrow_predicted_score=score,
            tomorrow_posture=posture,
            tomorrow_confidence="medium",
        )
    )


def _spoken_fields(resp: dict) -> str:
    return f"{resp.get('prose_summary', '')} {resp.get('message', '')}"


class SpokenEngineTokenDenyPinTests(unittest.TestCase):
    """Fail-closed Dummy pin: stance tokens, picture tags, and (protect)
    labels must never appear in spoken message / prose_summary.

    The bare verb "protect" is legitimate Iris speech and must pass.
    """

    def test_deny_pin_fails_on_stance_tokens(self):
        from aria_core.speak_guard import spoken_engine_token_hits

        for token in (
            "cap_heroics",
            "keep_rhythm",
            "hold_the_line",
            "rebuild_trust",
        ):
            hits = spoken_engine_token_hits(f"Tomorrow looks like {token} day")
            self.assertIn(token, hits, token)

    def test_deny_pin_fails_on_picture_and_engine_tags(self):
        from aria_core.speak_guard import spoken_engine_token_hits

        self.assertIn(
            "pictureAriaTags",
            spoken_engine_token_hits("see pictureAriaTags on the card"),
        )
        self.assertIn(
            "forecast:tomorrow:",
            spoken_engine_token_hits("forecast:tomorrow:52:protect"),
        )
        self.assertIn(
            "tomorrow_budget:",
            spoken_engine_token_hits("tomorrow_budget:people"),
        )
        self.assertIn(
            "working:",
            spoken_engine_token_hits("working:overreacher:cap_heroics"),
        )
        self.assertIn(
            "working:",
            spoken_engine_token_hits("working:feel:mixed"),
        )

    def test_deny_pin_fails_on_posture_label_not_bare_verb(self):
        from aria_core.speak_guard import spoken_engine_token_hits

        for posture in ("protect", "rest", "push", "steady"):
            hits = spoken_engine_token_hits(
                f"Tomorrow's readiness is forecast at 52 ({posture})"
            )
            self.assertIn(f"({posture})", hits, posture)

        self.assertEqual(
            spoken_engine_token_hits("Sleep first tonight — protect wind-down."),
            (),
        )
        self.assertEqual(
            spoken_engine_token_hits("protect your 23:00 wind-down tonight"),
            (),
        )

    def test_interpret_readiness_drops_raw_posture_paren(self):
        from aria_core import aria_engine
        from aria_core.speak_guard import spoken_engine_token_hits

        signal = aria_engine._interpret_readiness(_forecast_ctx("protect"))
        self.assertIsNotNone(signal)
        self.assertEqual(spoken_engine_token_hits(signal.interpretation), ())
        self.assertNotIn("(protect)", signal.interpretation.lower())
        self.assertIn("cap intensity", signal.interpretation.lower())

    def test_dummy_recommendation_spoken_stays_off_engine_tokens(self):
        from aria_core import aria_engine
        from aria_core.speak_guard import spoken_engine_token_hits

        for posture in ("protect", "rest", "push", "steady"):
            resp = aria_engine.generate_response(
                "what should I do today?",
                _forecast_ctx(posture),
                seed=0,
            )
            spoken = _spoken_fields(resp)
            hits = spoken_engine_token_hits(spoken)
            self.assertEqual(hits, (), f"posture={posture} spoken={spoken!r}")
            self.assertNotIn(f"({posture})", spoken.lower())

    def test_dummy_tagged_context_does_not_speak_picture_or_stance(self):
        from aria_core import aria_engine
        from aria_core.speak_guard import spoken_engine_token_hits

        ctx = ARIAContext(
            readiness=ReadinessContext(
                recovery_score=52,
                tomorrow_predicted_score=52,
                tomorrow_posture="protect",
            ),
            lifestyle=LifestyleContext(
                recent_patterns=[
                    "working:overreacher:cap_heroics",
                    "forecast:tomorrow:52:protect",
                    "tomorrow_budget:people",
                    "hobby_path:restore_quiet",
                ]
            ),
        )
        resp = aria_engine.generate_response("what should I do today?", ctx, seed=0)
        spoken = _spoken_fields(resp)
        self.assertEqual(spoken_engine_token_hits(spoken), (), spoken)
        self.assertNotIn("hobby_path:", spoken)
        self.assertIn("cap heroics", spoken.lower())



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
