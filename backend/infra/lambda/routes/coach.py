from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Callable

from ai_router import AIRouter, RouteRequest, RoutingError
from responses import RouteError, ok
from seed_data import today_iso
from services import coach_context, scoring
from storage import dynamodb, keys


# AI router invocation is wrapped so tests can monkeypatch it without booting Bedrock.
_router_invoker: Callable[[dict[str, Any]], dict[str, Any]] | None = None


def set_router_invoker(invoker: Callable[[dict[str, Any]], dict[str, Any]] | None) -> None:
    """Test seam: override how coach routes call the AI router."""
    global _router_invoker
    _router_invoker = invoker


def _invoke_router(payload: dict[str, Any]) -> dict[str, Any]:
    if _router_invoker is not None:
        return _router_invoker(payload)
    request = RouteRequest.from_payload(payload)
    return AIRouter().route(request)


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _safe_route(payload: dict[str, Any], fallback: str) -> dict[str, Any]:
    """Invoke the router; on routing/runtime failure return a deterministic fallback."""
    try:
        result = _invoke_router(payload)
        answer = result.get("finalAnswer") or result.get("answer") or fallback
        return {"answer": answer, "router": result}
    except RoutingError as exc:
        return {"answer": fallback, "error": exc.message, "fallback": True}
    except Exception as exc:  # noqa: BLE001 - any runtime issue (e.g. boto3 missing) falls back
        return {"answer": fallback, "error": str(exc), "fallback": True}


def handle_post_coach_message(user_id: str, body: dict) -> dict:
    content = str(body.get("content") or "").strip()
    if not content:
        raise RouteError(400, "Request body must include non-empty 'content'.")

    context = coach_context.gather_user_context(user_id)
    payload = {
        "question": content,
        "context": coach_context.context_to_prompt_block(context),
    }
    overall = coach_context.readiness_overall(context)
    last_sleep = (context["recentSleep"] or [{}])[0].get("score")
    if overall is None:
        fallback = (
            "I do not have readiness or sleep data for you yet, so I cannot tell you "
            "how hard to train today. Sync a sleep source or log a night and ask me again."
        )
    else:
        sleep_clause = (
            f" Your last sleep score was {last_sleep}." if last_sleep is not None else ""
        )
        fallback = (
            f"Readiness is {overall}/100.{sleep_clause} Train within your current "
            "readiness band and avoid stacking high-intensity days."
        )
    routed = _safe_route(payload, fallback)
    return ok({
        "id": f"coach-{int(datetime.now(timezone.utc).timestamp() * 1000)}",
        "role": "trainer",
        "content": routed["answer"],
        "timestamp": _now_iso(),
        "fallback": routed.get("fallback", False),
    })


def handle_post_coach_workout_plan(user_id: str, _body: dict) -> dict:
    context = coach_context.gather_user_context(user_id)
    last_workout_type = (context.get("recentWorkouts") or [{}])[0].get("type")
    baseline = scoring.baseline_workout_recommendation(
        coach_context.readiness_overall(context), last_workout_type
    )

    payload = {
        "question": (
            "Generate a single-day workout plan tailored to today's readiness and the user's "
            "recent training pattern. Return a short paragraph plus 4-6 exercises."
        ),
        "context": coach_context.context_to_prompt_block(context),
    }
    today_plan = context.get("todayPlan")
    plan_clause = (
        f" Use today's plan ('{today_plan['name']}') as the template and reduce volume "
        "by 10% if energy bank drops below 60."
        if isinstance(today_plan, dict) and today_plan.get("name")
        else " Nothing is scheduled for today yet, so treat this as the starting point."
    )
    fallback = (
        f"Suggested focus: {baseline['focus']} ({baseline['suggestedType']}, "
        f"{baseline['intensity']} intensity).{plan_clause}"
    )
    routed = _safe_route(payload, fallback)

    # `PLAN#{date}` is read in 4 places (this file, routes/workouts.py,
    # routes/dashboard.py) but was never written anywhere — GET /workouts/today
    # always returned nothing for a real account. Persist a minimal record here,
    # using the user's own last *logged* duration rather than inventing one
    # (WorkoutPlan.duration is non-optional on the client, and the AI router
    # only returns prose, no structured duration).
    last_duration = (context.get("recentWorkouts") or [{}])[0].get("duration")
    if isinstance(last_duration, (int, float)) and not isinstance(last_duration, bool):
        day = today_iso()
        generated_plan = {
            "id": f"plan-{int(datetime.now(timezone.utc).timestamp() * 1000)}",
            "date": day,
            "name": f"{baseline['focus'].title()} Focus",
            "type": baseline["suggestedType"],
            "duration": last_duration,
            "intensity": baseline["intensity"],
            "generatedBy": "ai",
            "exercises": [],
            "notes": routed["answer"],
        }
        dynamodb.put_item({**keys.workout_plan_key(user_id, day), **generated_plan})
        today_plan = generated_plan

    return ok({
        "baseline": baseline,
        "todayPlan": today_plan,
        "explanation": routed["answer"],
        "fallback": routed.get("fallback", False),
    })


def handle_post_coach_sleep_insight(user_id: str, _body: dict) -> dict:
    context = coach_context.gather_user_context(user_id)
    payload = {
        "question": (
            "Analyze the user's last 7 nights of sleep and surface the single most useful "
            "behavioral change they should make this week."
        ),
        "context": coach_context.context_to_prompt_block(context),
    }
    recovery = context["recoveryTrend"]
    if not context.get("recentSleep"):
        fallback = (
            "You have no sleep logged yet, so there is no trend to analyze. Connect a "
            "sleep source and I will have something to work with in a few nights."
        )
    else:
        direction = (
            "improving" if recovery["delta"] > 0
            else "declining" if recovery["delta"] < 0
            else "steady"
        )
        fallback = (
            f"Sleep trend is {direction} (avg {recovery['current']} vs prior "
            f"{recovery['previous']}). Protect a consistent wind-down window to lift "
            "deep-sleep minutes."
        )
    routed = _safe_route(payload, fallback)
    return ok({
        "recoveryTrend": recovery,
        "insight": routed["answer"],
        "fallback": routed.get("fallback", False),
    })


def handle_post_coach_progress_review(user_id: str, _body: dict) -> dict:
    context = coach_context.gather_user_context(user_id)
    payload = {
        "question": (
            "Summarize the user's progress over the last 30 days. Highlight one win, one risk, "
            "and one recommendation for the next block."
        ),
        "context": coach_context.context_to_prompt_block(context),
    }
    load = context["trainingLoad"]
    if not context.get("recentWorkouts"):
        fallback = (
            "You have no logged sessions yet, so there is no progress to review. Log a "
            "few workouts and I will summarize the block."
        )
    else:
        fallback = (
            f"Training load is {load['trend']} ({load['current']} vs {load['previous']}). "
            "Keep current intensity but rotate movement patterns to break the plateau."
        )
    routed = _safe_route(payload, fallback)
    return ok({
        "trainingLoad": load,
        "review": routed["answer"],
        "fallback": routed.get("fallback", False),
    })
