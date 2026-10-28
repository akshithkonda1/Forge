from __future__ import annotations

import unittest

import _bootstrap  # noqa: F401

from aria_core.condition_safety import contains_banned, decide, training_line


class ConditionSafetyTests(unittest.TestCase):
    def test_empty_declaration_never_guesses(self):
        out = decide(
            [],
            sleep_hours=4.8,
            heat_risk=True,
            move_names=["Open Water Swim", "Rock Climbing"],
        )
        self.assertFalse(out["applied"])
        self.assertEqual(out["blockedMoves"], [])

    def test_epilepsy_blocks_swim_and_climb_without_naming(self):
        out = decide(
            ["epilepsy"],
            sleep_hours=5.2,
            heat_risk=True,
            move_names=["Open Water Swim", "Rock Climbing", "Goblet Squat"],
        )
        self.assertTrue(out["applied"])
        self.assertIn("Open Water Swim", out["blockedMoves"])
        self.assertIn("Rock Climbing", out["blockedMoves"])
        self.assertIn("Goblet Squat", out["keptMoves"])
        self.assertIn("sleepLoss", out["flags"])
        self.assertIn("heat", out["flags"])
        blob = out["changeNote"].lower()
        self.assertIn("safety rule", blob)
        self.assertFalse(contains_banned(out["changeNote"]))
        self.assertFalse(contains_banned(training_line(["epilepsy"])))
        self.assertIn("swimming", training_line(["epilepsy"]).lower())
        self.assertIn("climbing", training_line(["epilepsy"]).lower())
