#!/usr/bin/env python3
from __future__ import annotations

import argparse
import json
import sys
from collections import defaultdict
from typing import Any, Iterable


CATEGORY_FIELDS = {
    "fitness-goal": "fitnessGoals",
    "experience-level": "experienceLevel",
    "workout-type": "preferredWorkouts",
    "coaching-style": "coachingStyle",
    "connected-device": "connectedDevices",
    "weekly-schedule": "weeklySchedule",
}

CATEGORY_LABELS = {
    "fitness-goal": {
        "build-muscle": "Build Muscle",
        "lose-fat": "Lose Fat",
        "improve-endurance": "Improve Endurance",
        "general-fitness": "General Fitness",
        "athletic-performance": "Athletic Performance",
    },
    "experience-level": {
        "beginner": "Beginner",
        "intermediate": "Intermediate",
        "advanced": "Advanced",
        "elite": "Elite",
    },
    "workout-type": {
        "strength": "Strength",
        "cardio": "Cardio",
        "hiit": "HIIT",
        "yoga": "Yoga",
        "mobility": "Mobility",
        "sport-specific": "Sport Specific",
    },
    "coaching-style": {
        "push-hard": "Push Me Hard",
        "balanced": "Keep It Balanced",
        "patient": "Be Patient With Me",
        "data-driven": "Data-Driven & Precise",
    },
    "weekly-schedule": {
        "0": "Sunday",
        "1": "Monday",
        "2": "Tuesday",
        "3": "Wednesday",
        "4": "Thursday",
        "5": "Friday",
        "6": "Saturday",
    },
}


def load_users(path: str | None) -> list[dict[str, Any]]:
    if path and path != "-":
        with open(path, "r", encoding="utf-8") as handle:
            payload = json.load(handle)
    else:
        payload = json.load(sys.stdin)

    if isinstance(payload, list):
        users = payload
    elif isinstance(payload, dict) and isinstance(payload.get("users"), list):
        users = payload["users"]
    else:
        raise ValueError("Input must be a JSON array of users or an object with a 'users' array.")

    invalid_indexes = [index for index, user in enumerate(users) if not isinstance(user, dict)]
    if invalid_indexes:
        raise ValueError(f"Every user must be an object. Invalid indexes: {invalid_indexes}")

    return users


def organize_users(users: list[dict[str, Any]], category: str) -> dict[str, Any]:
    if category == "all":
        return {
            "category": "all",
            "categories": {
                name: organize_users(users, name)
                for name in CATEGORY_FIELDS
            },
        }

    if category not in CATEGORY_FIELDS:
        valid = ", ".join(["all", *CATEGORY_FIELDS.keys()])
        raise ValueError(f"Unsupported category '{category}'. Expected one of: {valid}.")

    field_name = CATEGORY_FIELDS[category]
    grouped: dict[str, list[dict[str, Any]]] = defaultdict(list)
    uncategorized: list[dict[str, Any]] = []

    for user in users:
        profile = user.get("profile") if isinstance(user.get("profile"), dict) else user
        values = list(category_values(profile.get(field_name)))
        user_summary = summarize_user(user)

        if not values:
            uncategorized.append(user_summary)
            continue

        for value in values:
            grouped[value].append(user_summary)

    return {
        "category": category,
        "sourceField": field_name,
        "totalUsers": len(users),
        "groups": {
            key: {
                "label": label_for(category, key),
                "count": len(grouped[key]),
                "users": grouped[key],
            }
            for key in sorted(grouped)
        },
        "uncategorized": {
            "count": len(uncategorized),
            "users": uncategorized,
        },
    }


def category_values(value: Any) -> Iterable[str]:
    if value is None or value == "":
        return []
    if isinstance(value, list):
        return [normalize_value(item) for item in value if item is not None and item != ""]
    return [normalize_value(value)]


def normalize_value(value: Any) -> str:
    return str(value).strip()


def label_for(category: str, key: str) -> str:
    labels = CATEGORY_LABELS.get(category, {})
    return labels.get(key, key)


def summarize_user(user: dict[str, Any]) -> dict[str, Any]:
    profile = user.get("profile") if isinstance(user.get("profile"), dict) else user
    user_id = user.get("id") or user.get("userId") or user.get("sub") or profile.get("id") or profile.get("userId")
    name = profile.get("name") or user.get("name")

    summary: dict[str, Any] = {}
    if user_id:
        summary["id"] = str(user_id)
    if name:
        summary["name"] = str(name)
    if "email" in user:
        summary["email"] = str(user["email"])
    return summary or {"user": user}


def parse_args(argv: list[str]) -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Organize Forge users by the profile categories used in the iOS onboarding app.",
    )
    parser.add_argument(
        "input",
        nargs="?",
        default="-",
        help="Path to a JSON file, or '-' / omitted to read JSON from stdin.",
    )
    parser.add_argument(
        "--category",
        choices=["all", *CATEGORY_FIELDS.keys()],
        default="all",
        help="Frontend category to group by. Defaults to all categories.",
    )
    parser.add_argument(
        "--pretty",
        action="store_true",
        help="Pretty-print JSON output.",
    )
    return parser.parse_args(argv)


def main(argv: list[str] | None = None) -> int:
    args = parse_args(argv or sys.argv[1:])
    try:
        users = load_users(args.input)
        organized = organize_users(users, args.category)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        print(f"organize_users: {exc}", file=sys.stderr)
        return 1

    indent = 2 if args.pretty else None
    print(json.dumps(organized, indent=indent, sort_keys=True))
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
