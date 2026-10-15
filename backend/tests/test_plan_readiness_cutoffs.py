"""Workout plan readiness cutoffs: Peak 100 / Solid 85 / Moderate 70.

The backend recommendation mirrors AriaPlanEngine on device
(peakFloor / solidFloor / moderateFloor); keep both in step.
"""
import unittest

import _bootstrap  # noqa: F401

from services import scoring  # noqa: E402


class PlanReadinessCutoffTests(unittest.TestCase):
    def _rec(self, readiness):
        return scoring.baseline_workout_recommendation(readiness, None)

    def test_band_boundaries(self):
        cases = [
            (100, "power", "high"),
            (99, "hypertrophy", "moderate"),
            (85, "hypertrophy", "moderate"),
            (84, "technique", "low"),
            (70, "technique", "low"),
            (69, "recovery", "low"),
            (0, "recovery", "low"),
        ]
        for readiness, focus, intensity in cases:
            with self.subTest(readiness=readiness):
                rec = self._rec(readiness)
                self.assertEqual(rec["focus"], focus)
                self.assertEqual(rec["intensity"], intensity)


if __name__ == "__main__":
    unittest.main()
