"""Locks the invariants behind the hot-path perf work in aria_engine:

- signals are gathered only on paths that use them, but a clarification must
  still carry restricted_domains (the branch that was restructured);
- missing_fields (now built without an intermediate _groups dict) stays
  equivalent to a straight walk of _FIELD_MAP.

These are behavior locks, not timing assertions, so they are stable in CI.
"""
import unittest

import _bootstrap  # noqa: F401

from services import aria_engine as A  # noqa: E402


class HotPathInvariantTests(unittest.TestCase):
    def test_clarification_still_carries_restricted_domains(self):
        # Sparse context -> clarification. _gather_signals moved out of the
        # clarification branch; restricted_domains must still be stamped.
        ctx = A.ARIAContext.from_payload({"context": {"profile": {"primaryGoal": "lose-fat"}}})
        perms = A.DataPermissions.from_payload({"deny": ["sleep"]})
        resp = A.generate_response("hey", ctx, permissions=perms)
        self.assertEqual(resp["response_type"], "clarification")
        self.assertIn("sleep", resp["restricted_domains"])
        self.assertTrue(resp.get("prose_summary"))

    def test_non_clarification_paths_still_gather_signals(self):
        ctx = A.ARIAContext.from_payload({"context": {
            "sleep": {"durationMinutes": 300, "hrv": 44},
            "readiness": {"hrv7DayTrend": -12, "recoveryScore": 47}}})
        resp = A.generate_response("should I train hard today?", ctx)
        self.assertEqual(resp["response_type"], "recommendation")
        self.assertTrue(resp["prose_summary"])

    def test_missing_fields_matches_reference_walk(self):
        ctx = A.ARIAContext.from_payload({"context": {
            "sleep": {"durationMinutes": 400},  # duration present; other sleep fields None
            "profile": {"primaryGoal": "build-muscle"}}})
        expected = []
        for group, attrs in A._FIELD_MAP.items():
            obj = getattr(ctx, group)
            for attr in attrs:
                if getattr(obj, attr) is None:
                    expected.append(f"{group}.{attr}")
        self.assertEqual(ctx.missing_fields, expected)
        self.assertIn("sleep.hrv", ctx.missing_fields)
        self.assertNotIn("sleep.duration_minutes", ctx.missing_fields)


if __name__ == "__main__":
    unittest.main()
