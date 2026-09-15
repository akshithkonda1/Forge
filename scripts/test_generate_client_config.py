#!/usr/bin/env python3
"""Ship-gate tests for Dummy-offline client config.

These prove the committed Info-Add.plist is TestFlight-safe (no loopback, no
live-looking Cognito) and that generate_client_config.py still consumes
Terraform client_configuration for a later live API path.
"""

from __future__ import annotations

import importlib.util
import io
import json
import os
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
SCRIPT = ROOT / "scripts" / "generate_client_config.py"
PLIST = ROOT / "ForgeSwift" / "ForgeSwift" / "Info-Add.plist"


def _load_module():
    spec = importlib.util.spec_from_file_location("generate_client_config", SCRIPT)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    spec.loader.exec_module(module)
    return module


mod = _load_module()


def _base(**overrides: str) -> dict[str, str]:
    values = dict(mod.DUMMY_OFFLINE_VALUES)
    values.update(overrides)
    return values


def _terraform_outputs(
    api: str = "https://api.example.execute-api.us-east-1.amazonaws.com",
    region: str = "us-east-1",
    ios_client: str = "iosclientid123",
    pool: str = "us-east-1_AbCdEf",
) -> dict:
    return {
        "client_configuration": {
            "value": {
                "apiBaseUrl": api,
                "cognito": {
                    "region": region,
                    "iosClientId": ios_client,
                    "userPoolId": pool,
                },
            }
        }
    }


class CommittedPlistShipGateTests(unittest.TestCase):
    def test_check_passes_on_committed_dummy_offline_plist(self):
        code = mod.main(["--check"])
        self.assertEqual(code, 0)

    def test_committed_plist_has_no_loopback(self):
        text = PLIST.read_text(encoding="utf-8")
        values = mod.read_plist_values(text)
        blob = " ".join(values.values())
        for host in mod.LOOPBACK_HOSTS:
            self.assertNotIn(host, blob, f"shipped client config values must not contain {host}")
        self.assertEqual(values["FORGEEnvironment"], "dummy")
        self.assertEqual(values["FORGEAPIBaseURL"], "")
        self.assertEqual(values["FORGECognitoRegion"], "")
        self.assertEqual(values["FORGECognitoClientId"], "")
        self.assertEqual(values["FORGECognitoUserPoolId"], "")

    def test_committed_plist_is_valid_xml(self):
        parsed = mod.parse_plist(PLIST.read_text(encoding="utf-8"))
        self.assertEqual(parsed["FORGEEnvironment"], "dummy")
        self.assertEqual(parsed["FORGEAPIBaseURL"], "")


class ValidateDummyOfflineTests(unittest.TestCase):
    def test_dummy_offline_empty_config_is_ok(self):
        self.assertEqual(mod.validate(_base()), [])

    def test_rejects_loopback_in_dummy(self):
        problems = mod.validate(_base(FORGEAPIBaseURL="http://127.0.0.1:3001"))
        self.assertTrue(any("Loopback" in p or "127.0.0.1" in p for p in problems))
        self.assertTrue(any("Dummy-offline" in p for p in problems))

    def test_rejects_localhost_in_any_environment(self):
        problems = mod.validate(
            _base(
                FORGEEnvironment="dev",
                FORGEAPIBaseURL="http://localhost:3001",
                FORGECognitoRegion="us-east-1",
                FORGECognitoClientId="abc",
                FORGECognitoUserPoolId="us-east-1_x",
            )
        )
        self.assertTrue(any("Loopback" in p or "localhost" in p for p in problems))

    def test_rejects_dummy_with_live_looking_cognito(self):
        problems = mod.validate(
            _base(
                FORGECognitoRegion="us-east-1",
                FORGECognitoClientId="iosclient",
                FORGECognitoUserPoolId="us-east-1_pool",
            )
        )
        self.assertTrue(any("Cognito" in p for p in problems))
        self.assertTrue(any("live auth" in p for p in problems))

    def test_rejects_dummy_with_live_api(self):
        problems = mod.validate(
            _base(FORGEAPIBaseURL="https://api.example.execute-api.us-east-1.amazonaws.com")
        )
        self.assertTrue(any("Dummy-offline" in p for p in problems))

    def test_production_requires_https_and_cognito(self):
        problems = mod.validate(
            {
                "FORGEAPIBaseURL": "https://api.example.execute-api.us-east-1.amazonaws.com",
                "FORGECognitoRegion": "us-east-1",
                "FORGECognitoClientId": "iosclient",
                "FORGECognitoUserPoolId": "us-east-1_pool",
                "FORGEEnvironment": "prod",
            }
        )
        self.assertEqual(problems, [])

    def test_production_rejects_empty_cognito(self):
        problems = mod.validate(
            {
                "FORGEAPIBaseURL": "https://api.example.execute-api.us-east-1.amazonaws.com",
                "FORGECognitoRegion": "",
                "FORGECognitoClientId": "",
                "FORGECognitoUserPoolId": "",
                "FORGEEnvironment": "prod",
            }
        )
        self.assertTrue(any("FORGECognitoClientId" in p for p in problems))

    def test_dev_with_api_and_empty_cognito_looks_live(self):
        problems = mod.validate(
            {
                "FORGEAPIBaseURL": "https://api.example.execute-api.us-east-1.amazonaws.com",
                "FORGECognitoRegion": "",
                "FORGECognitoClientId": "",
                "FORGECognitoUserPoolId": "",
                "FORGEEnvironment": "dev",
            }
        )
        self.assertTrue(any("forgotten Cognito" in p for p in problems))


class DummyOfflineCliTests(unittest.TestCase):
    def test_dummy_offline_dry_run_needs_no_terraform(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            code = mod.main(["--dummy-offline", "--dry-run"])
        self.assertEqual(code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload, mod.DUMMY_OFFLINE_VALUES)
        self.assertEqual(payload["FORGEAPIBaseURL"], "")
        self.assertEqual(payload["FORGEEnvironment"], "dummy")

    def test_environment_dummy_dry_run_needs_no_stack_outputs(self):
        stdout = io.StringIO()
        with redirect_stdout(stdout):
            code = mod.main(["--environment", "dummy", "--dry-run"])
        self.assertEqual(code, 0)
        self.assertEqual(json.loads(stdout.getvalue())["FORGEEnvironment"], "dummy")

    def test_dummy_offline_refuses_terraform_outputs(self):
        stderr = io.StringIO()
        with self.assertRaises(SystemExit) as caught, redirect_stderr(stderr):
            mod.main(["--dummy-offline", "--from", "out.json"])
        self.assertEqual(caught.exception.code, 2)
        self.assertIn("does not take stack outputs", stderr.getvalue())

    def test_dummy_offline_refuses_live_environment(self):
        stderr = io.StringIO()
        with self.assertRaises(SystemExit) as caught, redirect_stderr(stderr):
            mod.main(["--dummy-offline", "--environment", "prod"])
        self.assertEqual(caught.exception.code, 2)
        self.assertIn("cannot be combined with a live", stderr.getvalue())


class TerraformLivePathTests(unittest.TestCase):
    def test_from_terraform_outputs_maps_client_configuration(self):
        values = mod.from_terraform_outputs(_terraform_outputs(), "prod")
        self.assertEqual(
            values["FORGEAPIBaseURL"],
            "https://api.example.execute-api.us-east-1.amazonaws.com",
        )
        self.assertEqual(values["FORGECognitoRegion"], "us-east-1")
        self.assertEqual(values["FORGECognitoClientId"], "iosclientid123")
        self.assertEqual(values["FORGECognitoUserPoolId"], "us-east-1_AbCdEf")
        self.assertEqual(values["FORGEEnvironment"], "prod")
        self.assertEqual(mod.validate(values), [])

    def test_live_generate_dry_run_from_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json", delete=False, encoding="utf-8") as handle:
            json.dump(_terraform_outputs(), handle)
            path = handle.name
        stdout = io.StringIO()
        try:
            with redirect_stdout(stdout):
                code = mod.main(["--from", path, "--environment", "prod", "--dry-run"])
        finally:
            os.unlink(path)
        self.assertEqual(code, 0)
        payload = json.loads(stdout.getvalue())
        self.assertEqual(payload["FORGEEnvironment"], "prod")
        self.assertTrue(payload["FORGEAPIBaseURL"].startswith("https://"))
        self.assertTrue(payload["FORGECognitoClientId"])

    def test_write_dummy_values_round_trip(self):
        original = PLIST.read_text(encoding="utf-8")
        updated = mod.write_plist_values(original, mod.DUMMY_OFFLINE_VALUES)
        self.assertEqual(mod.read_plist_values(updated), mod.DUMMY_OFFLINE_VALUES)
        values = mod.read_plist_values(updated)
        blob = " ".join(values.values())
        self.assertNotIn("127.0.0.1", blob)
        self.assertNotIn("localhost", blob)


class BedrockUntouchedTests(unittest.TestCase):
    def test_generator_does_not_enable_bedrock(self):
        source = SCRIPT.read_text(encoding="utf-8")
        self.assertIn("aria_bedrock_enabled", source)
        self.assertIn("stays false", source)
        self.assertNotRegex(source, r"aria_bedrock_enabled\s*=\s*true")


if __name__ == "__main__":
    unittest.main()
