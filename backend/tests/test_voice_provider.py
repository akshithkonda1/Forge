"""Voice mouth selection: Fish preferred, Polly then on-device, ElevenLabs off."""

from __future__ import annotations

import os
import unittest

import _bootstrap  # noqa: F401

from services import elevenlabs_voice  # noqa: E402
from services import fish_audio_voice  # noqa: E402
from services import polly_voice  # noqa: E402
from services import voice_provider  # noqa: E402


class VoiceProviderSelectionTests(unittest.TestCase):
    def test_registered_providers_and_default_chain(self):
        self.assertEqual(
            voice_provider.DEFAULT_CHAIN, ("fish", "polly", "on_device")
        )
        self.assertIn("elevenlabs", voice_provider.REGISTERED)
        self.assertNotIn("elevenlabs", voice_provider.DEFAULT_CHAIN)

    def test_dummy_and_offline_never_select_cloud(self):
        for kwargs in (
            {"dummy": True, "fish_enabled": True, "fish_configured": True},
            {"offline": True, "fish_enabled": True, "fish_configured": True},
        ):
            self.assertEqual(voice_provider.resolve_mouth(**kwargs), "on_device")

    def test_live_fish_when_enabled_and_configured(self):
        self.assertEqual(
            voice_provider.resolve_mouth(
                fish_enabled=True, fish_configured=True
            ),
            "fish",
        )

    def test_fish_error_timeout_busy_and_promo_fall_back_to_polly(self):
        for kwargs in (
            {"fish_failed": True},
            {"fish_timeout": True},
            {"fish_busy": True},
            {"fish_promo_expired": True},
        ):
            self.assertEqual(
                voice_provider.resolve_mouth(
                    fish_enabled=True,
                    fish_configured=True,
                    polly_enabled=True,
                    polly_configured=True,
                    **kwargs,
                ),
                "polly",
            )

    def test_quota_and_privacy_use_on_device_not_polly(self):
        self.assertEqual(
            voice_provider.resolve_mouth(
                privacy_ok=False,
                fish_enabled=True,
                fish_configured=True,
                polly_enabled=True,
                polly_configured=True,
            ),
            "on_device",
        )
        self.assertEqual(
            voice_provider.resolve_mouth(
                quota_ok=False,
                fish_enabled=True,
                fish_configured=True,
                polly_enabled=True,
                polly_configured=True,
            ),
            "on_device",
        )

    def test_polly_off_after_fish_failure_is_on_device(self):
        self.assertEqual(
            voice_provider.resolve_mouth(
                fish_enabled=True,
                fish_configured=True,
                fish_failed=True,
                polly_enabled=False,
            ),
            "on_device",
        )

    def test_elevenlabs_slot_stays_off_and_never_synthesizes(self):
        os.environ.pop("ARIA_ELEVENLABS_VOICE_ENABLED", None)
        self.assertFalse(elevenlabs_voice.voice_enabled())
        self.assertEqual(
            voice_provider.resolve_mouth(
                fish_enabled=True,
                fish_configured=True,
                elevenlabs_enabled=True,
                elevenlabs_configured=True,
            ),
            "fish",
        )
        from responses import RouteError

        with self.assertRaises(RouteError) as raised:
            elevenlabs_voice.synthesize("I'm ARIA.")
        self.assertEqual(raised.exception.code, "elevenlabs_disabled")

    def test_kill_switches_default_off(self):
        os.environ.pop("ARIA_FISH_VOICE_ENABLED", None)
        os.environ.pop("ARIA_POLLY_VOICE_FALLBACK", None)
        os.environ.pop("ARIA_ELEVENLABS_VOICE_ENABLED", None)
        self.assertFalse(fish_audio_voice.fish_voice_enabled())
        self.assertFalse(polly_voice.fallback_enabled())
        self.assertFalse(elevenlabs_voice.voice_enabled())


if __name__ == "__main__":
    unittest.main()
