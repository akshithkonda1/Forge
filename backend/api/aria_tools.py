"""ARIA tool definitions and implementations.

These are the tools ARIA can call during conversations to fetch real user data
and take actions. Each tool has:
  - A JSON schema definition (passed to the Anthropic API)
  - An implementation function that queries DynamoDB / services

Tool handler entry point: handle_tool_call(user_id, tool_name, tool_input)
"""
from __future__ import annotations

import uuid
from datetime import datetime, timezone
from typing import Any

import json

from routes import lifestyle as lifestyle_routes
from seed_data import (
    default_connections,
    default_daily_metrics,
    default_personal_records,
    default_profile,
    default_readiness,
    default_sleep,
    default_workout,
    default_workout_history,
    today_iso,
)
from services import readiness as readiness_svc, scoring
from storage import dynamodb, keys


# ---------------------------------------------------------------------------
# Tool schema definitions (passed to Claude's API as the `tools` parameter)
# ---------------------------------------------------------------------------

ARIA_TOOLS: list[dict[str, Any]] = [
    {
        "name": "get_user_profile",
        "description": (
            "Get the user's profile including their fitness goals, experience level, "
            "preferred workout types, coaching style preference, and connected devices. "
            "Call this first when personalizing advice."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_health_snapshot",
        "description": (
            "Get the user's health snapshot for today: readiness score breakdown, "
            "HRV, resting heart rate, steps, active calories, and total sleep. "
            "Use this before any training recommendation."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_sleep_analysis",
        "description": (
            "Get detailed sleep records for the last N nights (deep, REM, light, "
            "awake minutes and score per night). Use when the user asks about sleep "
            "quality, recovery, or why their readiness is low."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "days": {
                    "type": "integer",
                    "description": "Number of nights to retrieve (1-14). Defaults to 7.",
                    "minimum": 1,
                    "maximum": 14,
                }
            },
            "required": [],
        },
    },
    {
        "name": "get_workout_history",
        "description": (
            "Get recent workout history, training load trend, and recovery trend. "
            "Use when planning upcoming sessions or assessing fatigue accumulation."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "days": {
                    "type": "integer",
                    "description": "Number of days of history to retrieve (1-30). Defaults to 14.",
                    "minimum": 1,
                    "maximum": 30,
                }
            },
            "required": [],
        },
    },
    {
        "name": "get_personal_records",
        "description": (
            "Get the user's all-time personal records across exercises. "
            "Use when discussing progress, setting goals, or designing strength programs."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_todays_plan",
        "description": (
            "Get the workout plan generated for today, including exercises, sets, reps, "
            "weights, and rest periods. Use when discussing today's training session."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_integration_status",
        "description": (
            "Get the status of all connected health integrations (Apple Health, Oura, "
            "WHOOP, Strava, etc.) including last sync time and connection status."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "compute_readiness_score",
        "description": (
            "Compute a fresh readiness score from the user's recent sleep data. "
            "Returns overall readiness plus component scores (sleep quality, recovery, "
            "stress level, energy bank). Use when you need an up-to-date readiness value."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_training_load",
        "description": (
            "Compute current vs previous 7-day training load and trend (rising, steady, "
            "falling, flat). Use to assess fatigue accumulation and deload needs."
        ),
        "input_schema": {
            "type": "object",
            "properties": {},
            "required": [],
        },
    },
    {
        "name": "get_lifestyle_dashboard",
        "description": (
            "Get the user's lifestyle dashboard for today: quality-of-life metrics, "
            "nutrition totals (calories, protein, carbs, fat, water), logged meals, "
            "wellbeing habits, habit streak, and rule-based recommendations. "
            "Use for nutrition coaching, habit tracking, and holistic lifestyle advice."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "date": {
                    "type": "string",
                    "description": "ISO date (YYYY-MM-DD). Defaults to today.",
                }
            },
            "required": [],
        },
    },
    {
        "name": "get_nutrition_daily",
        "description": (
            "Get today's nutrition log: macro totals, water intake, targets, and meals. "
            "Use when discussing protein gaps, hydration, or meal planning."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "date": {
                    "type": "string",
                    "description": "ISO date (YYYY-MM-DD). Defaults to today.",
                }
            },
            "required": [],
        },
    },
    {
        "name": "get_wellbeing_habits",
        "description": (
            "Get today's wellbeing habits and completion state plus the current streak. "
            "Use for mindfulness, recovery rituals, and daily habit coaching."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "date": {
                    "type": "string",
                    "description": "ISO date (YYYY-MM-DD). Defaults to today.",
                }
            },
            "required": [],
        },
    },
    {
        "name": "log_coaching_insight",
        "description": (
            "Persist an important coaching insight about the user for future reference. "
            "Use when you identify a significant pattern, breakthrough, or risk that "
            "should be remembered across sessions."
        ),
        "input_schema": {
            "type": "object",
            "properties": {
                "type": {
                    "type": "string",
                    "enum": ["sleep", "training", "recovery", "nutrition", "mindset", "general"],
                    "description": "Category of the insight.",
                },
                "priority": {
                    "type": "string",
                    "enum": ["high", "medium", "low"],
                    "description": "Urgency or importance of the insight.",
                },
                "title": {
                    "type": "string",
                    "description": "Brief title (max 10 words).",
                },
                "observation": {
                    "type": "string",
                    "description": "What the data shows.",
                },
                "recommendation": {
                    "type": "string",
                    "description": "The specific action recommended.",
                },
            },
            "required": ["type", "priority", "title", "observation", "recommendation"],
        },
    },
]


# ---------------------------------------------------------------------------
# Tool implementations
# ---------------------------------------------------------------------------

def _strip_keys(item: dict[str, Any]) -> dict[str, Any]:
    return {k: v for k, v in item.items() if k not in ("pk", "sk")}


def _tool_get_user_profile(user_id: str, _input: dict[str, Any]) -> dict[str, Any]:
    item = dynamodb.get_item(**keys.profile_key(user_id))
    profile = _strip_keys(item) if item else default_profile()
    connections = _get_connections(user_id)
    return {"profile": profile, "connections": connections}


def _tool_get_health_snapshot(user_id: str, _input: dict[str, Any]) -> dict[str, Any]:
    readiness_item = dynamodb.get_item(**keys.readiness_key(user_id, today_iso()))
    if readiness_item:
        readiness_data = _strip_keys(readiness_item)
    else:
        sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=3)
        recent_sleep = [_strip_keys(i) for i in sleep_items] if sleep_items else default_sleep()[:3]
        readiness_data = readiness_svc.compute_readiness(recent_sleep)

    return {
        "today": today_iso(),
        "readiness": readiness_data,
        "dailyMetrics": default_daily_metrics(),
    }


def _tool_get_sleep_analysis(user_id: str, tool_input: dict[str, Any]) -> dict[str, Any]:
    days = max(1, min(14, int(tool_input.get("days", 7))))
    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=days)
    sleep_records = [_strip_keys(i) for i in sleep_items] if sleep_items else default_sleep()[:days]
    recovery = scoring.recovery_trend(sleep_records)

    avg_score = 0.0
    avg_deep = 0.0
    avg_total = 0.0
    if sleep_records:
        avg_score = sum(r.get("score", 0) for r in sleep_records) / len(sleep_records)
        avg_deep = sum(r.get("deepMinutes", 0) for r in sleep_records) / len(sleep_records)
        avg_total = sum(r.get("totalHours", 0) for r in sleep_records) / len(sleep_records)

    return {
        "nights": sleep_records,
        "periodDays": days,
        "averages": {
            "score": round(avg_score, 1),
            "deepMinutes": round(avg_deep, 1),
            "totalHours": round(avg_total, 2),
        },
        "recoveryTrend": recovery,
    }


def _tool_get_workout_history(user_id: str, tool_input: dict[str, Any]) -> dict[str, Any]:
    days = max(1, min(30, int(tool_input.get("days", 14))))
    limit = days + 2  # small buffer
    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=limit)
    workouts = [_strip_keys(i) for i in workout_items] if workout_items else default_workout_history()
    workouts = workouts[:days]

    training_load = scoring.training_load_trend(workouts)
    prs = scoring.detect_personal_records(workouts)

    return {
        "workouts": workouts,
        "periodDays": days,
        "trainingLoad": training_load,
        "personalRecordsFromPeriod": prs[:5],
    }


def _tool_get_personal_records(user_id: str, _input: dict[str, Any]) -> dict[str, Any]:
    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=60)
    workouts = [_strip_keys(i) for i in workout_items] if workout_items else []
    computed_prs = scoring.detect_personal_records(workouts)
    seed_prs = default_personal_records()

    # Merge: computed PRs take priority for exercises they cover
    pr_map = {pr["exercise"]: pr for pr in seed_prs}
    for pr in computed_prs:
        pr_map[pr["exercise"]] = pr

    return {"personalRecords": sorted(pr_map.values(), key=lambda x: x["exercise"])}


def _tool_get_todays_plan(user_id: str, _input: dict[str, Any]) -> dict[str, Any]:
    plan_item = dynamodb.get_item(**keys.workout_plan_key(user_id, today_iso()))
    plan = _strip_keys(plan_item) if plan_item else default_workout()
    return {"todayPlan": plan}


def _tool_get_integration_status(user_id: str, _input: dict[str, Any]) -> dict[str, Any]:
    connections = _get_connections(user_id)
    return {"connections": connections}


def _tool_compute_readiness_score(user_id: str, _input: dict[str, Any]) -> dict[str, Any]:
    sleep_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "SLEEP#", limit=7)
    recent_sleep = [_strip_keys(i) for i in sleep_items] if sleep_items else default_sleep()[:7]
    score = readiness_svc.compute_readiness(recent_sleep)
    return {"readiness": score, "basedOnNights": len(recent_sleep)}


def _tool_get_training_load(user_id: str, _input: dict[str, Any]) -> dict[str, Any]:
    workout_items = dynamodb.query_prefix_desc(keys.user_pk(user_id), "WORKOUT#", limit=14)
    workouts = [_strip_keys(i) for i in workout_items] if workout_items else default_workout_history()
    load = scoring.training_load_trend(workouts)
    return {"trainingLoad": load}


def _lifestyle_payload(handler_fn, user_id: str, tool_input: dict[str, Any]) -> dict[str, Any]:
    date = tool_input.get("date")
    event: dict[str, Any] = {"queryStringParameters": {"date": date} if date else {}}
    response = handler_fn(user_id, event)
    body = json.loads(response.get("body", "{}"))
    if response.get("statusCode", 500) >= 400:
        raise ValueError(body.get("message", "Lifestyle data unavailable."))
    return body


def _tool_get_lifestyle_dashboard(user_id: str, tool_input: dict[str, Any]) -> dict[str, Any]:
    return _lifestyle_payload(lifestyle_routes.handle_get_lifestyle_dashboard, user_id, tool_input)


def _tool_get_nutrition_daily(user_id: str, tool_input: dict[str, Any]) -> dict[str, Any]:
    return _lifestyle_payload(lifestyle_routes.handle_get_nutrition_daily, user_id, tool_input)


def _tool_get_wellbeing_habits(user_id: str, tool_input: dict[str, Any]) -> dict[str, Any]:
    return _lifestyle_payload(lifestyle_routes.handle_get_wellbeing_habits, user_id, tool_input)


def _tool_log_coaching_insight(user_id: str, tool_input: dict[str, Any]) -> dict[str, Any]:
    now = datetime.now(timezone.utc).isoformat()
    insight_id = uuid.uuid4().hex[:12]
    item = {
        **keys.aria_insight_key(user_id, today_iso(), insight_id),
        "insightId": insight_id,
        "type": str(tool_input.get("type", "general")),
        "priority": str(tool_input.get("priority", "medium")),
        "title": str(tool_input.get("title", "")),
        "observation": str(tool_input.get("observation", "")),
        "recommendation": str(tool_input.get("recommendation", "")),
        "createdAt": now,
        "date": today_iso(),
    }
    dynamodb.put_item(item)
    return {"saved": True, "insightId": insight_id, "createdAt": now}


# ---------------------------------------------------------------------------
# Dispatch
# ---------------------------------------------------------------------------

_TOOL_HANDLERS: dict[str, Any] = {
    "get_user_profile": _tool_get_user_profile,
    "get_health_snapshot": _tool_get_health_snapshot,
    "get_sleep_analysis": _tool_get_sleep_analysis,
    "get_workout_history": _tool_get_workout_history,
    "get_personal_records": _tool_get_personal_records,
    "get_todays_plan": _tool_get_todays_plan,
    "get_integration_status": _tool_get_integration_status,
    "compute_readiness_score": _tool_compute_readiness_score,
    "get_training_load": _tool_get_training_load,
    "get_lifestyle_dashboard": _tool_get_lifestyle_dashboard,
    "get_nutrition_daily": _tool_get_nutrition_daily,
    "get_wellbeing_habits": _tool_get_wellbeing_habits,
    "log_coaching_insight": _tool_log_coaching_insight,
}


def handle_tool_call(user_id: str, tool_name: str, tool_input: dict[str, Any]) -> Any:
    """Dispatch a tool call from ARIA to the appropriate implementation."""
    fn = _TOOL_HANDLERS.get(tool_name)
    if fn is None:
        raise ValueError(f"Unknown tool: '{tool_name}'")
    return fn(user_id, tool_input)


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _get_connections(user_id: str) -> list[dict[str, Any]]:
    providers = ["apple-health", "oura", "whoop", "garmin", "strava"]
    connections = []
    for provider in providers:
        item = dynamodb.get_item(**keys.connection_key(user_id, provider))
        if item:
            connections.append(_strip_keys(item))

    if not connections:
        connections = default_connections()

    return connections
