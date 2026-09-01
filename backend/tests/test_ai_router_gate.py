"""The Bedrock kill-switch. POST /ai/router and the aria_cli --live path must not
reach Amazon Bedrock unless ARIA_BEDROCK_ENABLED is set — even on a deployed
Lambda with a valid JWT and IAM. Bedrock stays off by default.
"""
import json
import os
import sys
import types
import unittest

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from ai_router import BedrockGateway, RoutingError, bedrock_enabled  # noqa: E402
from services import aria_engine  # noqa: E402


def event(method, path, body=None, *, user_id="router-user"):
    payload = {
        "requestContext": {"http": {"method": method, "path": path}},
        "queryStringParameters": {},
        "headers": {},
    }
    if user_id:
        payload["requestContext"]["authorizer"] = {"jwt": {"claims": {"sub": user_id}}}
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def body(response):
    return json.loads(response["body"])


class _Flag:
    """Set/restore ARIA_BEDROCK_ENABLED around a block."""

    def __init__(self, value):
        self.value = value

    def __enter__(self):
        self._original = os.environ.get("ARIA_BEDROCK_ENABLED")
        if self.value is None:
            os.environ.pop("ARIA_BEDROCK_ENABLED", None)
        else:
            os.environ["ARIA_BEDROCK_ENABLED"] = self.value
        return self

    def __exit__(self, *exc):
        if self._original is None:
            os.environ.pop("ARIA_BEDROCK_ENABLED", None)
        else:
            os.environ["ARIA_BEDROCK_ENABLED"] = self._original


class RouterEndpointGateTests(unittest.TestCase):
    def test_router_endpoint_returns_503_when_flag_off(self):
        with _Flag("false"):
            self.assertFalse(bedrock_enabled())
            resp = handler(event("POST", "/ai/router", {"question": "summarize my data"}), None)
        self.assertEqual(resp["statusCode"], 503)
        self.assertIn("ARIA_BEDROCK_ENABLED", body(resp)["message"])

    def test_router_endpoint_missing_flag_is_treated_as_off(self):
        with _Flag(None):
            resp = handler(event("POST", "/ai/router", {"question": "hi"}), None)
        self.assertEqual(resp["statusCode"], 503)

    def test_router_endpoint_still_requires_auth(self):
        # Auth is checked before the flag; anonymous stays 401 regardless.
        with _Flag("true"):
            resp = handler(event("POST", "/ai/router", {"question": "hi"}, user_id=None), None)
        self.assertEqual(resp["statusCode"], 401)


class BedrockGatewayGateTests(unittest.TestCase):
    """The one place that actually calls Bedrock Converse enforces the flag."""

    def test_converse_blocked_when_flag_off(self):
        gateway = BedrockGateway(region_name="us-east-1")
        with _Flag("false"):
            with self.assertRaises(RoutingError) as ctx:
                gateway.converse(
                    model_id="anthropic.claude-sonnet-4-6",
                    system_prompt="s",
                    user_prompt="u",
                    max_tokens=100,
                    temperature=0.2,
                )
        self.assertEqual(ctx.exception.status_code, 503)

    def test_converse_reaches_bedrock_only_when_flag_on(self):
        # Inject a fake boto3 so no creds/network are needed. Proves the gate is
        # flag-controlled: Converse proceeds (and returns text) only when enabled.
        saved = {name: sys.modules.get(name) for name in ("boto3", "botocore", "botocore.config")}

        class _FakeClient:
            def converse(self, **kwargs):
                return {
                    "output": {"message": {"content": [{"text": "hello from bedrock"}]}},
                    "usage": {"inputTokens": 1, "outputTokens": 2},
                    "stopReason": "end_turn",
                }

        fake_boto3 = types.SimpleNamespace(client=lambda *a, **k: _FakeClient())
        botocore = types.ModuleType("botocore")
        botocore_config = types.ModuleType("botocore.config")
        botocore_config.Config = lambda **kwargs: kwargs
        botocore.config = botocore_config
        sys.modules["boto3"] = fake_boto3
        sys.modules["botocore"] = botocore
        sys.modules["botocore.config"] = botocore_config
        try:
            gateway = BedrockGateway(region_name="us-east-1")
            with _Flag("true"):
                out = gateway.converse(
                    model_id="anthropic.claude-sonnet-4-6",
                    system_prompt="s",
                    user_prompt="u",
                    max_tokens=100,
                    temperature=0.2,
                )
            self.assertEqual(out["answer"], "hello from bedrock")
        finally:
            for name, module in saved.items():
                if module is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = module


class AriaCliLivePathGateTests(unittest.TestCase):
    """aria_cli --live drives generate_response_live with converse=None. With the
    flag off it must stay deterministic and never call out to Bedrock."""

    def _ctx(self):
        return aria_engine.ARIAContext.from_payload(
            {"context": {"sleep": {"durationMinutes": 420, "hrv": 55},
                         "readiness": {"recoveryScore": 60}}}
        )

    def test_live_default_path_blocked_when_flag_off_never_calls_bedrock(self):
        original = aria_engine._default_converse
        calls = {"n": 0}

        def boom(*args, **kwargs):
            calls["n"] += 1
            raise AssertionError("must not reach Bedrock when the flag is off")

        aria_engine._default_converse = boom
        try:
            with _Flag("false"):
                resp = aria_engine.generate_response_live("should I train?", self._ctx(), converse=None)
        finally:
            aria_engine._default_converse = original
        self.assertEqual(calls["n"], 0)
        self.assertEqual(resp["reasoning_source"], "deterministic")

    def test_injected_converse_still_runs_when_flag_off(self):
        # Unit-testability preserved: an injected converse is always honored.
        def fake(model_id, system, user):
            return json.dumps({
                "schema_version": aria_engine.SCHEMA_VERSION,
                "response_type": "insight",
                "prose_summary": "live ok",
            })

        with _Flag("false"):
            resp = aria_engine.generate_response_live("how did I sleep?", self._ctx(), converse=fake)
        self.assertEqual(resp["reasoning_source"], "bedrock")

    def test_aria_cli_respond_live_falls_back_when_flag_off(self):
        from backend.ai import aria_cli

        original = aria_engine._default_converse

        def boom(*args, **kwargs):
            raise AssertionError("aria_cli --live must not reach Bedrock when the flag is off")

        aria_engine._default_converse = boom
        try:
            with _Flag("false"):
                envelope = aria_cli.respond(
                    "should I train today?",
                    {"context": aria_cli.PROFILES["depleted"]["context"]},
                    voice=False,
                    live=True,
                    permissions=aria_engine.DataPermissions.allow_all(),
                )
        finally:
            aria_engine._default_converse = original
        self.assertEqual(envelope.get("reasoning_source"), "deterministic")


if __name__ == "__main__":
    unittest.main()
