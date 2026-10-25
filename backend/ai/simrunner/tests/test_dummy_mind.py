"""Dummy mind: WHOOP-forum failures, cold start, determinism, offline, style, leakage."""

from __future__ import annotations

import io
import json
import logging
import os
import sys
import tempfile
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import dummy_mind as mind  # noqa: E402
from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner import dummy_privacy as privacy  # noqa: E402
from backend.ai.simrunner.aria_simrunner import speak_quality  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import DailyRecord  # noqa: E402
from backend.ai.simrunner.backend_simulator.data_generator import ARIAContext  # noqa: E402

CANARY_NAME = "ZeldaQx91Canary"
CANARY_HRV = 777
CANARY_SLEEP = 13.37


def _daily(**overrides) -> DailyRecord:
    base = dict(
        date="2026-01-15",
        total_sleep_hours=7.4,
        deep_sleep_minutes=80,
        rem_sleep_minutes=95,
        sleep_score=80,
        hrv=55,
        resting_hr=55,
        readiness_score=70,
        steps=9000,
        active_calories=500,
        workout_logged=False,
        workout_type=None,
        workout_duration_minutes=None,
        workout_intensity=None,
        training_load=0.0,
        acwr=1.0,
        notes=None,
    )
    base.update(overrides)
    return DailyRecord(**base)


def _ctx(**overrides) -> ARIAContext:
    today = overrides.pop("today", _daily())
    history = overrides.pop("history", [today, today, today, today])
    fields = dict(
        user_name="Test",
        chronotype="bear",
        experience_level="intermediate",
        coaching_style="balanced",
        occupation="teacher",
        life_season="maintenance",
        today=today,
        hrv_7d_avg=55.0,
        hrv_7d_trend="stable",
        sleep_debt_7d_hours=0.0,
        readiness_7d_avg=70.0,
        readiness_trend="stable",
        acwr=1.0,
        training_streak=0,
        days_since_last_workout=1,
        target_sleep_hours=8.0,
        target_wake_hour=7.0,
        is_overtrained=False,
        is_sleep_deprived=False,
        has_notable_event=False,
        notable_event_note=None,
        history=history,
        sleep_nights_available_7d=len(history),
    )
    fields.update(overrides)
    return ARIAContext(**fields)


class DummyMindContractTests(unittest.TestCase):
    def setUp(self):
        self._env = os.environ.get("ENVIRONMENT")
        os.environ.pop("ENVIRONMENT", None)

    def tearDown(self):
        if self._env is None:
            os.environ.pop("ENVIRONMENT", None)
        else:
            os.environ["ENVIRONMENT"] = self._env

    def _row(self, message, **kwargs):
        kwargs.setdefault("seed", 11)
        kwargs.setdefault("engine", "stub")
        return dummy.respond(message, **kwargs)

    def test_does_not_invent_health_numbers(self):
        ctx = _ctx(today=_daily(hrv=None, total_sleep_hours=None), history=[])
        ctx.sleep_nights_available_7d = 0
        for engine in ("stub", "lambda"):
            row = self._row("What's my HRV and how many hours did I sleep?", context=ctx, engine=engine)
            blob = speak_quality.user_visible_blob(row)
            self.assertNotRegex(blob, r"\b(4[0-9]|5[0-9]|6[0-9])\s*ms\b")
            self.assertNotIn("52", blob)
            self.assertNotRegex(blob, r"\b7\.[0-9]\s*hours\b")
            self.assertEqual(speak_quality.vitals_hits(blob), [])
            self.assertTrue(row["judgment"]["cold_start"] or row["judgment"]["stance"] == "clarify")

    def test_correction_sticks_on_the_next_turn(self):
        ctx = _ctx(today=_daily(total_sleep_hours=5.1))
        prior = [
            "How did I sleep last night?",
            "That's not right — I slept a full night, I slept well.",
        ]
        row = self._row("What should I train today?", context=ctx, prior_turns=prior)
        blob = speak_quality.user_visible_blob(row).lower()
        mem = row["dummy_memory"]
        self.assertEqual(mem["corrections"].get("sleep"), "rebuilt")
        self.assertNotRegex(blob, r"didn'?t give you a full reset")
        self.assertNotIn("came up short", blob)
        self.assertTrue(
            "full" in blob or "paid you back" in blob or "morning" in blob or "honest" in blob,
            blob,
        )

    def test_preference_is_honored(self):
        ctx = _ctx()
        prior = ["I prefer morning workouts, never evenings."]
        row = self._row("What should I train today?", context=ctx, prior_turns=prior)
        blob = speak_quality.user_visible_blob(row).lower()
        self.assertEqual(row["dummy_memory"]["preferences"].get("workout_time"), "morning")
        self.assertIn("morning", blob)
        self.assertNotIn("this evening", blob)
        self.assertNotIn("tonight", blob)

    def test_logged_illness_blocks_training_push(self):
        ctx = _ctx()
        prior = ["I'm sick, log that I'm ill today."]
        for engine in ("stub", "lambda"):
            row = self._row("What should I train today?", context=ctx, prior_turns=prior, engine=engine)
            blob = speak_quality.user_visible_blob(row).lower()
            self.assertTrue(row["judgment"]["blocks_training"], row["judgment"])
            self.assertEqual(row["judgment"]["stance"], "protect")
            self.assertIn("rest and fluids", blob)
            self.assertIsNone(row.get("session"))
            self.assertIsNone(speak_quality.bark_hits(blob) or None)
            for banned in ("go train", "real work", "hero set", "moderate-to-hard"):
                self.assertNotIn(banned, blob, banned)

    def test_cold_start_asks_instead_of_guessing(self):
        night = _daily()
        ctx = _ctx(today=night, history=[night], sleep_nights_available_7d=1)
        row = self._row("What should I train today?", context=ctx)
        self.assertTrue(row["judgment"]["cold_start"])
        self.assertEqual(row["judgment"]["stance"], "clarify")
        self.assertLess(row["orchestration"]["dummy_nights"], mind.MIN_NIGHTS)
        blob = speak_quality.user_visible_blob(row).lower()
        self.assertTrue(
            "few" in blob or "yet" in blob or "guess" in blob or "nights" in blob,
            blob,
        )
        self.assertNotIn("go train", blob)

    def test_same_inputs_are_deterministic(self):
        ctx = _ctx()
        prior = ["I prefer morning workouts.", "I feel great, let's go!"]
        a = self._row("What should I train today?", context=ctx, prior_turns=prior, seed=21)
        b = self._row("What should I train today?", context=ctx, prior_turns=prior, seed=21)
        self.assertEqual(a["prose_summary"], b["prose_summary"])
        self.assertEqual(a["message"], b["message"])
        self.assertEqual(a["judgment"], b["judgment"])
        self.assertEqual(a["dummy_memory"]["style"], b["dummy_memory"]["style"])

    def test_recommendation_includes_why_from_data(self):
        row = self._row("What should I train today?", context=_ctx())
        blob = speak_quality.user_visible_blob(row).lower()
        self.assertTrue(row["judgment"]["why"])
        self.assertTrue(
            any(cue in blob for cue in ("because", "that's from", "since", "the night", "last night")),
            blob,
        )

    def test_adaptive_style_shifts_tone_not_advice(self):
        ctx = _ctx()
        opt = self._row(
            "What should I train today?",
            context=ctx,
            seed=8,
            prior_turns=["I feel great, let's go! I'm pumped."],
        )
        cau = self._row(
            "What should I train today?",
            context=ctx,
            seed=8,
            prior_turns=["I'm worried I might overdo it. Play it safe."],
        )
        self.assertEqual(opt["dummy_memory"]["style"]["band"], "optimistic")
        self.assertEqual(cau["dummy_memory"]["style"]["band"], "cautious")
        self.assertEqual(opt["judgment"]["stance"], cau["judgment"]["stance"])
        self.assertNotEqual(opt["prose_summary"], cau["prose_summary"])
        opt_blob = opt["prose_summary"].lower()
        cau_blob = cau["prose_summary"].lower()
        self.assertTrue(
            any(w in opt_blob for w in ("energy", "sparkle", "parade", "victory")),
            opt["prose_summary"],
        )
        self.assertTrue(
            any(w in cau_blob for w in ("steady", "measured", "kind", "heroics")),
            cau["prose_summary"],
        )

    def test_optimistic_illness_still_blocks_training(self):
        ctx = _ctx()
        row = self._row(
            "I feel great, let's go — what should I train today?",
            context=ctx,
            prior_turns=["I'm sick, log that I'm ill today."],
        )
        self.assertTrue(row["judgment"]["blocks_training"])
        self.assertEqual(row["judgment"]["stance"], "protect")
        blob = speak_quality.user_visible_blob(row).lower()
        self.assertIn("rest", blob)
        self.assertNotIn("go train", blob)
        self.assertEqual(row["dummy_memory"]["style"]["band"], "optimistic")

    def test_dummy_mind_and_privacy_never_import_cloud_clients(self):
        for mod in (mind, privacy, dummy):
            src = Path(mod.__file__).read_text()
            imports = [
                line.strip()
                for line in src.splitlines()
                if line.strip().startswith(("import ", "from "))
            ]
            for needle in ("boto3", "botocore", "bedrock_client", "urllib", "requests", "http.client", "httpx"):
                for stmt in imports:
                    self.assertNotIn(needle, stmt, f"{mod.__name__} imported {needle}")


class DummyOfflineEnforcementTests(unittest.TestCase):
    def setUp(self):
        os.environ.pop("ENVIRONMENT", None)
        os.environ.pop("FORGE_DUMMY_WEB", None)
        os.environ.pop("FORGE_SCOUT_MODE", None)
        os.environ.pop("APP_DATA_TABLE_NAME", None)

    def test_respond_raises_if_socket_or_boto3_is_constructed(self):
        def boom(*_a, **_k):
            raise AssertionError("Dummy must not open a network socket or AWS client")

        class _Boto:
            def client(self, *a, **k):
                boom()

            def resource(self, *a, **k):
                boom()

            class session:
                class Session:
                    def client(self, *a, **k):
                        boom()

                    def resource(self, *a, **k):
                        boom()

        patches = [
            patch("socket.socket", side_effect=boom),
            patch("socket.create_connection", side_effect=boom),
            patch("socket.getaddrinfo", side_effect=boom),
        ]
        boto = sys.modules.get("boto3")
        if boto is not None:
            patches.append(patch.object(boto, "client", side_effect=boom))
            patches.append(patch.object(boto, "resource", side_effect=boom))
        else:
            patches.append(patch.dict(sys.modules, {"boto3": _Boto()}))
        stacked = patches[0]
        for extra in patches[1:]:
            stacked = stacked
        with patch("socket.socket", side_effect=boom), patch(
            "socket.create_connection", side_effect=boom
        ), patch("socket.getaddrinfo", side_effect=boom):
            if boto is not None:
                with patch.object(boto, "client", side_effect=boom), patch.object(
                    boto, "resource", side_effect=boom
                ):
                    row = dummy.respond("What should I train today?", seed=3, engine="stub")
            else:
                with patch.dict(sys.modules, {"boto3": _Boto()}):
                    row = dummy.respond("What should I train today?", seed=3, engine="stub")
        self.assertTrue(row["test_ready"])
        self.assertIn("judgment", row)

    def test_research_worthy_turn_stays_offline(self):
        def boom(*_a, **_k):
            raise AssertionError("Dummy look_up must not open a socket")

        with patch("socket.socket", side_effect=boom), patch(
            "socket.create_connection", side_effect=boom
        ):
            row = dummy.respond("how do I improve my workout routine?", seed=1, engine="stub")
        self.assertTrue(row["prose_summary"])
        self.assertTrue(row.get("judgment"))


class DummyZeroLeakageTests(unittest.TestCase):
    def setUp(self):
        os.environ.pop("ENVIRONMENT", None)

    def test_canary_name_and_health_never_leave_dummy(self):
        today = _daily(hrv=CANARY_HRV, total_sleep_hours=CANARY_SLEEP)
        ctx = _ctx(user_name=CANARY_NAME, today=today, history=[today, today, today, today])
        message = f"Hi I'm {CANARY_NAME}, my HRV is {CANARY_HRV}. What should I train?"
        captured: list[str] = []

        class _Handler(logging.Handler):
            def emit(self, record):
                captured.append(self.format(record))

        handler = _Handler()
        logging.getLogger().addHandler(handler)
        analytics: list[tuple] = []

        def capture_analytics(event, payload=None):
            analytics.append((event, payload))

        try:
            with patch.object(privacy, "emit_analytics", side_effect=capture_analytics):
                row = dummy.respond(message, seed=4, context=ctx, engine="stub")
                from backend.ai.aria_chat.session import run_turn

                with tempfile.TemporaryDirectory() as tmp:
                    out = run_turn(
                        message,
                        payload={
                            "user_name": CANARY_NAME,
                            "context": {
                                "profile": {"name": CANARY_NAME},
                                "sleep": {"hrv": CANARY_HRV, "durationMinutes": 802},
                            },
                        },
                        persist_log=True,
                        log_dir=tmp,
                        install_pseudonym="pseudo-canary",
                    )
                    files = list(Path(tmp).glob("*.jsonl"))
                    logged = ""
                    for path in files:
                        logged += path.read_text(encoding="utf-8")
        finally:
            logging.getLogger().removeHandler(handler)

        surfaces = [
            "\n".join(captured),
            json.dumps(analytics),
            json.dumps(row.get("dummy_memory")),
            json.dumps(row.get("thinking")),
            logged,
            json.dumps({k: out.get(k) for k in ("dummy_memory", "thinking") if k in out}),
        ]
        for surface in surfaces:
            for canary in (CANARY_NAME, str(CANARY_HRV), str(CANARY_SLEEP)):
                self.assertNotIn(canary, surface, surface[:400])
        # Spoken reply also must not dump the canary health value or name.
        blob = speak_quality.user_visible_blob(row)
        self.assertNotIn(CANARY_NAME, blob)
        self.assertNotIn(str(CANARY_HRV), blob)
        self.assertNotIn(str(CANARY_SLEEP), blob)

    def test_health_needles_do_not_rewrite_turn_id(self):
        """Profile values like 44/70 must not rewrite uuid hex inside turn_id."""
        from backend.ai.aria_chat import logging as chatlog

        turn_id = "sample-sess-0008-aa44bb70"
        session_id = "sample-sess"
        needles = [CANARY_NAME, str(CANARY_HRV), str(CANARY_SLEEP), "44", "70"]
        record = chatlog.build_record(
            session_id=session_id,
            turn_id=turn_id,
            turn=8,
            seed=4,
            install_pseudonym="pseudo-canary",
            memory_enabled=True,
            user_message=f"Hi I'm {CANARY_NAME}, my HRV is {CANARY_HRV}.",
            envelope={"message": "ok", "prose_summary": "ok", "guidance_band": "coach"},
            payload={
                "user_name": CANARY_NAME,
                "context": {"sleep": {"hrv": CANARY_HRV, "remMinutes": 70}},
            },
            needles=needles,
        )
        self.assertEqual(record["turn_id"], turn_id)
        self.assertEqual(record["session_id"], session_id)
        blob = json.dumps(record)
        self.assertNotIn(CANARY_NAME, blob)
        self.assertNotIn(str(CANARY_HRV), blob)


if __name__ == "__main__":
    unittest.main()
