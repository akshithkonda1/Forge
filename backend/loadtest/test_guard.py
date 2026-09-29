"""Prove the loadtest guard increments and raises. Not a load scenario."""

from __future__ import annotations

import types
import unittest
import urllib.request

from backend.loadtest import guard


class GuardTests(unittest.TestCase):
    def setUp(self):
        guard._COUNTS.update({k: 0 for k in guard._COUNTS})
        guard._INSTALLED = False
        guard.install()

    def test_boto3_bedrock_client_increments(self):
        fake = types.SimpleNamespace(client=lambda *a, **k: object())
        guard._wrap_boto3(fake)
        with self.assertRaises(guard.LoadtestGuardError):
            fake.client("bedrock-runtime")
        self.assertEqual(guard.snapshot()["bedrock_client"], 1)

    def test_elevenlabs_urlopen_increments(self):
        with self.assertRaises(guard.LoadtestGuardError):
            urllib.request.urlopen("https://api.elevenlabs.io/v1/voices", timeout=1)
        self.assertEqual(guard.snapshot()["elevenlabs_http"], 1)

    def test_s3_client_is_not_counted_as_bedrock(self):
        seen = {}

        def client(name, *a, **k):
            seen["name"] = name
            return object()

        fake = types.SimpleNamespace(client=client)
        guard._wrap_boto3(fake)
        fake.client("s3")
        self.assertEqual(seen["name"], "s3")
        self.assertEqual(guard.snapshot()["bedrock_client"], 0)


if __name__ == "__main__":
    unittest.main()
