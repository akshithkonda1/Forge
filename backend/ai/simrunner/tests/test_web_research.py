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

    def test_aging_questions_are_always_research_worthy(self):
        self.assertTrue(web_research.suggests_aging("what's my training age?"))
        self.assertTrue(web_research.is_research_worthy("what's my training age?", "aria"))
        self.assertTrue(web_research.is_research_worthy("VO2 max vs calendar", "workout"))
        self.assertFalse(web_research.suggests_aging("what should I train today?"))


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
        # Provenance contract: every successful lookup keeps a "From {source}:" label.
        self.assertRegex(result, r"^From [^:]+: ")

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

    def test_aging_lookup_cites_medlineplus_vo2(self):
        html = b"<html><body><p>VO2 max measures oxygen use during exercise.</p></body></html>"
        with patch.object(web_research, "urlopen", return_value=self._fake_response(status=200, body=html)):
            result = web_research.look_up("aging")
        self.assertIsNotNone(result)
        self.assertTrue(result.startswith("From MedlinePlus: Exercise Stress Test / VO2: "))
        self.assertIn("VO2 max", result)
        self.assertRegex(result, r"^From MedlinePlus: ")

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
            # Provenance gate patches look_up; still Dummy-local, not a live call site.
            package_root / "tests" / "test_nyx_eval_gates.py",
        }
        offenders = []
        for path in package_root.rglob("*.py"):
            if path in allowed or "__pycache__" in path.parts:
                continue
            if "web_research" in path.read_text(encoding="utf-8"):
                offenders.append(path)
        self.assertEqual(offenders, [], f"unexpected references to web_research: {offenders}")



# --- Expanded outside context (FORGE_DUMMY_WEB) -----------------------------

from backend.ai.simrunner.aria_simrunner.perception import ResearchNeed  # noqa: E402

MEDLINE_XML = b"""<?xml version="1.0" encoding="UTF-8"?>
<nlmSearchResult><term>creatine</term><count>1</count>
<list num="1" start="0" per="2">
<document rank="0" url="https://medlineplus.gov/dietarysupplements.html">
<content name="title">Dietary &lt;span class="qt0"&gt;Supplements&lt;/span&gt;</content>
<content name="FullSummary">&lt;p&gt;Dietary supplements are vitamins, minerals, herbs and other substances.&lt;/p&gt;&lt;p&gt;Talk with your health care provider first.&lt;/p&gt;</content>
</document>
<document rank="1" url="http://insecure.example/x"><content name="title">X</content><content name="FullSummary">Y</content></document>
</list></nlmSearchResult>"""

PUBMED_IDS = b'{"header":{},"esearchresult":{"count":"2","idlist":["111","222"]}}'
PUBMED_SUMMARY = (
    b'{"result":{"uids":["111"],"111":{"title":"Creatine and sleep deprivation.","source":"Sci Rep","pubdate":"2024 Feb 1"}}}'
)
FDA_LABEL = b'{"results":[{"indications_and_usage":["Temporarily relieves minor aches."],"warnings":["Stomach bleeding warning."],"openfda":{"generic_name":["IBUPROFEN"]}}]}'
FORECAST = b'{"current":{"time":"2026-09-30T14:00","temperature_2m":33.1,"apparent_temperature":37.4,"precipitation":0.0,"uv_index":8.5,"is_day":1}}'
AIR = b'{"current":{"time":"2026-09-30T14:00","us_aqi":112,"pm2_5":40.2}}'


class ExpandedParserTests(unittest.TestCase):
    def test_medlineplus(self):
        rows = web_research.parse_medlineplus(MEDLINE_XML)
        self.assertEqual(len(rows), 1)
        self.assertEqual(rows[0]["title"], "Dietary Supplements")
        self.assertNotIn("<p>", rows[0]["summary"])
        self.assertEqual(web_research.parse_medlineplus(b"<not xml"), [])

    def test_pubmed(self):
        self.assertEqual(web_research.parse_pubmed_ids(PUBMED_IDS), ["111", "222"])
        rows = web_research.parse_pubmed_summaries(PUBMED_SUMMARY)
        self.assertEqual(rows[0]["url"], "https://pubmed.ncbi.nlm.nih.gov/111/")
        self.assertEqual(rows[0]["year"], "2024")
        self.assertEqual(web_research.parse_pubmed_ids(b"{}"), [])

    def test_openfda(self):
        label = web_research.parse_openfda_label(FDA_LABEL)
        self.assertEqual(label["name"], "IBUPROFEN")
        self.assertIn("bleeding", label["warnings"])
        self.assertIsNone(web_research.parse_openfda_label(b'{"results":[]}'))

    def test_environment(self):
        env = web_research.parse_environment(FORECAST, AIR)
        self.assertEqual(env.apparent_temp_c, 37.4)
        self.assertEqual(env.us_aqi, 112)
        self.assertTrue(env.hot and env.smoky and env.harsh_sun)
        self.assertTrue(env.is_day)
        self.assertIsNone(web_research.parse_environment(None, b"junk"))

    def test_scout_brief(self):
        brief = {"answer": "Most adults need seven or more hours.", "confidence": 0.8,
                 "sources": [{"title": "CDC", "url": "https://www.cdc.gov/sleep"}, {"url": "http://bad"}]}
        ev = web_research.evidence_from_brief(brief)
        self.assertEqual(ev.via, "scout")
        self.assertEqual(len(ev.sources), 1)
        self.assertTrue(ev.cite().startswith("From cdc.gov:"))
        self.assertIsNone(web_research.evidence_from_brief({"answer": "x", "sources": []}))
        self.assertIsNone(web_research.evidence_from_brief({"answer": ""}))


class ExpandedGatingTests(unittest.TestCase):
    NEED = ResearchNeed(query="creatine sleep", topic="nutrition", why="test")

    def setUp(self):
        self._saved = {k: os.environ.get(k) for k in ("FORGE_DUMMY_WEB", "FORGE_SCOUT_URL", "FORGE_SCOUT_MODE", "ENVIRONMENT", "AWS_LAMBDA_FUNCTION_NAME")}
        for k in self._saved:
            os.environ.pop(k, None)
        from backend.scout import modes as scout_modes

        scout_modes.reset_for_tests()

    def tearDown(self):
        for key, value in self._saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_default_is_offline_scout_with_no_network(self):
        with patch.object(web_research, "urlopen") as mock_urlopen:
            evidence = web_research.research(ResearchNeed("how much sleep do adults need", "sleep", "t"))
            self.assertIsNone(web_research.environment(40.71, -74.01))
        mock_urlopen.assert_not_called()
        self.assertEqual((evidence.via, evidence.scout_mode), ("scout", "offline"))
        self.assertTrue(evidence.cite().startswith("From cdc.gov:"))

    def test_scout_off_and_web_off_is_dark(self):
        os.environ["FORGE_SCOUT_MODE"] = "off"
        with patch.object(web_research, "urlopen") as mock_urlopen:
            self.assertIsNone(web_research.research(self.NEED))
        mock_urlopen.assert_not_called()

    def test_refuses_network_in_cloud_even_when_enabled(self):
        os.environ["FORGE_DUMMY_WEB"] = "1"
        os.environ["AWS_LAMBDA_FUNCTION_NAME"] = "forge-api"
        for mode in ("local", "remote"):
            os.environ["FORGE_SCOUT_MODE"] = mode
            os.environ["FORGE_SCOUT_URL"] = "https://api.example.com/scout/research"
            with patch.object(web_research, "urlopen") as mock_urlopen:
                self.assertIsNone(web_research.research(self.NEED))
            mock_urlopen.assert_not_called()

    def _responses(self, mapping):
        def fake(request, timeout=0):
            url = request.full_url
            for needle, body in mapping.items():
                if needle in url:
                    return TestExpandedHelpers.response(body)
            raise URLError("no route")
        return fake

    def test_remote_scout_first(self):
        os.environ["FORGE_DUMMY_WEB"] = "1"
        os.environ["FORGE_SCOUT_MODE"] = "remote"
        os.environ["FORGE_SCOUT_URL"] = "https://api.example.com/scout/research"
        brief = b'{"answer":"Creatine may blunt some sleep-loss effects.","sources":[{"title":"PubMed","url":"https://pubmed.ncbi.nlm.nih.gov/1/"}],"confidence":0.7}'
        with patch.object(web_research, "urlopen", side_effect=self._responses({"scout/research": brief})) as m:
            ev = web_research.research(self.NEED)
        self.assertEqual((ev.via, ev.scout_mode), ("scout", "remote"))
        sent = m.call_args_list[0].args[0]
        self.assertEqual(sent.get_method(), "POST")
        self.assertIn(b"creatine sleep", sent.data)

    def test_falls_back_to_health_apis_then_catalog(self):
        os.environ["FORGE_DUMMY_WEB"] = "1"
        os.environ["FORGE_SCOUT_MODE"] = "off"
        with patch.object(web_research, "urlopen", side_effect=self._responses({"wsearch.nlm.nih.gov": MEDLINE_XML})):
            self.assertEqual(web_research.research(self.NEED).via, "medlineplus")
        with patch.object(web_research, "urlopen", side_effect=self._responses({"esearch": PUBMED_IDS, "esummary": PUBMED_SUMMARY})):
            self.assertEqual(web_research.research(ResearchNeed("creatine sleep", "training", "t")).via, "pubmed")
        html = b"<html><body><p>" + b"Adults need 150 minutes of activity each week. " * 5 + b"</p></body></html>"
        with patch.object(web_research, "urlopen", side_effect=self._responses({"cdc.gov": html})):
            self.assertEqual(web_research.research(ResearchNeed("zone two", "training", "t")).via, "catalog")

    def test_environment_rounds_location(self):
        os.environ["FORGE_DUMMY_WEB"] = "1"
        with patch.object(web_research, "urlopen", side_effect=self._responses({"api.open-meteo.com": FORECAST, "air-quality": AIR})) as m:
            env = web_research.environment(40.712776, -74.005974)
        self.assertTrue(env.hot)
        urls = " ".join(c.args[0].full_url for c in m.call_args_list)
        self.assertIn("latitude=40.7&", urls)
        self.assertNotIn("40.71", urls)


class TestExpandedHelpers:
    @staticmethod
    def response(body):
        resp = MagicMock()
        resp.status = 200
        resp.read.return_value = body
        resp.__enter__ = lambda s: s
        resp.__exit__ = lambda s, *a: False
        return resp


if __name__ == "__main__":
    unittest.main()
