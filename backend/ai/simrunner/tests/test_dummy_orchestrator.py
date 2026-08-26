import io
import os
import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import dummy_orchestrator as dummy  # noqa: E402
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
        self.assertTrue({"recover", "train", "fuel"} <= kinds)
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
        self.assertIn("train", row["agents"])
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
