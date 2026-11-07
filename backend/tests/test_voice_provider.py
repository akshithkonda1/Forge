"""Voice mouth selection: Kokoro only. Cloud vendors are not registered."""

from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from services import voice_provider  # noqa: E402


class VoiceProviderSelectionTests(unittest.TestCase):
    def test_registered_mouth_is_kokoro_only(self):
        self.assertEqual(voice_provider.DEFAULT_CHAIN, ("kokoro",))
        self.assertEqual(voice_provider.REGISTERED, ("kokoro",))
        self.assertNotIn("fish", voice_provider.REGISTERED)
        self.assertNotIn("polly", voice_provider.REGISTERED)
        self.assertNotIn("elevenlabs", voice_provider.REGISTERED)

    def test_dummy_offline_quota_and_live_all_select_kokoro(self):
        cases = (
            {},
            {"dummy": True, "fish_enabled": True, "fish_configured": True},
            {"offline": True, "fish_enabled": True, "fish_configured": True},
            {"privacy_ok": False, "polly_enabled": True, "polly_configured": True},
            {"quota_ok": False},
            {"fish_enabled": True, "fish_configured": True},
            {
                "fish_failed": True,
                "polly_enabled": True,
                "polly_configured": True,
            },
            {
                "elevenlabs_enabled": True,
                "elevenlabs_configured": True,
            },
        )
        for kwargs in cases:
            self.assertEqual(voice_provider.resolve_mouth(**kwargs), "kokoro", kwargs)


if __name__ == "__main__":
    unittest.main()
