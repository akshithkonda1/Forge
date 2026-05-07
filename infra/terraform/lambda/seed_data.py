from __future__ import annotations

from datetime import date, datetime, timezone
from typing import Any


def now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def today_iso() -> str:
    return date.today().isoformat()


def default_profile() -> dict[str, Any]:
    return {
        "name": "Akshith",
        "fitnessGoals": ["build-muscle"],
        "experienceLevel": "intermediate",
        "preferredWorkouts": ["strength", "hiit"],
        "coachingStyle": "push-hard",
        "connectedDevices": ["Apple Watch", "Oura Ring"],
        "weeklySchedule": [1, 3, 5],
    }


def default_connections() -> list[dict[str, Any]]:
    timestamp = now_iso()
    return [
        {
            "provider": "apple-health",
            "displayName": "Apple Health",
            "status": "connected",
            "lastSyncedAt": timestamp,
        },
        {
            "provider": "oura",
            "displayName": "Oura Ring",
            "status": "connected",
            "lastSyncedAt": timestamp,
        },
        {
            "provider": "whoop",
            "displayName": "WHOOP",
            "status": "needs-auth",
        },
        {
            "provider": "strava",
            "displayName": "Strava",
            "status": "needs-auth",
        },
    ]


def default_readiness() -> dict[str, Any]:
    return {
        "overall": 82,
        "sleepQuality": 88,
        "recoveryScore": 79,
        "stressLevel": 24,
        "energyBank": 76,
        "generatedAt": now_iso(),
    }


def default_daily_metrics() -> dict[str, Any]:
    return {
        "date": today_iso(),
        "steps": 3241,
        "activeCalories": 186,
        "hrv": 52,
        "restingHR": 58,
        "deepSleep": 102,
        "totalSleep": 432,
        "sources": ["apple-health", "oura"],
    }


def default_workout() -> dict[str, Any]:
    return {
        "id": "w1",
        "date": today_iso(),
        "name": "Upper Body Power",
        "type": "strength",
        "duration": 55,
        "intensity": "high",
        "generatedBy": "system",
        "exercises": [
            {
                "id": "e1",
                "name": "Barbell Bench Press",
                "sets": 4,
                "reps": "6-8",
                "weight": 185,
                "restSeconds": 120,
                "notes": "Focus on controlled eccentric",
            },
            {
                "id": "e2",
                "name": "Weighted Pull-Ups",
                "sets": 4,
                "reps": "6-8",
                "weight": 25,
                "restSeconds": 120,
            },
            {
                "id": "e3",
                "name": "Overhead Press",
                "sets": 3,
                "reps": "8-10",
                "weight": 115,
                "restSeconds": 90,
            },
            {
                "id": "e4",
                "name": "Barbell Rows",
                "sets": 3,
                "reps": "8-10",
                "weight": 155,
                "restSeconds": 90,
            },
            {
                "id": "e5",
                "name": "Incline Dumbbell Press",
                "sets": 3,
                "reps": "10-12",
                "weight": 65,
                "restSeconds": 60,
            },
            {
                "id": "e6",
                "name": "Face Pulls",
                "sets": 3,
                "reps": "15-20",
                "weight": 30,
                "restSeconds": 60,
            },
        ],
    }


def default_sleep() -> list[dict[str, Any]]:
    return [
        {
            "date": "2026-05-06",
            "totalHours": 7.2,
            "deepMinutes": 102,
            "remMinutes": 95,
            "lightMinutes": 215,
            "awakeMinutes": 20,
            "score": 88,
            "sources": ["oura", "apple-health"],
        },
        {
            "date": "2026-05-05",
            "totalHours": 6.8,
            "deepMinutes": 78,
            "remMinutes": 88,
            "lightMinutes": 225,
            "awakeMinutes": 17,
            "score": 74,
            "sources": ["oura"],
        },
        {
            "date": "2026-05-04",
            "totalHours": 7.5,
            "deepMinutes": 110,
            "remMinutes": 100,
            "lightMinutes": 220,
            "awakeMinutes": 20,
            "score": 91,
            "sources": ["oura", "apple-health"],
        },
        {
            "date": "2026-05-03",
            "totalHours": 6.2,
            "deepMinutes": 65,
            "remMinutes": 72,
            "lightMinutes": 210,
            "awakeMinutes": 25,
            "score": 62,
            "sources": ["apple-health"],
        },
        {
            "date": "2026-05-02",
            "totalHours": 7.8,
            "deepMinutes": 115,
            "remMinutes": 105,
            "lightMinutes": 228,
            "awakeMinutes": 20,
            "score": 93,
            "sources": ["oura"],
        },
        {
            "date": "2026-05-01",
            "totalHours": 7.0,
            "deepMinutes": 88,
            "remMinutes": 92,
            "lightMinutes": 218,
            "awakeMinutes": 22,
            "score": 80,
            "sources": ["oura", "apple-health"],
        },
        {
            "date": "2026-04-30",
            "totalHours": 6.5,
            "deepMinutes": 72,
            "remMinutes": 80,
            "lightMinutes": 208,
            "awakeMinutes": 30,
            "score": 68,
            "sources": ["apple-health"],
        },
        {
            "date": "2026-04-29",
            "totalHours": 7.4,
            "deepMinutes": 98,
            "remMinutes": 96,
            "lightMinutes": 222,
            "awakeMinutes": 18,
            "score": 85,
            "sources": ["oura"],
        },
        {
            "date": "2026-04-28",
            "totalHours": 6.9,
            "deepMinutes": 82,
            "remMinutes": 84,
            "lightMinutes": 216,
            "awakeMinutes": 32,
            "score": 70,
            "sources": ["apple-health"],
        },
        {
            "date": "2026-04-27",
            "totalHours": 7.6,
            "deepMinutes": 108,
            "remMinutes": 102,
            "lightMinutes": 224,
            "awakeMinutes": 22,
            "score": 90,
            "sources": ["oura", "apple-health"],
        },
        {
            "date": "2026-04-26",
            "totalHours": 5.8,
            "deepMinutes": 55,
            "remMinutes": 65,
            "lightMinutes": 195,
            "awakeMinutes": 33,
            "score": 55,
            "sources": ["apple-health"],
        },
        {
            "date": "2026-04-25",
            "totalHours": 7.1,
            "deepMinutes": 95,
            "remMinutes": 90,
            "lightMinutes": 218,
            "awakeMinutes": 23,
            "score": 82,
            "sources": ["oura"],
        },
        {
            "date": "2026-04-24",
            "totalHours": 7.3,
            "deepMinutes": 100,
            "remMinutes": 94,
            "lightMinutes": 220,
            "awakeMinutes": 24,
            "score": 84,
            "sources": ["oura", "apple-health"],
        },
        {
            "date": "2026-04-23",
            "totalHours": 6.6,
            "deepMinutes": 70,
            "remMinutes": 78,
            "lightMinutes": 212,
            "awakeMinutes": 36,
            "score": 65,
            "sources": ["apple-health"],
        },
    ]


def default_workout_history() -> list[dict[str, Any]]:
    return [
        {
            "id": "h1",
            "date": "2026-05-05",
            "name": "Lower Body Strength",
            "type": "strength",
            "duration": 62,
            "volume": 18500,
            "intensity": "high",
            "source": "manual",
        },
        {
            "id": "h2",
            "date": "2026-05-03",
            "name": "HIIT Conditioning",
            "type": "hiit",
            "duration": 30,
            "volume": 0,
            "intensity": "max",
            "source": "apple-health",
        },
        {
            "id": "h3",
            "date": "2026-05-02",
            "name": "Upper Body Hypertrophy",
            "type": "strength",
            "duration": 58,
            "volume": 22400,
            "intensity": "moderate",
            "source": "manual",
        },
        {
            "id": "h4",
            "date": "2026-04-30",
            "name": "Full Body Power",
            "type": "strength",
            "duration": 65,
            "volume": 24000,
            "intensity": "high",
            "source": "manual",
        },
        {
            "id": "h5",
            "date": "2026-04-28",
            "name": "Cardio + Core",
            "type": "cardio",
            "duration": 45,
            "volume": 0,
            "intensity": "moderate",
            "source": "apple-health",
        },
        {
            "id": "h6",
            "date": "2026-04-26",
            "name": "Push Day",
            "type": "strength",
            "duration": 52,
            "volume": 19800,
            "intensity": "high",
            "source": "manual",
        },
        {
            "id": "h7",
            "date": "2026-04-25",
            "name": "Pull Day",
            "type": "strength",
            "duration": 55,
            "volume": 21000,
            "intensity": "high",
            "source": "manual",
        },
        {
            "id": "h8",
            "date": "2026-04-23",
            "name": "Leg Day",
            "type": "strength",
            "duration": 60,
            "volume": 26500,
            "intensity": "high",
            "source": "manual",
        },
    ]


def default_personal_records() -> list[dict[str, Any]]:
    return [
        {"exercise": "Bench Press", "value": 225, "unit": "lbs", "date": "2026-04-23"},
        {"exercise": "Squat", "value": 315, "unit": "lbs", "date": "2026-04-26"},
        {"exercise": "Deadlift", "value": 365, "unit": "lbs", "date": "2026-04-10"},
        {"exercise": "Mile Run", "value": 6.45, "unit": "min", "date": "2026-04-30"},
        {"exercise": "Pull-Ups", "value": 18, "unit": "reps", "date": "2026-05-03"},
    ]


def default_chat_messages() -> list[dict[str, Any]]:
    workout = default_workout()
    return [
        {
            "id": "m1",
            "role": "trainer",
            "content": "Hey Akshith, welcome to Forge. I have synced your Apple Watch and Oura Ring data and I am already pulling your biometrics into today's plan.",
            "timestamp": "2026-05-04T14:00:00+00:00",
        },
        {
            "id": "m2",
            "role": "user",
            "content": "Excited to get started. I have been training for about 2 years but feel like I have plateaued.",
            "timestamp": "2026-05-04T14:01:00+00:00",
        },
        {
            "id": "m3",
            "role": "trainer",
            "content": "Plateaus are normal and breakable. Your consistency is strong, so the next lever is better periodization and recovery-aware progression.",
            "timestamp": "2026-05-04T14:02:00+00:00",
        },
        {
            "id": "m4",
            "role": "trainer",
            "content": "Morning Akshith. Deep sleep was solid last night and HRV is up from yesterday. You are primed for an upper body power session.",
            "timestamp": "2026-05-06T13:00:00+00:00",
            "richCard": {
                "type": "workout-plan",
                "data": workout,
            },
        },
    ]


def dashboard_payload() -> dict[str, Any]:
    return {
        "profile": default_profile(),
        "readiness": default_readiness(),
        "dailyMetrics": default_daily_metrics(),
        "todayWorkout": default_workout(),
        "recentSleep": default_sleep(),
        "recentWorkouts": default_workout_history(),
        "personalRecords": default_personal_records(),
        "connections": default_connections(),
    }
