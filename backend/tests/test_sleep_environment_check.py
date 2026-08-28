"""The sleep environment-check route — a real vision read of a room photo.

`routes/form_check.py` deliberately answers `available: false` for every
photo because whether Bedrock's Converse image content blocks worked was
unverified. This route is the first to actually send the image through:
`BedrockGateway.converse` now accepts an `image_bytes` block, and
`aria_engine.generate_coach_vision` is the vision sibling of
`generate_coach_text`. These tests cover the same ground `test_form_check.py`
covers for the text path — auth, size/shape validation, and that a live call
carries the security law and the actual image bytes — plus the base64
decoding this route does that form_check's stub never needed to.
"""

import base64
import json
import os
import unittest

import _bootstrap  # noqa: F401

from handler import handler  # noqa: E402
from services import aria_engine  # noqa: E402


def event(method, path, body=None, *, user_id=None):
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


def body_of(response):
    return json.loads(response["body"])


TINY_JPEG_BASE64 = base64.b64encode(b"\xff\xd8\xff\xdb\x00fake-jpeg-bytes").decode("ascii")


class SleepEnvironmentCheckAuthTests(unittest.TestCase):

    _GUARDED = ("ENVIRONMENT", "FORGE_ALLOW_ANON_TEST_USER")

    def setUp(self):
        self._saved = {k: os.environ.get(k) for k in self._GUARDED}

    def tearDown(self):
        for key, value in self._saved.items():
            if value is None:
                os.environ.pop(key, None)
            else:
                os.environ[key] = value

    def test_production_refuses_an_unauthenticated_check(self):
        os.environ["ENVIRONMENT"] = "production"
        os.environ.pop("FORGE_ALLOW_ANON_TEST_USER", None)
        resp = handler(
            event("POST", "/sleep/environment-check", {"image_base64": TINY_JPEG_BASE64}),
            None,
        )
        self.assertEqual(resp["statusCode"], 401)

    def test_a_spoofed_body_user_id_cannot_override_the_token(self):
        resp = handler(
            event("POST", "/sleep/environment-check",
                  {"image_base64": TINY_JPEG_BASE64, "user_id": "someone-else"}, user_id="u1"),
            None,
        )
        self.assertEqual(resp["statusCode"], 403)


class SleepEnvironmentCheckValidationTests(unittest.TestCase):

    def test_a_missing_image_is_a_400(self):
        resp = handler(event("POST", "/sleep/environment-check", {}, user_id="u1"), None)
        self.assertEqual(resp["statusCode"], 400)

    def test_an_oversized_frame_is_refused_before_anything_decodes_it(self):
        huge = "A" * 400_001
        resp = handler(
            event("POST", "/sleep/environment-check", {"image_base64": huge}, user_id="u1"), None
        )
        self.assertEqual(resp["statusCode"], 413)

    def test_malformed_base64_is_a_400_not_a_500(self):
        resp = handler(
            event("POST", "/sleep/environment-check", {"image_base64": "not-base64!!"}, user_id="u1"),
            None,
        )
        self.assertEqual(resp["statusCode"], 400)


class SleepEnvironmentCheckLiveTests(unittest.TestCase):

    def test_a_live_call_carries_the_security_law_and_the_actual_image_bytes(self):
        captured = {}

        def fake_converse_vision(model_id, system, user, image_bytes, image_format):
            captured["system"] = system
            captured["user"] = user
            captured["image_bytes"] = image_bytes
            captured["image_format"] = image_format
            return "The lamp by the bed is the brightest thing in frame — a warmer bulb would help."

        original = aria_engine._default_converse_vision
        original_enabled = aria_engine.bedrock_enabled
        aria_engine._default_converse_vision = fake_converse_vision
        aria_engine.bedrock_enabled = lambda: True
        try:
            resp = handler(
                event("POST", "/sleep/environment-check",
                      {"image_base64": TINY_JPEG_BASE64}, user_id="u1"),
                None,
            )
        finally:
            aria_engine._default_converse_vision = original
            aria_engine.bedrock_enabled = original_enabled

        self.assertEqual(resp["statusCode"], 200)
        payload = body_of(resp)
        self.assertTrue(payload["available"])
        self.assertIn("lamp", payload["assessment"])
        self.assertIn("SECURITY LAW (mandatory)", captured["system"])
        self.assertIn("You are ARIA", captured["system"])
        self.assertEqual(captured["image_bytes"], base64.b64decode(TINY_JPEG_BASE64))
        self.assertEqual(captured["image_format"], "jpeg")

    def test_without_live_reasoning_it_degrades_rather_than_failing(self):
        resp = handler(
            event("POST", "/sleep/environment-check",
                  {"image_base64": TINY_JPEG_BASE64}, user_id="u1"),
            None,
        )
        self.assertEqual(resp["statusCode"], 200)
        payload = body_of(resp)
        self.assertFalse(payload["available"])
        self.assertEqual(payload["reason"], "live_reasoning_disabled")


if __name__ == "__main__":
    unittest.main()
