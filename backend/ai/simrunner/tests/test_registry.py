import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402


class RegistryIntegrityTests(unittest.TestCase):
    def test_exactly_20_archetypes(self):
        self.assertEqual(len(reg.BEDROCK_MODEL_REGISTRY), 20)

    def test_four_per_tier(self):
        for tier in range(1, 6):
            self.assertEqual(len(reg.get_models_by_tier(tier)), 4, f"tier {tier}")

    def test_model_ids_unique(self):
        ids = reg.all_model_ids()
        self.assertEqual(len(set(ids)), len(ids))

    def test_sanitized_filenames_unique(self):
        safe = [reg._sanitize_id(i) for i in reg.all_model_ids()]
        self.assertEqual(len(set(safe)), len(safe), "report filenames would collide")

    def test_difficulty_tiers_valid(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            self.assertIn(model["difficulty_tier"], (1, 2, 3, 4, 5))

    def test_required_profile_keys_present(self):
        for model in reg.BEDROCK_MODEL_REGISTRY:
            missing = reg.REQUIRED_PROFILE_KEYS - set(model["behavioral_profile"])
            self.assertEqual(missing, set(), f"{model['model_id']} missing {missing}")

    def test_get_model_roundtrip(self):
        for mid in reg.all_model_ids():
            self.assertEqual(reg.get_model(mid)["model_id"], mid)

    def test_get_model_unknown_raises(self):
        with self.assertRaises(KeyError):
            reg.get_model("not-a-real-model")

    def test_validate_registry_passes_on_real_registry(self):
        reg.validate_registry()  # must not raise

    def test_validate_registry_catches_wrong_count(self):
        with self.assertRaises(ValueError):
            reg.validate_registry(reg.BEDROCK_MODEL_REGISTRY[:19])

    def test_validate_registry_catches_duplicate_id(self):
        bad = list(reg.BEDROCK_MODEL_REGISTRY)
        bad[1] = dict(bad[0])  # duplicate of model 0
        with self.assertRaises(ValueError):
            reg.validate_registry(bad)

    def test_validate_registry_catches_missing_profile_key(self):
        bad = [dict(m) for m in reg.BEDROCK_MODEL_REGISTRY]
        profile = dict(bad[0]["behavioral_profile"])
        profile.pop("chronotype")
        bad[0] = {**bad[0], "behavioral_profile": profile}
        with self.assertRaises(ValueError):
            reg.validate_registry(bad)

    def test_validate_registry_catches_bad_tier_distribution(self):
        bad = [dict(m) for m in reg.BEDROCK_MODEL_REGISTRY]
        bad[0] = {**bad[0], "difficulty_tier": 5}  # now 3 in tier 1, 5 in tier 5
        with self.assertRaises(ValueError):
            reg.validate_registry(bad)

    def test_validate_registry_catches_bad_tier_value(self):
        bad = [dict(m) for m in reg.BEDROCK_MODEL_REGISTRY]
        bad[0] = {**bad[0], "difficulty_tier": 0}
        with self.assertRaises(ValueError):
            reg.validate_registry(bad)


if __name__ == "__main__":
    unittest.main()
