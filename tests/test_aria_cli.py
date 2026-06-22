import contextlib
import io
import json
import sys
import unittest
from pathlib import Path

REPO_ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(REPO_ROOT / "backend"))

import aria_cli  # noqa: E402  (adds the Lambda dir to sys.path on import)
from services import aria_engine  # noqa: E402


CANONICAL_KEYS = {
    "schema_version", "response_type", "confidence", "confidence_reason",
    "prose_summary", "card", "restricted_domains", "message", "suggested_actions", "model",
}


def _body(profile: str) -> dict:
    return {"context": aria_cli.PROFILES[profile]["context"]}


def _respond(message, profile, *, voice=False, live=False, permissions=None):
    return aria_cli.respond(
        message, _body(profile),
        voice=voice, live=live,
        permissions=permissions or aria_engine.DataPermissions.allow_all(),
    )


class ProfileTests(unittest.TestCase):
    def test_every_profile_produces_a_valid_envelope(self):
        for name in aria_cli.PROFILES:
            env = _respond("should I train today?", name)
            self.assertTrue(CANONICAL_KEYS.issubset(env.keys()), msg=name)
            self.assertTrue(env["prose_summary"].strip(), msg=name)

    def test_depleted_user_is_coached_to_recover(self):
        env = _respond("should I train today?", "depleted")
        self.assertEqual(env["response_type"], "recommendation")
        self.assertTrue(any(ch.isdigit() for ch in env["message"]))

    def test_primed_user_is_cleared_to_push(self):
        env = _respond("should I train today?", "primed")
        self.assertEqual(env["response_type"], "recommendation")
        self.assertIn("primed", env["message"].lower())

    def test_sparse_user_is_asked_for_data(self):
        env = _respond("what should I do today?", "sparse")
        self.assertEqual(env["response_type"], "clarification")
        self.assertLess(env["confidence"], 0.5)


class ModeTests(unittest.TestCase):
    def test_voice_mode_suppresses_the_card(self):
        env = _respond("should I train?", "depleted", voice=True)
        self.assertIsNone(env["card"])
        self.assertEqual(env["message"], env["prose_summary"])

    def test_permissions_redact_and_report(self):
        perms = aria_engine.DataPermissions.from_payload({"deny": ["sleep"]})
        env = _respond("should I train today?", "depleted", permissions=perms)
        self.assertEqual(env["restricted_domains"], ["sleep"])
        # The user's specific sleep numbers must not leak (deep-sleep fraction is 12%).
        self.assertNotIn("12%", json.dumps(env))

    def test_live_without_aws_falls_back_to_deterministic(self):
        env = _respond("should I train today?", "mixed", live=True)
        self.assertEqual(env["reasoning_source"], "deterministic")


class RenderTests(unittest.TestCase):
    def test_render_includes_header_and_prose(self):
        env = _respond("how did I sleep?", "primed")
        out = aria_cli.render("how did I sleep?", env, label="Diego")
        self.assertIn("ARIA · Diego", out)
        self.assertIn(env["message"], out)


class CliEntrypointTests(unittest.TestCase):
    def _run(self, argv) -> str:
        buffer = io.StringIO()
        with contextlib.redirect_stdout(buffer):
            code = aria_cli.main(argv)
        self.assertEqual(code, 0)
        return buffer.getvalue()

    def test_json_output_is_a_valid_envelope(self):
        out = self._run(["-p", "primed", "-m", "how did I sleep?", "--json"])
        payload = json.loads(out)
        self.assertIn("response_type", payload)
        self.assertTrue(payload["prose_summary"].strip())

    def test_list_profiles_lists_the_sample_users(self):
        out = self._run(["--list-profiles"])
        for name in aria_cli.PROFILES:
            self.assertIn(name, out)


if __name__ == "__main__":
    unittest.main()
