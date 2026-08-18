import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.backend_simulator import bedrock_catalog as cat  # noqa: E402
from backend.ai.simrunner.backend_simulator import model_registry as reg  # noqa: E402
from backend.ai.simrunner.backend_simulator.behavior_engine import generate_stream  # noqa: E402


class CatalogIntegrityTests(unittest.TestCase):
    def test_catalog_non_empty_and_validates(self):
        self.assertGreater(len(cat.BEDROCK_CATALOG), 30)
        cat.validate_catalog()  # must not raise

    def test_model_ids_unique(self):
        ids = [m.model_id for m in cat.BEDROCK_CATALOG]
        self.assertEqual(len(set(ids)), len(ids))

    def test_major_providers_present(self):
        provs = set(cat.providers())
        for p in ("anthropic", "amazon", "meta", "mistral", "cohere", "ai21", "deepseek"):
            self.assertIn(p, provs)

    def test_classes_and_display_names_valid(self):
        valid = {"frontier", "reasoning", "balanced", "fast", "image", "video", "embedding"}
        for m in cat.BEDROCK_CATALOG:
            self.assertIn(m.model_class, valid, m.model_id)
            self.assertTrue(m.display_name.strip())

    def test_lookups(self):
        m = cat.BEDROCK_CATALOG[0]
        self.assertTrue(cat.is_bedrock_model(m.model_id))
        self.assertFalse(cat.is_bedrock_model("not.a-model"))
        self.assertEqual(cat.get_bedrock_model(m.model_id).model_id, m.model_id)
        with self.assertRaises(KeyError):
            cat.get_bedrock_model("not.a-model")

    def test_sanitized_filenames_unique(self):
        import re
        safe = [re.sub(r"[./:-]", "_", m.model_id) for m in cat.BEDROCK_CATALOG]
        self.assertEqual(len(set(safe)), len(safe))

    def test_validate_catalog_catches_duplicates(self):
        dupe = cat.BEDROCK_CATALOG + [cat.BEDROCK_CATALOG[0]]
        with self.assertRaises(ValueError):
            cat.validate_catalog(dupe)


class DerivedPersonaTests(unittest.TestCase):
    def test_derive_is_deterministic(self):
        m = cat.get_bedrock_model("meta.llama3-1-70b-instruct-v1:0")
        self.assertEqual(cat.derive_archetype(m), cat.derive_archetype(m))

    def test_every_derived_persona_is_valid_and_runnable(self):
        for m in cat.BEDROCK_CATALOG:
            arch = cat.derive_archetype(m)
            self.assertEqual(reg.REQUIRED_PROFILE_KEYS - set(arch["behavioral_profile"]), set(), m.model_id)
            self.assertIn(arch["difficulty_tier"], (1, 2, 3, 4, 5))
            self.assertTrue(arch.get("derived"))
            self.assertEqual(len(generate_stream(arch["behavioral_profile"])), 30)  # runs end to end


class ResolveArchetypeTests(unittest.TestCase):
    def test_named_archetype_wins(self):
        arch = reg.resolve_archetype("anthropic.claude-sonnet-4-6")
        self.assertFalse(arch.get("derived"))
        self.assertEqual(arch["display_name"], "Claude Sonnet 4.6 — The Compliant Athlete")

    def test_catalog_id_derives_persona(self):
        arch = reg.resolve_archetype("amazon.nova-pro-v1:0")
        self.assertTrue(arch.get("derived"))
        self.assertEqual(arch["model_id"], "amazon.nova-pro-v1:0")

    def test_unknown_raises(self):
        with self.assertRaises(KeyError):
            reg.resolve_archetype("totally.made-up-model")


class LiveFetchTests(unittest.TestCase):
    def test_default_is_static(self):
        self.assertEqual(len(cat.load_catalog()), len(cat.BEDROCK_CATALOG))

    def test_live_falls_back_to_static_without_boto3_or_creds(self):
        # No boto3 / no creds / no network → must return the static catalog, never raise.
        catalog = cat.load_catalog(live=True)
        static_ids = {m.model_id for m in cat.BEDROCK_CATALOG}
        self.assertGreaterEqual(len(catalog), len(cat.BEDROCK_CATALOG))
        self.assertTrue(static_ids.issubset({m.model_id for m in catalog}))


if __name__ == "__main__":
    unittest.main()
