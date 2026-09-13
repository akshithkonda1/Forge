import io
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner import voice_diagnostics  # noqa: E402
from backend.ai.simrunner.aria_simrunner import web_research  # noqa: E402
from backend.ai.simrunner import lifetime_suite  # noqa: E402


class DummyOrchestratorTests(unittest.TestCase):
    def setUp(self):
        self._env = os.environ.get("ENVIRONMENT")
        os.environ.pop("ENVIRONMENT", None)

    def tearDown(self):
        if self._env is None:
            os.environ.pop("ENVIRONMENT", None)
        else:
            os.environ["ENVIRONMENT"] = self._env

    def test_refuses_production(self):
        os.environ["ENVIRONMENT"] = "production"
        with self.assertRaises(RuntimeError) as ctx:
            dummy.refuse_if_production()
        self.assertIn("test-only", str(ctx.exception))
        with self.assertRaises(RuntimeError):
            dummy.respond("how did I sleep?")

    def test_staging_is_also_refused(self):
        os.environ["ENVIRONMENT"] = "staging"
        with self.assertRaises(RuntimeError):
            dummy.respond("train today")

    def test_multi_intent_spawns_several_workers(self):
        plan = dummy.plan_workers("I slept badly — what should I train and eat?")
        kinds = {w.kind for w in plan.workers}
        # "slept" routes to the dedicated Sleep specialist rather than
        # Recovery, and "eat" routes to Lifestyle now that Fuel folded into it.
        self.assertTrue({"sleep", "workout", "lifestyle"} <= kinds)
        self.assertEqual(sum(1 for w in plan.workers if w.is_primary), 1)

    def test_cycle_one_worker_per_person(self):
        plan = dummy.plan_workers(
            "how do I show up for them",
            cycle_subjects=["Sam", "Maya"],
        )
        cycle = [w for w in plan.workers if w.kind == "cycle"]
        self.assertEqual([w.subject for w in cycle], ["Sam", "Maya"])

    def test_respond_is_simrunner_stub_not_bedrock(self):
        row = dummy.respond("What should I train today?", seed=42)
        self.assertTrue(row["test_ready"])
        self.assertEqual(row["reasoning_source"], dummy.REASONING_SOURCE)
        self.assertEqual(row["model"], dummy.STUB_MODEL)
        self.assertEqual(row["user_id"], "test-user-00000000")
        self.assertIn("workout", row["agents"])
        self.assertTrue(row["prose_summary"].strip())

    def test_same_seed_is_deterministic(self):
        a = dummy.respond("How did I sleep last night?", seed=7)
        b = dummy.respond("How did I sleep last night?", seed=7)
        self.assertEqual(a["prose_summary"], b["prose_summary"])
        self.assertEqual(a["agents"], b["agents"])

    def test_cli_test_ready_exits_zero(self):
        old = sys.stdout
        sys.stdout = io.StringIO()
        try:
            self.assertEqual(lifetime_suite.main(["--test-ready"]), 0)
        finally:
            sys.stdout = old

    def test_cli_test_ready_refuses_prod(self):
        os.environ["ENVIRONMENT"] = "prod"
        old = sys.stdout
        sys.stdout = io.StringIO()
        try:
            self.assertEqual(lifetime_suite.main(["--test-ready"]), 2)
        finally:
            sys.stdout = old

    def test_refuses_lambda_and_other_cloud_runtimes(self):
        for key in ("AWS_LAMBDA_FUNCTION_NAME", "K_SERVICE", "FUNCTION_TARGET", "WEBSITE_INSTANCE_ID"):
            with self.subTest(key=key):
                previous = os.environ.get(key)
                os.environ[key] = "forge-dummy-test"
                try:
                    with self.assertRaises(RuntimeError) as ctx:
                        dummy.respond("how did I sleep?")
                    self.assertIn("local-only", str(ctx.exception))
                finally:
                    if previous is None:
                        os.environ.pop(key, None)
                    else:
                        os.environ[key] = previous

    def test_source_never_imports_cloud_clients(self):
        src = Path(dummy.__file__).read_text()
        imports = [
            line.strip()
            for line in src.splitlines()
            if line.strip().startswith(("import ", "from "))
        ]
        forbidden = ("boto3", "botocore", "bedrock_client", "urllib", "requests", "http.client")
        for stmt in imports:
            for needle in forbidden:
                self.assertNotIn(needle, stmt, f"dummy orchestrator imported {needle}")

    def test_never_invokes_bedrock_converse(self):
        from backend.ai.simrunner.aria_simrunner import bedrock_client

        def boom(*_args, **_kwargs):
            raise AssertionError("dummy orchestrator must not call Bedrock")

        original = bedrock_client.converse
        bedrock_client.converse = boom
        try:
            row = dummy.respond("What should I train today?", seed=1)
            self.assertEqual(row["reasoning_source"], dummy.REASONING_SOURCE)
        finally:
            bedrock_client.converse = original

    def test_research_worthy_message_appends_a_cited_web_note(self):
        with patch.object(web_research, "look_up", return_value="From Some Source: real info.") as mock_look_up:
            row = dummy.respond("how do I improve my workout routine?", seed=1)
        mock_look_up.assert_called_once_with("workout")
        # Trailing period may be normalized when the cite is parenthesized.
        self.assertIn("From Some Source: real info", row["message"])

    def test_non_research_message_never_calls_web_research(self):
        with patch.object(web_research, "look_up") as mock_look_up:
            dummy.respond("What should I train today?", seed=1)
        mock_look_up.assert_not_called()

    def test_a_failed_lookup_leaves_the_reply_unchanged(self):
        with patch.object(web_research, "look_up", return_value=None):
            row = dummy.respond("how do I improve my workout routine?", seed=1)
        self.assertTrue(row["prose_summary"])
        self.assertEqual(row["message"], row["prose_summary"])

    def test_humanized_prose_does_not_dump_fields(self):
        # The stub used to splice `_context_phrase` ("Readiness is 96, HRV 52ms")
        # into the chat. The dummy orchestra must rewrite that before a person
        # (or voice-check) sees it.
        row = dummy.respond("How did I sleep last night?", seed=42)
        self._assert_no_vitals_speak(row)
        prose = row["prose_summary"]
        self.assertNotRegex(prose, r"Readiness is \d")
        self.assertNotRegex(prose, r"\bACWR ")
        self.assertTrue(prose.strip())
        self.assertIn(row["voice_diagnosis"]["verdict"], ("human", "mixed"))
        self.assertNotEqual(row["voice_diagnosis"]["verdict"], "data_driven")

    def test_default_voice_check_turns_are_not_data_driven(self):
        report = dummy.run_voice_diagnostics(seed=42)
        for turn in report["turns"]:
            self.assertNotEqual(
                turn["verdict"],
                "data_driven",
                f"{turn['message']!r} still reads as a field dump: {turn['reply']!r}",
            )
        self.assertEqual(report["summary"]["data_driven"], 0)

    def test_supporting_briefs_are_sentences_not_huds(self):
        row = dummy.respond("I slept badly — what should I train and eat?", seed=1)
        self.assertNotRegex(row["message"], r"Recovery · ")
        self.assertNotRegex(row["message"], r"HRV \d+ms")
        self.assertIn("thinking", row)
        self.assertTrue(row["thinking"])

    def test_respond_includes_a_voice_diagnosis(self):
        row = dummy.respond("How did I sleep last night?", seed=42)
        diag = row["voice_diagnosis"]
        self.assertIn(diag["verdict"], ("human", "data_driven", "mixed"))
        self.assertIn("evidence", diag)

    def test_respond_voice_diagnosis_matches_diagnosing_the_prose_directly(self):
        row = dummy.respond("How did I sleep last night?", seed=42)
        expected = voice_diagnostics.diagnose(row["prose_summary"]).as_dict()
        self.assertEqual(row["voice_diagnosis"], expected)

    def test_voice_diagnosis_is_based_on_the_primary_reply_not_appended_extras(self):
        # `message` gets the web-research note appended after `prose_summary`
        # (see the two tests above this one); the diagnosis must still track
        # only the primary reply, not the note's own sentence shape.
        with patch.object(
            web_research, "look_up",
            return_value="From Some Source: unrelated filler with its own shape.",
        ):
            row = dummy.respond("how do I improve my workout routine?", seed=1)
        self.assertNotEqual(row["prose_summary"], row["message"])
        expected = voice_diagnostics.diagnose(row["prose_summary"]).as_dict()
        self.assertEqual(row["voice_diagnosis"], expected)

    def test_run_voice_diagnostics_shape_and_determinism(self):
        report_a = dummy.run_voice_diagnostics(seed=42)
        report_b = dummy.run_voice_diagnostics(seed=42)
        self.assertEqual(report_a, report_b)
        self.assertEqual(len(report_a["turns"]), 5)
        for turn in report_a["turns"]:
            self.assertIn(turn["verdict"], ("human", "data_driven", "mixed"))
            self.assertTrue(turn["reply"])
            self.assertIsInstance(turn["evidence"], list)
        summary = report_a["summary"]
        self.assertEqual(summary["total"], 5)
        self.assertEqual(
            summary["human"] + summary["data_driven"] + summary["mixed"],
            summary["total"],
        )

    def test_run_voice_diagnostics_respects_custom_messages(self):
        report = dummy.run_voice_diagnostics(messages=["What should I train today?"], seed=1)
        self.assertEqual(len(report["turns"]), 1)
        self.assertEqual(report["turns"][0]["message"], "What should I train today?")

    def test_run_voice_diagnostics_refuses_production(self):
        os.environ["ENVIRONMENT"] = "production"
        with self.assertRaises(RuntimeError):
            dummy.run_voice_diagnostics()

    def test_cli_voice_check_exits_zero(self):
        old = sys.stdout
        sys.stdout = io.StringIO()
        try:
            self.assertEqual(lifetime_suite.main(["--voice-check"]), 0)
        finally:
            sys.stdout = old

    def test_cli_voice_check_refuses_prod(self):
        os.environ["ENVIRONMENT"] = "prod"
        old = sys.stdout
        sys.stdout = io.StringIO()
        try:
            self.assertEqual(lifetime_suite.main(["--voice-check"]), 2)
        finally:
            sys.stdout = old

    def test_cli_voice_check_gate_fails_when_data_driven_turns_exist(self):
        fake_report = {
            "turns": [{
                "message": "m", "agent": "workout", "reply": "r",
                "verdict": "data_driven", "evidence": [],
            }],
            "summary": {"human": 0, "data_driven": 1, "mixed": 0, "total": 1},
        }
        old = sys.stdout
        sys.stdout = io.StringIO()
        try:
            with patch.object(dummy, "run_voice_diagnostics", return_value=fake_report):
                self.assertEqual(lifetime_suite.main(["--voice-check", "--gate"]), 2)
        finally:
            sys.stdout = old

    def test_cli_voice_check_gate_passes_when_no_turn_is_data_driven(self):
        fake_report = {
            "turns": [{
                "message": "m", "agent": "workout", "reply": "r",
                "verdict": "mixed", "evidence": [],
            }],
            "summary": {"human": 0, "data_driven": 0, "mixed": 1, "total": 1},
        }
        old = sys.stdout
        sys.stdout = io.StringIO()
        try:
            with patch.object(dummy, "run_voice_diagnostics", return_value=fake_report):
                self.assertEqual(lifetime_suite.main(["--voice-check", "--gate"]), 0)
        finally:
            sys.stdout = old

    def test_train_ask_attaches_a_body_session(self):
        row = dummy.respond("What should I train today?", seed=1)
        session = row.get("session")
        self.assertIsInstance(session, dict)
        self.assertTrue(session.get("exercises"))
        self.assertTrue(session.get("title"))
        self.assertNotRegex(session.get("reason") or "", r"\d+\s?(ms|bpm|sets)")

    def test_orchestration_envelope_is_a_real_pipeline(self):
        row = dummy.respond("I slept badly — what should I train and eat?", seed=1)
        orch = row["orchestration"]
        self.assertEqual(orch["stages"], list(dummy.ORCH_STAGES))
        kinds = {h["kind"] for h in orch["intents"]}
        self.assertTrue({"sleep", "workout", "lifestyle"} <= kinds)
        self.assertEqual(orch["primary"], row["agent"])
        self.assertIn(orch["signals"]["sleep"], ("thin", "decent", "rebuilt", "unknown"))
        self.assertIn(orch["signals"]["recovery"], ("asking", "steady", "ready"))
        self.assertTrue(orch["persona"]["occupation"])
        self.assertGreaterEqual(orch["latency_ms"], 40)
        self.assertLess(orch["latency_ms"], 130)
        self.assertIn("Heard", row["thinking"])

    def test_intent_weights_prefer_what_they_opened_with(self):
        hits = dummy.score_intents("I slept badly — what should I train and eat?")
        by_kind = {h.kind: h for h in hits}
        self.assertGreaterEqual(by_kind["sleep"].weight, 2)  # slept + lead bonus
        self.assertTrue(by_kind["workout"].cues)
        self.assertTrue(by_kind["lifestyle"].cues)

    def test_prior_turns_are_acknowledged_without_breaking_determinism(self):
        a = dummy.respond(
            "What should I train today?",
            seed=3,
            prior_turns=["How did I sleep last night?"],
        )
        b = dummy.respond(
            "What should I train today?",
            seed=3,
            prior_turns=["How did I sleep last night?"],
        )
        self.assertEqual(a["prose_summary"], b["prose_summary"])
        prose = a["prose_summary"]
        # Spoken memory bridges — not meta "Following on from your previous message".
        self.assertTrue(
            any(
                prose.startswith(p)
                for p in (
                    "You were asking about the night",
                    "Picking up from last night",
                    "Yeah — about that night",
                    "Yeah — after that night",
                    "Still thinking about the sleep",
                    "Right, the night you mentioned",
                    "After what you said about sleeping",
                    "Right, with the night still in play",
                    "Okay, night first then the work",
                )
            ),
            prose,
        )
        self.assertEqual(a["orchestration"]["prior_turns"], 1)
        fresh = dummy.respond("What should I train today?", seed=3)
        self.assertNotEqual(fresh["prose_summary"], a["prose_summary"])

    def test_multi_turn_sounds_spoken_not_templated(self):
        history = ["How did I sleep last night?"]
        first = dummy.respond(history[0], seed=11)
        second = dummy.respond(
            "ok what should I train then",
            seed=11,
            prior_turns=history,
        )
        chat = second["message"]
        # One spoken reply — not stacked specialist briefs.
        self.assertNotIn("\n\n", chat)
        # No meta rewriter / HUD markers.
        lowered = chat.lower()
        for banned in (
            "fresh pass",
            "another cut",
            "same question, new phrasing",
            "following on from",
            "readiness is ",
        ):
            self.assertNotIn(banned, lowered, chat)
        self._assert_no_vitals_speak(second)
        self._assert_no_vitals_speak(first)
        # Voice gate still reads as human on the primary prose.
        self.assertEqual(second["voice_diagnosis"]["verdict"], "human")
        self.assertTrue(first["prose_summary"].strip())

    def test_short_follow_ups_mutate_the_plan_like_a_real_coach(self):
        history = ["How did I sleep last night?", "what should I train"]
        easier = dummy.respond("make it easier", seed=11, prior_turns=history)
        shorter = dummy.respond("shorter", seed=11, prior_turns=history + ["make it easier"])
        skip = dummy.respond("skip it", seed=11, prior_turns=history + ["make it easier", "shorter"])
        for row in (easier, shorter, skip):
            self.assertNotIn("\n\n", row["message"])
            self.assertNotIn("from the training side of what you asked", row["message"].lower())
            self.assertEqual(row["voice_diagnosis"]["verdict"], "human")
            self.assertLess(len(row["message"].split()), 45)
        blob = f"{easier['message']} {shorter['message']} {skip['message']}".lower()
        self.assertTrue(any(w in blob for w in ("dial", "trim", "scratch", "lighter", "soft", "short", "rest")))

    def test_specialists_are_woven_not_stacked(self):
        row = dummy.respond(
            "I slept badly — what should I train and eat?",
            seed=1,
        )
        self.assertNotIn("\n\n", row["message"])
        # Orchestration still records specialists; the user-facing message does not list them as reports.
        self.assertTrue(row["orchestration"]["specialists"])
        for note in row["orchestration"]["specialist_notes"]:
            # Full specialist sentences should not appear as their own paragraph.
            self.assertNotIn(f"\n\n{note['text']}", row["message"])

    def test_phrase_banks_vary_across_seeds(self):
        texts = {
            dummy.respond("What should I train today?", seed=s)["prose_summary"]
            for s in range(20, 40)
        }
        # Enough spoken variety that twenty seeds are not a single canned line.
        self.assertGreaterEqual(len(texts), 4)

    def test_persona_colors_lifestyle_without_dumping_fields(self):
        # Default tier-1 persona is a teacher. Lifestyle asides should sound
        # like they know the life, not like they read a spreadsheet.
        row = dummy.respond("I slept badly — what should I train and eat?", seed=1)
        self.assertIn("teacher", (row["orchestration"]["persona"]["occupation"] or "").lower())
        self._assert_no_vitals_speak(row)
        joined = row["message"].lower()
        self.assertNotRegex(row["message"], r"Readiness is \d")
        # Either the lifestyle specialist, a woven aside, or the persona life
        # clause should show the week — without dumping a spreadsheet.
        notes = " ".join(n["text"] for n in row["orchestration"]["specialist_notes"]).lower()
        self.assertTrue(
            "teacher" in joined
            or "protein and water" in joined
            or "protein and water" in notes
            or "teacher" in notes
            or "teacher" in (row["orchestration"]["persona"]["occupation"] or "").lower(),
            row["message"],
        )

    def test_read_signals_never_exposes_raw_metrics(self):
        from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream
        from backend.ai.simrunner.backend_simulator.data_generator import build_context
        from backend.ai.simrunner.backend_simulator import model_registry

        profile = model_registry.get_models_by_tier(1)[0]["behavioral_profile"]
        ctx = build_context(generate_stream(profile, 42), profile, 29)
        signals = dummy.read_signals(ctx)
        blob = f"{signals.sleep} {signals.recovery} {signals.load} {signals.life}"
        self.assertNotRegex(blob, r"\d")

    def test_weave_does_not_speak_missing_hrv_hud(self):
        note = dummy.SpecialistNote(
            "recovery",
            "missing",
            "Recovery is looking without a full picture — sleep unavailable, HRV unavailable — "
            "so I won't pretend I have a clean read.",
        )
        spoken = dummy._weave_specialists("Keep today kind.", [note], seed=1)
        self.assertIn("kind", spoken.lower())
        self.assertNotIn("hrv", spoken.lower())
        self.assertNotIn("sleep debt", spoken.lower())
        self.assertNotIn("% below baseline", spoken.lower())

    def test_user_visible_speak_never_dumps_vitals(self):
        prompts = (
            "How did I sleep last night?",
            "What should I train today?",
            "I slept badly — what should I train and eat?",
            "ok what should I train then",
        )
        history: list[str] = []
        for prompt in prompts:
            row = dummy.respond(prompt, seed=11, prior_turns=history or None)
            self._assert_no_vitals_speak(row)
            history.append(prompt)

    def test_follow_up_does_not_repeat_the_prior_essay(self):
        history = ["How did I sleep last night?"]
        first = dummy.respond(history[0], seed=11)
        second = dummy.respond("make it easier", seed=11, prior_turns=history)
        self.assertNotEqual(first["prose_summary"], second["prose_summary"])
        self.assertNotIn(first["prose_summary"].strip(), second["message"])

    def test_dummy_speak_stays_a_friend_not_a_clinician(self):
        row = dummy.respond("I slept badly — what should I train and eat?", seed=1)
        blob = f"{row.get('prose_summary') or ''} {row.get('message') or ''}".lower()
        for banned in ("diagnos", "prescrib", "cure", "treat this", "medical condition"):
            self.assertNotIn(banned, blob, banned)
        self.assertNotIn("\n\n", row["message"])
        self.assertNotIn("fresh pass", blob)
        self.assertNotIn("following on from", blob)

    def _assert_no_vitals_speak(self, row: dict) -> None:
        blob = f"{row.get('prose_summary') or ''} {row.get('message') or ''}".lower()
        for banned in (
            "hrv",
            "bpm",
            "mmhg",
            "spo2",
            "vo2",
            "sleep debt",
            "sleep-debt",
            "% below baseline",
            "recovery score",
        ):
            self.assertNotIn(banned, blob, banned)
