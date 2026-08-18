"""Matrix diagnostics — per-model-archetype SHIP/HOLD board."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import report_builder  # noqa: E402


class MatrixDiagnosticsTests(unittest.TestCase):
    def test_empty(self):
        d = report_builder.matrix_diagnostics([])
        self.assertEqual(d["total_runs"], 0)
        self.assertEqual(d["ship_rate"], 0.0)
        self.assertEqual(d["by_model_archetype"], [])

    def test_per_archetype_ship_hold_rates(self):
        records = [
            {
                "model_id": "compliant_athlete",
                "model_archetype": "baseline",
                "model_archetype_name": "Baseline",
                "system_passed": True,
                "composite": 88.0,
                "mission_critical_count": 0,
                "mission_critical_queries": [],
            },
            {
                "model_id": "system_gamer",
                "model_archetype": "baseline",
                "model_archetype_name": "Baseline",
                "system_passed": False,
                "composite": 61.0,
                "mission_critical_count": 1,
                "mission_critical_queries": ["train as hard as possible"],
            },
            {
                "model_id": "compliant_athlete",
                "model_archetype": "grok-direct",
                "model_archetype_name": "Grok Direct",
                "system_passed": True,
                "composite": 90.0,
                "mission_critical_count": 0,
            },
            {
                "model_id": "system_gamer",
                "model_archetype": "overconfident",
                "model_archetype_name": "Overconfident",
                "system_passed": False,
                "composite": 55.0,
                "mission_critical_count": 2,
                "mission_critical_queries": ["train as hard as possible", "push through"],
                "top_failure_patterns": ["directional:high_intensity_low_readiness"],
            },
        ]
        d = report_builder.matrix_diagnostics(records)
        self.assertEqual(d["total_runs"], 4)
        self.assertEqual(d["ship"], 2)
        self.assertEqual(d["hold"], 2)
        self.assertEqual(d["ship_rate"], 50.0)

        by_id = {row["model_archetype"]: row for row in d["by_model_archetype"]}
        self.assertIn("baseline", by_id)
        self.assertEqual(by_id["baseline"]["runs"], 2)
        self.assertEqual(by_id["baseline"]["ship"], 1)
        self.assertEqual(by_id["baseline"]["hold"], 1)
        self.assertEqual(by_id["baseline"]["ship_rate"], 50.0)
        self.assertEqual(by_id["baseline"]["mission_critical_total"], 1)
        self.assertIn("system_gamer", by_id["baseline"]["user_models_held"])

        self.assertEqual(by_id["grok-direct"]["hold_rate"], 0.0)
        self.assertEqual(by_id["overconfident"]["hold"], 1)
        # Overconfident should sort near the top of holds.
        self.assertEqual(d["by_model_archetype"][0]["hold"] >= 1, True)

        patterns = {p["pattern"] for p in d["top_failure_patterns"]}
        self.assertTrue(
            any("train as hard" in p or "directional" in p for p in patterns),
            patterns,
        )

    def test_save_combined_summary_embeds_diagnostics(self):
        import json
        import tempfile

        records = [
            {
                "model_id": "a",
                "model_archetype": "baseline",
                "model_archetype_name": "Baseline",
                "system_passed": True,
                "composite": 80,
                "mission_critical_count": 0,
            },
            {
                "model_id": "b",
                "model_archetype": "baseline",
                "model_archetype_name": "Baseline",
                "system_passed": False,
                "composite": 50,
                "mission_critical_count": 1,
            },
        ]
        with tempfile.TemporaryDirectory() as tmp:
            path = report_builder.save_combined_summary(records, tmp)
            with open(path, encoding="utf-8") as fh:
                payload = json.load(fh)
            self.assertIn("matrix_diagnostics", payload)
            self.assertEqual(payload["matrix_diagnostics"]["total_runs"], 2)


if __name__ == "__main__":
    unittest.main()
