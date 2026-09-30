"""Stdlib checks for the loadtest refuse-to-run gates. Not a load scenario."""

from __future__ import annotations

import unittest

try:
    from backend.loadtest.preflight import validate_run_env
except ImportError:  # pragma: no cover - script-style `cd backend/loadtest`
    from preflight import validate_run_env


class PreflightTests(unittest.TestCase):
    def test_accepts_loopback_and_false_flags(self):
        url = validate_run_env(
            {
                "BASE_URL": "http://127.0.0.1:3001/",
                "ARIA_BEDROCK_ENABLED": "false",
                "ARIA_VOICE_ENABLED": "false",
            }
        )
        self.assertEqual(url, "http://127.0.0.1:3001")

    def test_rejects_remote_base_url(self):
        with self.assertRaises(ValueError):
            validate_run_env(
                {
                    "BASE_URL": "https://example.execute-api.us-east-1.amazonaws.com",
                    "ARIA_BEDROCK_ENABLED": "false",
                    "ARIA_VOICE_ENABLED": "false",
                }
            )

    def test_rejects_missing_false_flags(self):
        with self.assertRaises(ValueError):
            validate_run_env({"BASE_URL": "http://localhost:3001"})

    def test_rejects_truthy_bedrock_flag(self):
        with self.assertRaises(ValueError):
            validate_run_env(
                {
                    "BASE_URL": "http://127.0.0.1:3001",
                    "ARIA_BEDROCK_ENABLED": "true",
                    "ARIA_VOICE_ENABLED": "false",
                }
            )


if __name__ == "__main__":
    unittest.main()
