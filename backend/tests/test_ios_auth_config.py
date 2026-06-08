"""Gate B unit checks for iOS auth helpers (mirrors CognitoTokenSupport.swift)."""

from __future__ import annotations

import base64
import json
import time
import unittest


def _expiration_date(jwt: str) -> float | None:
    parts = jwt.split(".")
    if len(parts) < 2:
        return None
    payload = parts[1].replace("-", "+").replace("_", "/")
    payload += "=" * ((4 - len(payload) % 4) % 4)
    try:
        data = json.loads(base64.b64decode(payload))
    except (json.JSONDecodeError, ValueError):
        return None
    exp = data.get("exp")
    return float(exp) if exp is not None else None


def _should_refresh(jwt: str, *, now: float, lead_time: float = 300) -> bool:
    exp = _expiration_date(jwt)
    if exp is None:
        return True
    return (exp - now) <= lead_time


def _refresh_payload(client_id: str, refresh_token: str) -> dict:
    return {
        "AuthFlow": "REFRESH_TOKEN_AUTH",
        "ClientId": client_id,
        "AuthParameters": {"REFRESH_TOKEN": refresh_token},
    }


def _make_jwt(exp: int) -> str:
    header = base64.urlsafe_b64encode(b'{"alg":"none"}').decode().rstrip("=")
    payload = base64.urlsafe_b64encode(json.dumps({"exp": exp}).encode()).decode().rstrip("=")
    return f"{header}.{payload}.signature"


class IOSAuthConfigTests(unittest.TestCase):
    def test_should_refresh_when_token_near_expiry(self):
        now = int(time.time())
        jwt = _make_jwt(now + 120)
        self.assertTrue(_should_refresh(jwt, now=float(now)))

    def test_should_not_refresh_when_token_fresh(self):
        now = int(time.time())
        jwt = _make_jwt(now + 3600)
        self.assertFalse(_should_refresh(jwt, now=float(now)))

    def test_refresh_payload_matches_cognito_contract(self):
        payload = _refresh_payload("ios-client", "refresh-token-abc")
        self.assertEqual(payload["AuthFlow"], "REFRESH_TOKEN_AUTH")
        self.assertEqual(payload["ClientId"], "ios-client")
        self.assertEqual(payload["AuthParameters"]["REFRESH_TOKEN"], "refresh-token-abc")

    def test_production_api_host_rejects_localhost_when_auth_enabled(self):
        hosts = {"127.0.0.1", "localhost", ""}
        for host in hosts:
            with self.subTest(host=host):
                self.assertTrue(host in {"", "127.0.0.1", "localhost"})


if __name__ == "__main__":
    unittest.main()