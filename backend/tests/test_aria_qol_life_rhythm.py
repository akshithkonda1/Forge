"""ARIA can reflect the holistic Quality of Life score back as *life rhythm* —
a lifestyle signal, never a diagnosis, never fabricated, and redacted with the
rest of the lifestyle domain when the user denies it.
"""
import unittest

import _bootstrap  # noqa: F401

from services import aria_engine  # noqa: E402
from services import aria_evidence  # noqa: E402
from services import scoring  # noqa: E402


def _ctx(lifestyle: dict):
    return aria_engine.ARIAContext.from_payload({"context": {"lifestyle": lifestyle}})


class LifeRhythmBandTests(unittest.TestCase):
    def test_band_thresholds_mirror_the_client(self):
        self.assertEqual(aria_engine.life_rhythm_band(85), "thriving")
        self.assertEqual(aria_engine.life_rhythm_band(84), "steady")
        self.assertEqual(aria_engine.life_rhythm_band(70), "steady")
        self.assertEqual(aria_engine.life_rhythm_band(69), "strained")
        self.assertEqual(aria_engine.life_rhythm_band(50), "strained")
        self.assertEqual(aria_engine.life_rhythm_band(49), "depleted")

    def test_descriptor_is_supportive_not_clinical(self):
        text = aria_engine.life_rhythm_descriptor(40)
        self.assertIn("recovery-first", text)
        self.assertNotIn("diagnos", text.lower())


class QoLContextTests(unittest.TestCase):
    def test_qol_tag_parsed_and_surfaced_as_life_rhythm(self):
        ctx = _ctx({"tags": ["habit:sleep_variance:sleep:85", "qol:72"]})
        self.assertEqual(ctx.lifestyle.quality_of_life_score, 72)
        block = ctx.user_model_block()
        self.assertIn("life_rhythm: steady (72/100)", block)
        # Framed as lifestyle, explicitly not medical.
        self.assertIn("never a medical or diagnostic claim", block)

    def test_explicit_score_and_confidence_fields_parsed(self):
        ctx = _ctx({"qualityOfLifeScore": 91, "qualityOfLifeConfidence": 0.8})
        self.assertEqual(ctx.lifestyle.quality_of_life_score, 91)
        block = ctx.user_model_block()
        self.assertIn("life_rhythm: thriving (91/100, confidence 0.80)", block)

    def test_absent_qol_is_never_fabricated(self):
        ctx = _ctx({"tags": ["habit:sleep_variance:sleep:85"]})
        self.assertIsNone(ctx.lifestyle.quality_of_life_score)
        self.assertNotIn("life_rhythm", ctx.user_model_block())

    def test_score_is_clamped(self):
        self.assertEqual(_ctx({"tags": ["qol:250"]}).lifestyle.quality_of_life_score, 100)
        self.assertEqual(_ctx({"tags": ["qol:-5"]}).lifestyle.quality_of_life_score, 0)

    def test_life_rhythm_redacted_when_lifestyle_denied(self):
        ctx = _ctx({"tags": ["qol:40"]})
        perms = aria_engine.DataPermissions.from_payload({"deny": ["lifestyle"]})
        sanitized, restricted = aria_engine.apply_permissions(ctx, perms)
        self.assertIn("lifestyle", restricted)
        self.assertIsNone(sanitized.lifestyle.quality_of_life_score)
        self.assertNotIn("life_rhythm", sanitized.user_model_block(restricted))

    def test_restricted_lifestyle_suppresses_qol_even_on_unsanitized_context(self):
        # Defense-in-depth: a caller may pass the raw context plus the restricted
        # list (not the redacted copy). A denied domain must never reach the prompt.
        ctx = _ctx({"tags": ["qol:40"]})
        self.assertEqual(ctx.lifestyle.quality_of_life_score, 40)  # still present on the object
        block = ctx.user_model_block(restricted=["lifestyle"])
        self.assertNotIn("life_rhythm", block)
        self.assertNotIn("qol:", block)

    def test_life_rhythm_reaches_the_live_prompt(self):
        ctx = _ctx({"tags": ["qol:58"]})
        prompt = aria_engine.build_user_prompt("how am I doing overall?", ctx)
        self.assertIn("life_rhythm: strained (58/100)", prompt)

    def test_elaboration_tags_and_bag_parsed(self):
        ctx = _ctx(
            {
                "tags": [
                    "qol:48",
                    "qol:band:depleted",
                    "qol:driver:Sleep",
                    "qol:missing:Connection",
                    "qol:pillar:mind:40",
                    "qol:pillar:sleep:35",
                ],
                "qualityOfLifeCoaching": "Sleep and Mind are pulling the grade.",
            }
        )
        self.assertEqual(ctx.lifestyle.quality_of_life_band, "depleted")
        self.assertIn("Sleep", ctx.lifestyle.quality_of_life_drivers)
        self.assertIn("Connection", ctx.lifestyle.quality_of_life_missing)
        self.assertEqual(ctx.lifestyle.quality_of_life_pillars.get("mind"), 40)
        self.assertEqual(ctx.lifestyle.quality_of_life_coaching, "Sleep and Mind are pulling the grade.")
        block = ctx.user_model_block()
        self.assertIn("drivers: Sleep", block)
        self.assertIn("missing: Connection", block)
        self.assertIn("coaching: Sleep and Mind are pulling the grade.", block)
        self.assertIn("life_rhythm_training", block)

    def test_training_plan_mirrors_client_policy(self):
        depleted = aria_engine.life_rhythm_training_plan(42, band="depleted")
        self.assertTrue(depleted["keep_light"])
        self.assertEqual(depleted["max_duration"], 30)
        steady = aria_engine.life_rhythm_training_plan(78, band="steady")
        self.assertIsNone(steady)

    def test_scoring_clamps_high_intensity_when_qol_depleted(self):
        result = scoring.baseline_workout_recommendation(
            90,
            "strength",
            quality_of_life_score=40,
            quality_of_life_band="depleted",
        )
        self.assertEqual(result["intensity"], "low")
        self.assertEqual(result["focus"], "recovery")
        self.assertIn("lifeRhythm", result)

    def test_evidence_blocks_intensity_for_depleted_life_rhythm(self):
        ctx = _ctx({"tags": ["qol:40", "qol:band:depleted", "qol:driver:Sleep"]})
        pattern = aria_evidence.detect_pattern(ctx, signals=[], restricted=[])
        plan = aria_engine.life_rhythm_training_plan(
            ctx.lifestyle.quality_of_life_score,
            band=ctx.lifestyle.quality_of_life_band,
            pillars=ctx.lifestyle.quality_of_life_pillars,
        )
        self.assertIsNotNone(plan)
        self.assertEqual(pattern.stance, "protect")
        self.assertTrue(pattern.blocks_intensity)


if __name__ == "__main__":
    unittest.main()
