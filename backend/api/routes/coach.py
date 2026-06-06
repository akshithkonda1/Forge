from __future__ import annotations

from datetime import datetime, timezone
from typing import Any, Callable

from ai_router import AIRouter, RouteRequest, RoutingError
from responses import RouteError, ok
from services import coach_context, scoring


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
    fallback = (
        f"Readiness is {context['readiness']['overall']}/100. Your last sleep score was "
        f"{(context['recentSleep'] or [{'score': 0}])[0].get('score', 0)}. Train within "
        "your current readiness band and avoid stacking high-intensity days."
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
        context["readiness"]["overall"], last_workout_type
    )

    payload = {
        "question": (
            "Generate a single-day workout plan tailored to today's readiness and the user's "
            "recent training pattern. Return a short paragraph plus 4-6 exercises."
        ),
        "context": coach_context.context_to_prompt_block(context),
    }
    fallback = (
        f"Suggested focus: {baseline['focus']} ({baseline['suggestedType']}, "
        f"{baseline['intensity']} intensity). Use today's plan ('{context['todayPlan']['name']}') "
        "as the template and reduce volume by 10% if energy bank drops below 60."
    )
    routed = _safe_route(payload, fallback)
    return ok({
        "baseline": baseline,
        "todayPlan": context["todayPlan"],
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
    direction = "improving" if recovery["delta"] > 0 else "declining" if recovery["delta"] < 0 else "steady"
    fallback = (
        f"Sleep trend is {direction} (avg {recovery['current']} vs prior {recovery['previous']}). "
        "Protect a consistent wind-down window to lift deep-sleep minutes."
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
