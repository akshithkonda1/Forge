import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SCRIPT = ROOT / "backend" / "organize_users.py"
sys.path.insert(0, str(ROOT / "backend"))

from organize_users import organize_users  # noqa: E402


USERS = [
    {
        "id": "u1",
        "email": "one@example.com",
        "profile": {
            "name": "One",
            "fitnessGoals": ["build-muscle", "improve-endurance"],
            "experienceLevel": "intermediate",
            "preferredWorkouts": ["strength", "hiit"],
            "coachingStyle": "push-hard",
            "connectedDevices": ["Apple Watch", "Oura Ring"],
            "weeklySchedule": [1, 3, 5],
        },
    },
    {
        "id": "u2",
        "profile": {
            "name": "Two",
            "fitnessGoals": ["lose-fat"],
            "experienceLevel": "beginner",
            "preferredWorkouts": ["cardio"],
            "coachingStyle": "patient",
            "connectedDevices": ["Garmin"],
            "weeklySchedule": [2, 4],
        },
    },
    {
        "id": "u3",
        "profile": {
            "name": "Three",
            "experienceLevel": "advanced",
            "preferredWorkouts": [],
            "coachingStyle": "data-driven",
        },
    },
]


class OrganizeUsersTests(unittest.TestCase):
    def test_groups_multi_value_fitness_goals(self):
        result = organize_users(USERS, "fitness-goal")

        self.assertEqual(result["groups"]["build-muscle"]["count"], 1)
        self.assertEqual(result["groups"]["improve-endurance"]["users"][0]["id"], "u1")
        self.assertEqual(result["groups"]["lose-fat"]["label"], "Lose Fat")
        self.assertEqual(result["uncategorized"]["count"], 1)

    def test_groups_weekly_schedule_with_day_labels(self):
        result = organize_users(USERS, "weekly-schedule")

        self.assertEqual(result["groups"]["1"]["label"], "Monday")
        self.assertEqual(result["groups"]["5"]["users"][0]["name"], "One")

    def test_all_categories_includes_ios_profile_dimensions(self):
        result = organize_users(USERS, "all")

        self.assertEqual(result["category"], "all")
        self.assertIn("coaching-style", result["categories"])
        self.assertIn("workout-type", result["categories"])

    def test_cli_reads_json_file(self):
        with tempfile.NamedTemporaryFile("w", suffix=".json") as handle:
            json.dump({"users": USERS}, handle)
            handle.flush()

            completed = subprocess.run(
                [sys.executable, str(SCRIPT), handle.name, "--category", "experience-level"],
                check=True,
                capture_output=True,
                text=True,
            )

        payload = json.loads(completed.stdout)
        self.assertEqual(payload["groups"]["beginner"]["users"][0]["id"], "u2")
        self.assertEqual(payload["groups"]["intermediate"]["users"][0]["email"], "one@example.com")


if __name__ == "__main__":
    unittest.main()
