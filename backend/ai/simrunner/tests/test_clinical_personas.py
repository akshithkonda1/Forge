"""Clinical + structural-sparsity personas: registry integrity and stream shape.

Covers the three archetypes added for ARIA's mosaic thesis — the
metabolic-risk executive (lab-aware coaching without diagnosing), the
low-mood professional (sensitive mood+sleep+load fusion), and the
minimal-device tracker (structural sparsity, not new-user sparsity).
"""

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import (  # noqa: E402
    generate_stream,
)
from backend.ai.simrunner.backend_simulator.data_generator import (  # noqa: E402
    build_context,
)

METABOLIC_ID = "anthropic.claude-sonnet-4-6-metabolic"
LOWMOOD_ID = "amazon.nova-lite-v1-lowmood"
MINIMAL_ID = "cohere.command-r-plus-minimal"
NEW_IDS = {METABOLIC_ID, LOWMOOD_ID, MINIMAL_ID}


def _profile(model_id: str) -> dict:
    return reg.get_model(model_id)["behavioral_profile"]


class ClinicalPersonaRegistryTests(unittest.TestCase):
    def test_new_archetypes_present_with_tiers(self):
        self.assertEqual(reg.get_model(METABOLIC_ID)["difficulty_tier"], 3)
        self.assertEqual(reg.get_model(LOWMOOD_ID)["difficulty_tier"], 3)
        self.assertEqual(reg.get_model(MINIMAL_ID)["difficulty_tier"], 4)

    def test_registry_counts_updated(self):
        self.assertEqual(reg.TOTAL_ARCHETYPES, 26)
        self.assertEqual(len(reg.get_models_by_tier(3)), 7)
        self.assertEqual(len(reg.get_models_by_tier(4)), 6)

    def test_validate_registry_passes(self):
        reg.validate_registry()  # must not raise

    def test_new_pattern_keys_absent_from_existing_archetypes(self):
        # The load-bearing RNG invariant: metabolic_risk / anxious_nights
        # branches short-circuit on the pattern, so no pre-existing
        # archetype may set them — their streams stay byte-for-byte identical.
        for model in reg.BEDROCK_MODEL_REGISTRY:
            if model["model_id"] in NEW_IDS:
                continue
            self.assertNotIn(
                model["behavioral_profile"].get("notable_pattern"),
                {"metabolic_risk", "anxious_nights"},
                model["model_id"],
            )

    def test_streams_are_seed_deterministic(self):
        for mid in NEW_IDS:
            profile = _profile(mid)
            a = generate_stream(profile, seed=42)
            b = generate_stream(profile, seed=42)
            self.assertEqual(
                [(r.total_sleep_hours, r.hrv, r.notes) for r in a],
                [(r.total_sleep_hours, r.hrv, r.notes) for r in b],
                mid,
            )


class MetabolicRiskTests(unittest.TestCase):
    def test_lab_note_stamped_on_schedule(self):
        stream = generate_stream(_profile(METABOLIC_ID), seed=42)
        notes = [r.notes for r in stream if r.notes]
        ldl_notes = [n for n in notes if "LDL 168" in n]
        self.assertEqual(len(ldl_notes), 2, notes)

    def test_lab_note_reaches_context(self):
        # The note is ARIA's only view of the lab value — it must survive
        # the stream -> context mapping via notable_event_note.
        profile = _profile(METABOLIC_ID)
        stream = generate_stream(profile, seed=42)
        ldl_days = [i for i, r in enumerate(stream) if r.notes and "LDL 168" in r.notes]
        self.assertTrue(ldl_days)
        ctx = build_context(stream, profile, day_index=ldl_days[0])
        self.assertTrue(ctx.has_notable_event)
        self.assertIn("LDL 168", ctx.notable_event_note)

    def test_low_hrv_sedentary_shape(self):
        stream = generate_stream(_profile(METABOLIC_ID), seed=42)
        hrvs = [r.hrv for r in stream if r.hrv is not None]
        self.assertLess(sum(hrvs) / len(hrvs), 45)
        workouts = sum(1 for r in stream if r.workout_logged)
        self.assertLessEqual(workouts, 8)


class LowMoodTests(unittest.TestCase):
    def test_racing_mind_nights_present(self):
        stream = generate_stream(_profile(LOWMOOD_ID), seed=42)
        notes = [r.notes for r in stream if r.notes]
        self.assertTrue(
            any("racing mind" in n for n in notes),
            f"no anxious-night note in {notes}",
        )

    def test_sleep_degraded_relative_to_athlete(self):
        lowmood = generate_stream(_profile(LOWMOOD_ID), seed=42)
        athlete = generate_stream(
            _profile("anthropic.claude-sonnet-4-6"), seed=42
        )
        lowmood_avg = sum(r.total_sleep_hours for r in lowmood) / len(lowmood)
        athlete_avg = sum(r.total_sleep_hours for r in athlete) / len(athlete)
        self.assertLess(lowmood_avg, athlete_avg - 0.75)


class MinimalDeviceTests(unittest.TestCase):
    def test_structural_sparsity_in_stream(self):
        stream = generate_stream(_profile(MINIMAL_ID), seed=42)
        missing_hrv = sum(1 for r in stream if r.hrv is None)
        missing_sleep = sum(1 for r in stream if r.total_sleep_hours is None)
        # completeness=0.30 -> ~70% of days missing each field, independent rolls
        self.assertGreater(missing_hrv, 10, "HRV too complete for a phoneless user")
        self.assertGreater(missing_sleep, 10, "sleep too complete for a phoneless user")
        # ...but steps always survive: the phone accelerometer never leaves.
        self.assertTrue(all(r.steps and r.steps > 0 for r in stream))

    def test_context_reports_what_is_missing(self):
        profile = _profile(MINIMAL_ID)
        stream = generate_stream(profile, seed=7)
        sparse_days = [i for i, r in enumerate(stream) if r.hrv is None]
        self.assertTrue(sparse_days)
        ctx = build_context(stream, profile, day_index=sparse_days[0])
        self.assertFalse(ctx.has_hrv)
        self.assertIn("today.hrv", ctx.missing_fields)


if __name__ == "__main__":
    unittest.main()
