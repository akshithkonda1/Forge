from __future__ import annotations

from typing import Any

DEFAULT_MACRO_TARGETS: dict[str, float] = {
    "calories": 2600,
    "protein": 180,
    "carbs": 280,
    "fat": 80,
    "waterMl": 1900,
}


def default_habits() -> list[dict[str, Any]]:
    return [
        {"id": "morning-sunlight", "name": "Morning sunlight (10 min)", "completed": False},
        {"id": "meditation", "name": "Meditation (5 min)", "completed": False},
        {"id": "reading", "name": "Read (20 min)", "completed": False},
        {"id": "mobility", "name": "Mobility work (10 min)", "completed": False},
        {"id": "cold-shower", "name": "Cold shower", "completed": False},
        {"id": "journaling", "name": "Journaling", "completed": False},
    ]


def default_restaurants() -> list[dict[str, Any]]:
    return [
        {
            "id": "raising-canes",
            "name": "Raising Cane's",
            "logo": "🍗",
            "category": "Chicken",
            "items": [
                {"id": "box-combo", "name": "Box Combo (4 tenders)", "calories": 1220, "protein": 56, "carbs": 120, "fat": 55, "serving": "1 combo", "isHealthy": False},
                {"id": "chicken-finger", "name": "Chicken Finger (1 piece)", "calories": 130, "protein": 10, "carbs": 8, "fat": 6, "serving": "1 tender", "isHealthy": True},
            ],
        },
        {
            "id": "mcdonalds",
            "name": "McDonald's",
            "logo": "🍔",
            "category": "Burgers",
            "items": [
                {"id": "egg-mcmuffin", "name": "Egg McMuffin", "calories": 310, "protein": 17, "carbs": 30, "fat": 13, "serving": "1 sandwich", "isHealthy": True},
                {"id": "grilled-chicken", "name": "Grilled Chicken Sandwich", "calories": 380, "protein": 37, "carbs": 44, "fat": 7, "serving": "1 sandwich", "isHealthy": True},
            ],
        },
        {
            "id": "chick-fil-a",
            "name": "Chick-fil-A",
            "logo": "🐔",
            "category": "Chicken",
            "items": [
                {"id": "grilled-nuggets", "name": "Grilled Nuggets (8-count)", "calories": 130, "protein": 25, "carbs": 1, "fat": 3, "serving": "8 pieces", "isHealthy": True},
                {"id": "cobb-salad", "name": "Cobb Salad (Grilled)", "calories": 390, "protein": 40, "carbs": 28, "fat": 14, "serving": "1 salad", "isHealthy": True},
            ],
        },
        {
            "id": "chipotle",
            "name": "Chipotle",
            "logo": "🌯",
            "category": "Mexican",
            "items": [
                {"id": "chicken-bowl", "name": "Chicken Bowl (no rice)", "calories": 320, "protein": 42, "carbs": 21, "fat": 8, "serving": "1 bowl", "isHealthy": True},
                {"id": "veggie-bowl", "name": "Veggie Bowl", "calories": 430, "protein": 16, "carbs": 68, "fat": 12, "serving": "1 bowl", "isHealthy": True},
            ],
        },
        {
            "id": "subway",
            "name": "Subway",
            "logo": "🥖",
            "category": "Healthy",
            "items": [
                {"id": "turkey-breast", "name": '6" Turkey Breast', "calories": 280, "protein": 18, "carbs": 46, "fat": 4, "serving": "6 inch", "isHealthy": True},
            ],
        },
        {
            "id": "panera",
            "name": "Panera Bread",
            "logo": "🥗",
            "category": "Healthy",
            "items": [
                {"id": "cobb-salad", "name": "Green Goddess Cobb Salad", "calories": 550, "protein": 42, "carbs": 23, "fat": 33, "serving": "1 salad", "isHealthy": True},
            ],
        },
        {
            "id": "taco-bell",
            "name": "Taco Bell",
            "logo": "🌮",
            "category": "Mexican",
            "items": [
                {"id": "power-bowl", "name": "Chicken Power Bowl", "calories": 470, "protein": 26, "carbs": 50, "fat": 19, "serving": "1 bowl", "isHealthy": True},
            ],
        },
        {
            "id": "wendys",
            "name": "Wendy's",
            "logo": "🍔",
            "category": "Burgers",
            "items": [
                {"id": "grilled-sandwich", "name": "Grilled Chicken Sandwich", "calories": 350, "protein": 35, "carbs": 37, "fat": 8, "serving": "1 sandwich", "isHealthy": True},
            ],
        },
    ]