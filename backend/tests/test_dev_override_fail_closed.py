"""Lambda must fail closed when FORGE_ALLOW_DEV_OVERRIDE is missing or unknown.

Terraform always sets the flag, but the code must not fall back to
``ENVIRONMENT in _DEV_LIKE`` (which includes the empty string) or
``FORGE_ALLOW_TEST_USER`` just because the process is a Lambda named
something other than prod.
"""

from __future__ import annotations

import base64
import json
import os
import unittest

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from security import allow_dev_override, demo_data_enabled  # noqa: E402
from storage import dynamodb as dynamodb_store  # noqa: E402


_ENV_KEYS = (
    "AWS_LAMBDA_FUNCTION_NAME",
    "ENVIRONMENT",
    "FORGE_ALLOW_DEV_OVERRIDE",
    "FORGE_ALLOW_TEST_USER",
    "FORGE_ALLOW_ANON_TEST_USER",
    "FORGE_TEST_USER_ID",
)

_LAMBDA_NAME = "forge-dev-api"
_TESTER_SUB = "test-user-00000000"


def _b64url(obj: dict) -> str:
    raw = json.dumps(obj, separators=(",", ":"), sort_keys=True).encode()
    return base64.urlsafe_b64encode(raw).decode().rstrip("=")


def _dev_override_token(sub: str = _TESTER_SUB) -> str:
    return (
        _b64url({"alg": "none", "typ": "JWT"})
        + "."
        + _b64url({"sub": sub})
        + "."
    )


def _dashboard_event(token: str) -> dict:
    return {
        "requestContext": {"http": {"method": "GET", "path": "/dashboard/today"}},
        "queryStringParameters": {},
        "headers": {"authorization": f"Bearer {token}"},
    }


class LambdaDevOverrideFailClosedTests(unittest.TestCase):
    """Token path through the real handler, plus security-level unit asserts."""

    def setUp(self):
        dynamodb_store.clear_local_store()
        self._saved = {key: os.environ.get(key) for key in _ENV_KEYS}
        for key in _ENV_KEYS:
            os.environ.pop(key, None)
        os.environ["AWS_LAMBDA_FUNCTION_NAME"] = _LAMBDA_NAME

    def tearDown(self):
        dynamodb_store.clear_local_store()
        for key, value in self._saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def _get_dashboard_with_override_token(self) -> dict:
        return handler(_dashboard_event(_dev_override_token()), None)

    def test_lambda_unset_environment_rejects_dev_override_token(self):
        os.environ.pop("ENVIRONMENT", None)
        os.environ.pop("FORGE_ALLOW_DEV_OVERRIDE", None)
        self.assertFalse(allow_dev_override())
        self.assertFalse(demo_data_enabled())
        response = self._get_dashboard_with_override_token()
        self.assertEqual(response["statusCode"], 401)

    def test_lambda_beta_rejects_dev_override_token(self):
        os.environ["ENVIRONMENT"] = "beta"
        os.environ.pop("FORGE_ALLOW_DEV_OVERRIDE", None)
        self.assertFalse(allow_dev_override())
        self.assertFalse(demo_data_enabled())
        response = self._get_dashboard_with_override_token()
        self.assertEqual(response["statusCode"], 401)

    def test_lambda_testflight_rejects_dev_override_token(self):
        os.environ["ENVIRONMENT"] = "testflight"
        os.environ.pop("FORGE_ALLOW_DEV_OVERRIDE", None)
        self.assertFalse(allow_dev_override())
        self.assertFalse(demo_data_enabled())
        response = self._get_dashboard_with_override_token()
        self.assertEqual(response["statusCode"], 401)

    def test_lambda_prd_rejects_dev_override_token(self):
        os.environ["ENVIRONMENT"] = "prd"
        os.environ.pop("FORGE_ALLOW_DEV_OVERRIDE", None)
        self.assertFalse(allow_dev_override())
        self.assertFalse(demo_data_enabled())
        response = self._get_dashboard_with_override_token()
        self.assertEqual(response["statusCode"], 401)

    def test_lambda_prod_rejects_dev_override_token_even_when_flag_true(self):
        os.environ["ENVIRONMENT"] = "prod"
        os.environ["FORGE_ALLOW_DEV_OVERRIDE"] = "true"
        response = self._get_dashboard_with_override_token()
        self.assertEqual(response["statusCode"], 401)

    def test_lambda_unrecognized_flag_rejects_dev_override_token(self):
        os.environ["ENVIRONMENT"] = "dev"
        os.environ["FORGE_ALLOW_DEV_OVERRIDE"] = "flase"
        response = self._get_dashboard_with_override_token()
        self.assertEqual(response["statusCode"], 401)

    def test_lambda_explicit_flag_true_accepts_dev_override_token(self):
        os.environ["ENVIRONMENT"] = "dev"
        os.environ["FORGE_ALLOW_DEV_OVERRIDE"] = "true"
        response = self._get_dashboard_with_override_token()
        self.assertEqual(response["statusCode"], 200)

    def test_lambda_test_user_flag_does_not_open_override_when_dev_flag_unset(self):
        os.environ["ENVIRONMENT"] = "beta"
        os.environ["FORGE_ALLOW_TEST_USER"] = "1"
        os.environ.pop("FORGE_ALLOW_DEV_OVERRIDE", None)
        response = self._get_dashboard_with_override_token()
        self.assertEqual(response["statusCode"], 401)


if __name__ == "__main__":
    unittest.main()
