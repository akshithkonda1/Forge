import io
import os
import sys
import unittest
from pathlib import Path
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
from backend.ai.simrunner.aria_simrunner import speak_quality  # noqa: E402
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
        row = dummy.respond("What should I train today?", seed=42, engine="stub")
        self.assertTrue(row["test_ready"])
        self.assertEqual(row["reasoning_source"], dummy.REASONING_SOURCE)
        self.assertEqual(row["model"], dummy.STUB_MODEL)
        self.assertEqual(row["user_id"], "test-user-00000000")
        self.assertIn("workout", row["agents"])
        self.assertTrue(row["prose_summary"].strip())

    def test_same_seed_is_deterministic(self):
        a = dummy.respond("How did I sleep last night?", seed=7, engine="stub")
        b = dummy.respond("How did I sleep last night?", seed=7, engine="stub")
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
            row = dummy.respond("What should I train today?", seed=1, engine="stub")
            self.assertEqual(row["reasoning_source"], dummy.REASONING_SOURCE)
        finally:
            bedrock_client.converse = original

    def test_research_worthy_message_appends_a_cited_web_note(self):
        with patch.object(web_research, "look_up", return_value="From Some Source: real info.") as mock_look_up:
            row = dummy.respond("how do I improve my workout routine?", seed=1, engine="stub")
        mock_look_up.assert_called_once_with("workout")
        # Trailing period may be normalized when the cite is parenthesized.
        self.assertIn("From Some Source: real info", row["message"])

    def test_training_age_looks_up_aging_web_source(self):
        plan = dummy.plan_workers("what's my training age?")
        self.assertEqual(plan.primary.kind, "aging")
        with patch.object(web_research, "look_up", return_value="From MedlinePlus: exercise stress test notes.") as mock_look_up:
            row = dummy.respond("what's my training age?", seed=1, engine="stub")
        mock_look_up.assert_called_once_with("aging")
        self.assertIn("From MedlinePlus: exercise stress test notes", row["message"])
        blob = (row["prose_summary"] + " " + row["message"]).lower()
        self.assertIn("lifestyle comparison", blob)
        self.assertIn("not a diagnosis", blob)

    def test_non_research_message_never_calls_web_research(self):
        with patch.object(web_research, "look_up") as mock_look_up:
            dummy.respond("What should I train today?", seed=1, engine="stub")
        mock_look_up.assert_not_called()

    def test_a_failed_lookup_leaves_the_reply_unchanged(self):
        with patch.object(web_research, "look_up", return_value=None):
            row = dummy.respond("how do I improve my workout routine?", seed=1, engine="stub")
        self.assertTrue(row["prose_summary"])
        self.assertEqual(row["message"], row["prose_summary"])

    def test_humanized_prose_does_not_dump_fields(self):
        # The stub used to splice `_context_phrase` ("Readiness is 96, HRV 52ms")
        # into the chat. The dummy orchestra must rewrite that before a person
        # (or voice-check) sees it.
        row = dummy.respond("How did I sleep last night?", seed=42, engine="stub")
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
        row = dummy.respond("I slept badly — what should I train and eat?", seed=1, engine="stub")
        self.assertNotRegex(row["message"], r"Recovery · ")
        self.assertNotRegex(row["message"], r"HRV \d+ms")
        self.assertIn("thinking", row)
        self.assertTrue(row["thinking"])

    def test_respond_includes_a_voice_diagnosis(self):
        row = dummy.respond("How did I sleep last night?", seed=42, engine="stub")
        diag = row["voice_diagnosis"]
        self.assertIn(diag["verdict"], ("human", "data_driven", "mixed"))
        self.assertIn("evidence", diag)

    def test_respond_voice_diagnosis_matches_diagnosing_the_prose_directly(self):
        row = dummy.respond("How did I sleep last night?", seed=42, engine="stub")
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
            row = dummy.respond("how do I improve my workout routine?", seed=1, engine="stub")
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
        row = dummy.respond("What should I train today?", seed=1, engine="stub")
        session = row.get("session")
        self.assertIsInstance(session, dict)
        self.assertTrue(session.get("exercises"))
        self.assertTrue(session.get("title"))
        self.assertNotRegex(session.get("reason") or "", r"\d+\s?(ms|bpm|sets)")

    def test_orchestration_envelope_is_a_real_pipeline(self):
        row = dummy.respond("I slept badly — what should I train and eat?", seed=1, engine="stub")
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
            engine="stub",
        )
        b = dummy.respond(
            "What should I train today?",
            seed=3,
            prior_turns=["How did I sleep last night?"],
            engine="stub",
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
        fresh = dummy.respond("What should I train today?", seed=3, engine="stub")
        self.assertNotEqual(fresh["prose_summary"], a["prose_summary"])

    def test_multi_turn_sounds_spoken_not_templated(self):
        history = ["How did I sleep last night?"]
        first = dummy.respond(history[0], seed=11, engine="stub")
        second = dummy.respond(
            "ok what should I train then",
            seed=11,
            prior_turns=history,
            engine="stub",
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
        easier = dummy.respond("make it easier", seed=11, prior_turns=history, engine="stub")
        shorter = dummy.respond("shorter", seed=11, prior_turns=history + ["make it easier"], engine="stub")
        skip = dummy.respond("skip it", seed=11, prior_turns=history + ["make it easier", "shorter"], engine="stub")
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
            engine="stub",
        )
        self.assertNotIn("\n\n", row["message"])
        # Orchestration still records specialists; the user-facing message does not list them as reports.
        self.assertTrue(row["orchestration"]["specialists"])
        for note in row["orchestration"]["specialist_notes"]:
            # Full specialist sentences should not appear as their own paragraph.
            self.assertNotIn(f"\n\n{note['text']}", row["message"])

    def test_phrase_banks_vary_across_seeds(self):
        texts = {
            dummy.respond("What should I train today?", seed=s, engine="stub")["prose_summary"]
            for s in range(20, 40)
        }
        # Enough spoken variety that twenty seeds are not a single canned line.
        self.assertGreaterEqual(len(texts), 4)

    def test_persona_colors_lifestyle_without_dumping_fields(self):
        # Default tier-1 persona is a teacher. Lifestyle asides should sound
        # like they know the life, not like they read a spreadsheet.
        row = dummy.respond("I slept badly — what should I train and eat?", seed=1, engine="stub")
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
            row = dummy.respond(prompt, seed=11, prior_turns=history or None, engine="stub")
            self._assert_no_vitals_speak(row)
            history.append(prompt)

    def test_follow_up_does_not_repeat_the_prior_essay(self):
        history = ["How did I sleep last night?"]
        first = dummy.respond(history[0], seed=11, engine="stub")
        second = dummy.respond("make it easier", seed=11, prior_turns=history, engine="stub")
        self.assertNotEqual(first["prose_summary"], second["prose_summary"])
        self.assertNotIn(first["prose_summary"].strip(), second["message"])

    def test_dummy_speak_stays_a_friend_not_a_clinician(self):
        row = dummy.respond("I slept badly — what should I train and eat?", seed=1, engine="stub")
        fails = speak_quality.speak_failures(row)
        self.assertEqual(fails, [], fails)
        self.assertTrue(speak_quality.has_friend_throughline(speak_quality.user_visible_blob(row)))
        self.assertNotIn("\n\n", row["message"])

    def test_default_engine_is_lambda_hypertune(self):
        row = dummy.respond("What should I train today?", seed=5)
        stub = dummy.respond("What should I train today?", seed=5, engine="stub")
        self.assertEqual(row["reasoning_source"], dummy.LAMBDA_REASONING_SOURCE)
        self.assertEqual(row["orchestration"]["engine"], dummy.ENGINE_LAMBDA)
        self.assertEqual(stub["reasoning_source"], dummy.REASONING_SOURCE)
        self.assertEqual(stub["model"], dummy.STUB_MODEL)
        self.assertNotEqual(row["prose_summary"], stub["prose_summary"])

    def test_lambda_engine_refuses_cloud_and_production(self):
        os.environ["ENVIRONMENT"] = "production"
        with self.assertRaises(RuntimeError):
            dummy.respond("What should I train today?", engine="lambda")
        os.environ.pop("ENVIRONMENT", None)
        previous = os.environ.get("AWS_LAMBDA_FUNCTION_NAME")
        os.environ["AWS_LAMBDA_FUNCTION_NAME"] = "forge-dummy-test"
        try:
            with self.assertRaises(RuntimeError) as ctx:
                dummy.respond("how did I sleep?", engine="lambda")
            self.assertIn("local-only", str(ctx.exception))
        finally:
            if previous is None:
                os.environ.pop("AWS_LAMBDA_FUNCTION_NAME", None)
            else:
                os.environ["AWS_LAMBDA_FUNCTION_NAME"] = previous

    def test_lambda_engine_never_calls_bedrock(self):
        from backend._paths import ensure_lambda_on_path
        from backend.ai.simrunner.aria_simrunner import bedrock_client

        ensure_lambda_on_path()
        from services import aria_engine as engine_mod

        def boom(*_args, **_kwargs):
            raise AssertionError("dummy lambda engine must not call Bedrock")

        original = bedrock_client.converse
        live = engine_mod.generate_response_live
        bedrock_client.converse = boom
        engine_mod.generate_response_live = boom
        try:
            self.assertFalse(engine_mod.bedrock_enabled())
            row = dummy.respond("What should I train today?", seed=1, engine="lambda")
            self.assertEqual(row["reasoning_source"], dummy.LAMBDA_REASONING_SOURCE)
            self.assertEqual(row["model"], dummy.LAMBDA_MODEL)
        finally:
            bedrock_client.converse = original
            engine_mod.generate_response_live = live

    def test_lambda_engine_uses_fuse_turn_and_generate_response(self):
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import aria_engine as engine_mod
        from services import fusion as fusion_mod

        with patch.object(fusion_mod, "fuse_turn", wraps=fusion_mod.fuse_turn) as fuse:
            with patch.object(
                engine_mod, "generate_response", wraps=engine_mod.generate_response
            ) as gen:
                with patch.object(engine_mod, "generate_response_live") as live:
                    row = dummy.respond("What should I train today?", seed=1)
        fuse.assert_called_once()
        self.assertFalse(fuse.call_args.kwargs.get("persist", True))
        gen.assert_called_once()
        live.assert_not_called()
        self.assertEqual(row["orchestration"]["engine"], dummy.ENGINE_LAMBDA)
        self.assertIn(row["fusion"]["source"], ("body_model", "payload", "persisted"))
        self.assertTrue(row["orchestration"]["observation_count"] >= 0)

    def test_lambda_engine_guidance_short_circuit(self):
        row = dummy.respond("diagnose me", seed=1, engine="lambda")
        self.assertEqual(row.get("guidance_band"), "refer_out")
        blob = f"{row['prose_summary']} {row['message']}".lower()
        self.assertIn("not a doctor", blob)
        self.assertNotIn("guidance_band", dummy.respond("What should I train today?", seed=1, engine="lambda"))

    def test_lambda_engine_stance_protect_changes_session_or_prose(self):
        proceed = dummy.respond("What should I train today?", seed=1, engine="lambda")
        protect = dummy.respond(
            "What should I train today?",
            seed=1,
            engine="lambda",
            lifestyle_tags=["calendar:kind:wedding", "calendar:evening:busy", "calendar:busy:4"],
        )
        self.assertEqual(protect["fusion"]["stance"], "protect")
        self.assertNotEqual(proceed["fusion"]["stance"], "protect")
        proceed_session = proceed.get("session") or {}
        protect_session = protect.get("session") or {}
        self.assertTrue(proceed_session)
        self.assertTrue(protect_session)
        self.assertTrue(
            proceed_session != protect_session
            or proceed["prose_summary"] != protect["prose_summary"]
            or (proceed.get("card") or {}).get("action") != (protect.get("card") or {}).get("action"),
            (proceed["prose_summary"], protect["prose_summary"]),
        )
        self.assertIn("protect", (protect_session.get("reason") or protect["prose_summary"]).lower())

    def test_lambda_engine_no_vitals_dump(self):
        for prompt in (
            "How did I sleep last night?",
            "What should I train today?",
            "I slept badly — what should I train and eat?",
        ):
            row = dummy.respond(prompt, seed=11, engine="lambda")
            self._assert_no_vitals_speak(row)
            self.assertTrue(row["prose_summary"].strip())

    def test_lambda_engine_strips_partner_cycle_tags_before_fuse(self):
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import fusion as fusion_mod

        captured: dict = {}
        original = fusion_mod.fuse_turn

        def wrap(user_id, payload, *args, **kwargs):
            captured["payload"] = payload
            return original(user_id, payload, *args, **kwargs)

        with patch.object(fusion_mod, "fuse_turn", side_effect=wrap):
            dummy.respond(
                "What should I train today?",
                seed=1,
                engine="lambda",
                lifestyle_tags=[
                    "partner_name:Sam",
                    "calendar:kind:wedding",
                    "cycle:bleeding",
                    "calendar:evening:busy",
                ],
            )
        tags = ((captured.get("payload") or {}).get("context") or {}).get("lifestyle") or {}
        kept = tags.get("tags") or []
        blob = " ".join(kept).lower()
        self.assertNotIn("partner_name", blob)
        self.assertNotIn("cycle:bleeding", blob)
        self.assertIn("calendar:kind:wedding", kept)

    def test_lambda_engine_speak_stays_a_friend_not_a_clinician(self):
        row = dummy.respond("What should I train today?", seed=1, engine="lambda")
        fails = speak_quality.speak_failures(row)
        self.assertEqual(fails, [], fails)
        self.assertEqual(speak_quality.medical_hits(speak_quality.user_visible_blob(row)), [])
        self.assertEqual(speak_quality.bark_hits(speak_quality.user_visible_blob(row)), [])

    def test_both_engines_skip_empty_cheerleading(self):
        banned = (
            "crushing it",
            "you got this",
            "you're killing it",
            "great job",
            "beast mode",
            "so proud",
        )
        for engine in ("stub", "lambda"):
            row = dummy.respond("What should I train today?", seed=1, engine=engine)
            blob = f"{row.get('prose_summary') or ''} {row.get('message') or ''}".lower()
            for phrase in banned:
                self.assertNotIn(phrase, blob, f"{engine}: {phrase}")
            self._assert_no_vitals_speak(row)
            self.assertNotIn("\n\n", row["message"])

    def test_both_engines_sound_like_a_friend_with_a_point(self):
        bank_hooks = tuple(
            line.split("—", 1)[0].strip().lower()
            for line in dummy._WIT_PROTECT + dummy._WIT_PROCEED + dummy._WIT_HONEST
            if "—" in line
        )
        needles = bank_hooks + (
            "clap you into",
            "victory-lap",
            "spend it like it's a dare",
            "plot getting interesting",
            "hold-steady",
            "don't-pick-a-fight",
            "not a pep talk",
            "not a parade",
            "sharp, not endless",
            "hero set",
            "sparkle in the tank",
            "hug with a point",
            "cozy-sweater",
        )
        for engine in ("stub", "lambda"):
            row = dummy.respond("What should I train today?", seed=1, engine=engine)
            blob = f"{row.get('prose_summary') or ''} {row.get('message') or ''}".lower()
            self.assertTrue(
                any(n in blob for n in needles),
                f"{engine} sounded like sludge: {row.get('prose_summary')!r}",
            )
            for banned in ("prescrib", "cure", "treat this", "medical condition"):
                self.assertNotIn(banned, blob, banned)

    def test_soft_wit_banks_are_funny_useful_friends_not_dry_bark(self):
        """Iris contract: each wit line is a funny take + one useful improve."""
        banks = {
            "protect": dummy._WIT_PROTECT,
            "proceed": dummy._WIT_PROCEED,
            "honest": dummy._WIT_HONEST,
        }
        funny = (
            "cute", "sparkle", "sparkly", "cozy", "hug", "plot", "cheering",
            "sweater", "montage", "fireworks", "encore", "crispy", "whisper",
            "friend", "double-dare", "go-play", "restock", "low-power",
            "villain", "meh", "maybe", "messy", "flop", "snack", "drafts",
            "please-be-nice", "tucking", "unwrap", "sparkle included",
        )
        useful = (
            "walk", "bed", "lights", "wind-down", "protein", "water", "meal",
            "easy", "gentle", "short", "one thing", "one clean", "one quality",
            "one honest", "one familiar", "stop", "session", "earlier",
            "protect", "soft", "kind", "sleep", "eat",
        )
        retired_dry = (
            "audience that isn't there",
            "no to performing",
            "not a pep talk. a read",
            "clap you into a hole",
            "sharp over loud",
            "heroics no",
        )
        seen: set[str] = set()
        for name, lines in banks.items():
            self.assertGreaterEqual(len(lines), 8, name)
            for line in lines:
                with self.subTest(bank=name, line=line):
                    self.assertNotIn(line, seen, "wit rotation needs unique lines")
                    seen.add(line)
                    self.assertIn("—", line, "funny take — useful improve")
                    low = line.lower()
                    self.assertTrue(
                        any(tok in low for tok in funny),
                        f"{name} missing funny take: {line!r}",
                    )
                    self.assertTrue(
                        any(tok in low for tok in useful),
                        f"{name} missing useful improve: {line!r}",
                    )
                    self.assertTrue(
                        speak_quality.has_friend_throughline(line),
                        f"{name} missing friend throughline: {line!r}",
                    )
                    self.assertEqual(speak_quality.bark_hits(line), [], line)
                    self.assertEqual(speak_quality.medical_hits(line), [], line)
                    self.assertEqual(speak_quality.vitals_hits(line), [], line)
                    self.assertEqual(speak_quality.sludge_hits(line), [], line)
                    for cold in retired_dry:
                        self.assertNotIn(cold, low, line)

    def test_friend_speak_appends_seed_indexed_soft_wit(self):
        body = (
            "You've got something to spend, since the night actually paid you back. "
            "A solid moderate session fits if we progress one thing and leave the extra volume. "
            "Want the session mapped, or just this read?"
        )
        self.assertGreaterEqual(len(body.split()), 28)
        for stance, bank in (
            ("protect", dummy._WIT_PROTECT),
            ("proceed", dummy._WIT_PROCEED),
            ("honest", dummy._WIT_HONEST),
        ):
            spoken = dummy.friend_speak(body, seed=1, stance=stance)
            extra = dummy._pick(1 ^ 17, list(bank))
            self.assertIn(extra, spoken)
            self.assertTrue(spoken.startswith(body))
            self.assertEqual(speak_quality.bark_hits(spoken), [])
            self.assertEqual(speak_quality.medical_hits(spoken), [])
            again = dummy.friend_speak(body, seed=1, stance=stance)
            self.assertEqual(spoken, again)
            other = dummy.friend_speak(body, seed=2, stance=stance)
            # Different seeds may land the same slot; variety is the bank size.
            self.assertIn(dummy._pick(2 ^ 17, list(bank)), other)

    def test_friend_speak_replaces_thin_or_fallback_with_seeded_wit(self):
        """Fused Dummy often lands the canned fallback or a stripped '.' — still local wit."""
        for thin in (dummy._SPEAK_FALLBACK, ".", "  ...  ", ""):
            spoken = dummy.friend_speak(thin, seed=4, stance="protect")
            extra = dummy._wit_line(4, "protect")
            self.assertEqual(spoken, extra)
            self.assertNotEqual(spoken, dummy._SPEAK_FALLBACK)
            self.assertEqual(dummy.friend_speak(thin, seed=4, stance="protect"), spoken)
            other = dummy.friend_speak(thin, seed=9, stance="protect")
            self.assertEqual(other, dummy._wit_line(9, "protect"))
            self.assertTrue(speak_quality.has_friend_throughline(spoken))
            self.assertEqual(speak_quality.vitals_hits(spoken), [])
            self.assertEqual(speak_quality.bark_hits(spoken), [])

    def test_friend_speak_short_ok_appends_wit_to_fused_notices(self):
        short = "Keep today low-intensity — Zone 2 cardio or mobility, not a hard session"
        self.assertLess(len(short.split()), 28)
        skipped = dummy.friend_speak(short, seed=2, stance="protect")
        self.assertEqual(skipped, short)
        spoken = dummy.friend_speak(short, seed=2, stance="protect", short_ok=True)
        extra = dummy._wit_line(2, "protect")
        self.assertIn(extra, spoken)
        self.assertTrue(spoken.startswith(short))
        self.assertEqual(
            dummy.friend_speak(short, seed=2, stance="protect", short_ok=True),
            spoken,
        )

    def test_friend_speak_leaves_guidance_and_follow_ups_alone(self):
        guard = "I'm not a doctor. Please talk to a clinician."
        self.assertEqual(
            dummy.friend_speak(guard, seed=1, stance="protect", guidance="refer_out"),
            guard,
        )
        follow = "Sure — we dial it back. Same idea, less intensity, stop while it still feels good."
        self.assertEqual(dummy.friend_speak(follow, seed=1, stance="protect", short_ok=True), follow)

    def test_lambda_sleep_and_checkin_get_local_seeded_wit(self):
        wit = dummy._WIT_PROTECT + dummy._WIT_PROCEED + dummy._WIT_HONEST
        seen: set[str] = set()
        for seed in (1, 2, 4, 9):
            for prompt in ("How did I sleep last night?", "hey"):
                row = dummy.respond(prompt, seed=seed, engine="lambda")
                blob = f"{row.get('prose_summary') or ''} {row.get('message') or ''}"
                self.assertTrue(
                    any(line in blob for line in wit),
                    f"seed={seed} {prompt!r} had no local wit: {row.get('prose_summary')!r}",
                )
                self.assertNotEqual(row["prose_summary"].strip(), ".")
                self._assert_no_vitals_speak(row)
                self.assertTrue(speak_quality.has_friend_throughline(blob))
                seen.add(row["prose_summary"])
        self.assertGreaterEqual(len(seen), 3, seen)
        a = dummy.respond("How did I sleep last night?", seed=4, engine="lambda")
        b = dummy.respond("How did I sleep last night?", seed=4, engine="lambda")
        self.assertEqual(a["prose_summary"], b["prose_summary"])
        self.assertEqual(a["message"], b["message"])

    def test_stub_train_attaches_wit_after_body_session(self):
        row = dummy.respond("What should I train today?", seed=3, engine="stub")
        blob = f"{row.get('prose_summary') or ''} {row.get('message') or ''}"
        self.assertTrue(
            any(line in blob for line in dummy._WIT_PROCEED + dummy._WIT_PROTECT + dummy._WIT_HONEST),
            row.get("prose_summary"),
        )
        self._assert_no_vitals_speak(row)

    def test_lambda_engine_same_seed_is_deterministic(self):
        a = dummy.respond("How did I sleep last night?", seed=7, engine="lambda")
        b = dummy.respond("How did I sleep last night?", seed=7, engine="lambda")
        self.assertEqual(a["prose_summary"], b["prose_summary"])
        self.assertEqual(a["message"], b["message"])
        self.assertEqual(a["fusion"]["stance"], b["fusion"]["stance"])
        self.assertEqual(a["reasoning_source"], dummy.LAMBDA_REASONING_SOURCE)

    def test_swarm_runs_on_every_engine_without_a_model(self):
        for engine in ("stub", "lambda"):
            row = dummy.respond("What should I train today?", seed=1, engine=engine)
            swarm = row["swarm"]
            self.assertEqual(swarm["name"], "swarm")
            self.assertEqual(swarm["slot_name"], "Grok")
            self.assertTrue(swarm["agentic"])
            self.assertIsNone(swarm["model"])
            self.assertEqual(swarm["stages"], ["read", "evaluate", "write"])
            present = {s["id"] for s in swarm["sources"] if s["present"]}
            self.assertTrue({"whoop", "apple-watch", "oura"} <= present, present)
            self.assertTrue(row["orchestration"]["swarm"])
            self.assertIn("Grok", row["orchestration"]["swarm_slot"])
            self.assertTrue(swarm["picture"]["headline"])
            self.assertTrue(swarm["picture"]["writes"])
            self._assert_no_vitals_speak(row)
            self.assertNotIn("HRV", swarm["picture"]["headline"])

    def test_stream_samples_are_vendor_tagged_not_simrunner(self):
        from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream
        from backend.ai.simrunner.backend_simulator.data_generator import build_context
        from backend.ai.simrunner.backend_simulator import model_registry

        profile = model_registry.get_models_by_tier(1)[0]["behavioral_profile"]
        ctx = build_context(generate_stream(profile, 42), profile, 29)
        samples = dummy._stream_samples(ctx)
        sources = {s["source"] for s in samples}
        self.assertNotIn("simrunner", sources)
        self.assertTrue({"whoop", "oura", "apple-watch"} & sources, sources)
        by_type = {s["type"]: s["source"] for s in samples}
        if "sleep" in by_type:
            self.assertEqual(by_type["sleep"], "oura")
        if "hrv" in by_type:
            self.assertEqual(by_type["hrv"], "whoop")
        if "steps" in by_type:
            self.assertEqual(by_type["steps"], "apple-watch")

    def test_swarm_is_sidecar_not_spoken(self):
        row = dummy.respond("What should I train today?", seed=1, engine="stub")
        headline = row["swarm"]["picture"]["headline"]
        # Swarm writes an actionable picture; chat still speaks like a friend.
        self.assertNotIn(headline, row["message"])
        self.assertIn("Swarm read", row["thinking"])

    def _assert_no_vitals_speak(self, row: dict) -> None:
        fails = speak_quality.speak_failures(row)
        self.assertEqual(fails, [], fails)
        blob = speak_quality.user_visible_blob(row)
        self.assertTrue(blob.strip())
        self.assertEqual(speak_quality.vitals_hits(row.get("prose_summary") or ""), [])
