import os
import sys
import unittest
from pathlib import Path
from unittest.mock import MagicMock, patch
from urllib.error import HTTPError, URLError

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import web_research  # noqa: E402


class IsResearchWorthyTests(unittest.TestCase):
    def test_requires_a_curated_kind(self):
        self.assertFalse(web_research.is_research_worthy("how do I fix my sleep?", "sleep"))
        self.assertFalse(web_research.is_research_worthy("how do I show up for her?", "cycle"))
        self.assertFalse(web_research.is_research_worthy("how do I fix this?", "aria"))

    def test_requires_research_flavored_phrasing(self):
        self.assertFalse(web_research.is_research_worthy("what should I train today?", "workout"))
        self.assertFalse(web_research.is_research_worthy("log my workout", "workout"))

    def test_true_for_curated_kind_and_phrasing(self):
        self.assertTrue(web_research.is_research_worthy("how do I recomp effectively?", "workout"))
        self.assertTrue(web_research.is_research_worthy("how much protein should I eat?", "lifestyle"))
        self.assertTrue(web_research.is_research_worthy("what does research say about rest days?", "progress"))

    def test_is_case_insensitive(self):
        self.assertTrue(web_research.is_research_worthy("HOW DO I get stronger?", "workout"))


class LookUpGatingTests(unittest.TestCase):
    def setUp(self):
        self._saved_env = {k: os.environ.get(k) for k in (
            "ENVIRONMENT", "AWS_LAMBDA_FUNCTION_NAME", "K_SERVICE",
        )}

    def tearDown(self):
        for key, value in self._saved_env.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_returns_none_for_uncurated_kind_without_a_network_attempt(self):
        with patch.object(web_research, "urlopen") as mock_urlopen:
            self.assertIsNone(web_research.look_up("cycle"))
            self.assertIsNone(web_research.look_up("recovery"))
            self.assertIsNone(web_research.look_up("sleep"))
            mock_urlopen.assert_not_called()

    def test_returns_none_on_production_environment_without_a_network_attempt(self):
        os.environ["ENVIRONMENT"] = "production"
        with patch.object(web_research, "urlopen") as mock_urlopen:
            self.assertIsNone(web_research.look_up("workout"))
            mock_urlopen.assert_not_called()

    def test_returns_none_on_cloud_runtime_without_a_network_attempt(self):
        os.environ["AWS_LAMBDA_FUNCTION_NAME"] = "some-function"
        with patch.object(web_research, "urlopen") as mock_urlopen:
            self.assertIsNone(web_research.look_up("workout"))
            mock_urlopen.assert_not_called()


class LookUpFetchTests(unittest.TestCase):
    def _fake_response(self, *, status: int, body: bytes):
        response = MagicMock()
        response.status = status
        response.read.return_value = body
        response.__enter__ = MagicMock(return_value=response)
        response.__exit__ = MagicMock(return_value=False)
        return response

    def test_success_extracts_text_and_cites_the_source(self):
        html = (
            b"<html><head><style>body{color:red}</style></head>"
            b"<body><script>track();</script>"
            b"<h1>Exercise</h1><p>Move  more.  Rest  well.</p></body></html>"
        )
        with patch.object(web_research, "urlopen", return_value=self._fake_response(status=200, body=html)):
            result = web_research.look_up("workout")
        self.assertIsNotNone(result)
        self.assertTrue(result.startswith("From MedlinePlus: Exercise and Physical Fitness: "))
        self.assertIn("Exercise", result)
        self.assertIn("Move more. Rest well.", result)
        self.assertNotIn("<", result)
        self.assertNotIn("track();", result)

    def test_decodes_html_entities_beyond_the_basic_four(self):
        # A genuine improvement over the Swift original's hand-rolled 4-entity
        # table: stdlib `html.unescape` decodes every standard entity.
        html = b"<p>Recovery&hellip; and progress &mdash; both matter.</p>"
        with patch.object(web_research, "urlopen", return_value=self._fake_response(status=200, body=html)):
            result = web_research.look_up("progress")
        self.assertIn("Recovery… and progress — both matter.", result)

    def test_non_200_status_returns_none(self):
        with patch.object(web_research, "urlopen", return_value=self._fake_response(status=404, body=b"")):
            self.assertIsNone(web_research.look_up("workout"))

    def test_empty_body_returns_none(self):
        with patch.object(web_research, "urlopen", return_value=self._fake_response(status=200, body=b"<html></html>")):
            self.assertIsNone(web_research.look_up("workout"))

    def test_http_error_returns_none(self):
        with patch.object(web_research, "urlopen", side_effect=HTTPError("url", 500, "err", {}, None)):
            self.assertIsNone(web_research.look_up("workout"))

    def test_url_error_returns_none(self):
        with patch.object(web_research, "urlopen", side_effect=URLError("no route")):
            self.assertIsNone(web_research.look_up("workout"))

    def test_timeout_returns_none(self):
        with patch.object(web_research, "urlopen", side_effect=TimeoutError()):
            self.assertIsNone(web_research.look_up("workout"))

    def test_never_imports_a_cloud_sdk(self):
        src = Path(web_research.__file__).read_text()
        imports = [
            line.strip()
            for line in src.splitlines()
            if line.strip().startswith(("import ", "from "))
        ]
        forbidden = ("boto3", "botocore", "requests", "httpx", "bedrock_client")
        for stmt in imports:
            for needle in forbidden:
                self.assertNotIn(needle, stmt, f"web_research imported {needle}")

    def test_only_referenced_from_dummy_orchestrator_and_its_own_tests(self):
        """Same isolation invariant `check-aria-web-research.py` enforces for
        the Swift side, ported here: a call site added anywhere outside
        `dummy_orchestrator.py` would risk this keyless reference fetch
        running from a context that was never actually gated behind
        `refuse_if_cloud()`."""
        package_root = Path(web_research.__file__).resolve().parent.parent
        allowed = {
            package_root / "aria_simrunner" / "dummy_orchestrator.py",
            package_root / "aria_simrunner" / "web_research.py",
            package_root / "tests" / "test_web_research.py",
            package_root / "tests" / "test_dummy_orchestrator.py",
        }
        offenders = []
        for path in package_root.rglob("*.py"):
            if path in allowed or "__pycache__" in path.parts:
                continue
            if "web_research" in path.read_text(encoding="utf-8"):
                offenders.append(path)
        self.assertEqual(offenders, [], f"unexpected references to web_research: {offenders}")


if __name__ == "__main__":
    unittest.main()
