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
        self.assertIn("From Some Source: real info.", row["message"])

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
        prose = row["prose_summary"]
        self.assertNotRegex(prose, r"Readiness is \d")
        self.assertNotRegex(prose, r"\bHRV \d")
        self.assertNotRegex(prose, r"\bACWR ")
        self.assertNotIn("sleep debt", prose.lower())
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
