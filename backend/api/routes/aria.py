"""ARIA route handlers.

These are thin handlers that wire HTTP route events to the ARIA agent and
memory layer. All heavy lifting is in aria_agent.py, aria_tools.py, and
aria_memory.py.

Routes:
  POST /aria/chat                – Agentic multi-turn chat with tool use
  POST /aria/analyze             – Deep analysis with Claude Opus + extended thinking
  POST /aria/plan                – Generate today's personalized workout/recovery plan
  POST /aria/voice               – Process a voice transcript
  POST /aria/insights/generate   – Generate proactive coaching insights
  GET  /aria/insights            – Retrieve stored insights
  GET  /aria/conversation        – Retrieve ARIA conversation history
  DELETE /aria/conversation      – Reset ARIA conversation
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

import aria_memory
from aria_agent import ARIAError, get_agent
from aria_tools import ARIA_TOOLS
from responses import RouteError, ok
from seed_data import today_iso
from services import coach_context
from storage import dynamodb, keys


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _build_user_context(user_id: str) -> str:
    """Gather and serialize the user context block for injection into ARIA."""
    ctx = coach_context.gather_user_context(user_id)
    return coach_context.context_to_prompt_block(ctx)


def _safe_agent_call(fn, *args, **kwargs) -> dict[str, Any]:
    """Wrap an agent call and translate ARIAError to RouteError."""
    try:
        return fn(*args, **kwargs)
    except ARIAError as exc:
        raise RouteError(exc.status_code, exc.message) from exc


# ---------------------------------------------------------------------------
# POST /aria/chat
# ---------------------------------------------------------------------------

def handle_post_aria_chat(user_id: str, body: dict[str, Any]) -> dict:
    """
    Main agentic chat endpoint. ARIA uses tools to fetch real user data and
    returns a grounded coaching response.

    Request body:
      content    (str, required)   – the user's message
      thread_id  (str, optional)   – conversation thread, defaults to "current"
      use_tools  (bool, optional)  – set false to skip tool use (default: true)
    """
    content = str(body.get("content") or "").strip()
    if not content:
        raise RouteError(400, "Request body must include non-empty 'content'.")

    thread_id = str(body.get("threadId") or body.get("thread_id") or "current")
    use_tools = body.get("useTools", body.get("use_tools", True))

    # Load conversation history from DynamoDB
    conversation = aria_memory.load_conversation(user_id, thread_id)

    # On the first message of a thread inject the user context as a cached block
    inject_context = _build_user_context(user_id) if not conversation else None

    tools = ARIA_TOOLS if use_tools else None

    result = _safe_agent_call(
        get_agent().chat,
        user_id=user_id,
        user_message=content,
        conversation=conversation,
        tools=tools,
        inject_context=inject_context,
    )

    # Persist the new turns
    user_msg = {"role": "user", "content": content}
    assistant_msg = {"role": "assistant", "content": result["answer"]}
    aria_memory.append_messages(user_id, [user_msg, assistant_msg], thread_id)

    now = _now_iso()
    return ok({
        "threadId": thread_id,
        "message": {
            "id": f"aria-{int(datetime.now(timezone.utc).timestamp() * 1000)}",
            "role": "trainer",
            "content": result["answer"],
            "timestamp": now,
        },
        "toolCallsMade": result.get("toolCallsMade", []),
        "model": result.get("model"),
        "usage": result.get("usage"),
    })


# ---------------------------------------------------------------------------
# POST /aria/analyze
# ---------------------------------------------------------------------------

def handle_post_aria_analyze(user_id: str, body: dict[str, Any]) -> dict:
    """
    Deep analysis endpoint using Claude Opus with extended thinking.

    Best for complex questions: periodization planning, injury risk assessment,
    sleep pattern root-cause analysis, long-term progress review.

    Request body:
      question       (str, required)  – the analytical question
      thinking_budget (int, optional) – extended thinking token budget (default 10000)
    """
    question = str(body.get("question") or body.get("content") or "").strip()
    if not question:
        raise RouteError(400, "Request body must include non-empty 'question'.")

    thinking_budget = max(1024, min(32000, int(body.get("thinkingBudget", 10000))))
    context = _build_user_context(user_id)

    result = _safe_agent_call(
        get_agent().analyze,
        question=question,
        context=context,
        thinking_budget=thinking_budget,
    )

    return ok({
        "question": question,
        "analysis": result["answer"],
        "model": result.get("model"),
        "thinkingBudget": result.get("thinkingBudget"),
        "usage": result.get("usage"),
    })


# ---------------------------------------------------------------------------
# POST /aria/plan
# ---------------------------------------------------------------------------

def handle_post_aria_plan(user_id: str, body: dict[str, Any]) -> dict:
    """
    Generate a personalized workout or recovery plan for today.

    ARIA uses tools to check readiness, sleep, and recent training before
    producing a tailored plan recommendation.

    Request body:
      focus    (str, optional)  – "workout" | "recovery" | "nutrition" (default: auto)
    """
    focus = str(body.get("focus") or "auto").lower()
    valid_focus = {"workout", "recovery", "nutrition", "auto"}
    if focus not in valid_focus:
        focus = "auto"

    focus_prompt = {
        "workout": (
            "Generate a complete workout plan for today based on the user's current "
            "readiness score, training history, and goals. Include exercises, sets, "
            "reps, weights, and rest periods."
        ),
        "recovery": (
            "Design a recovery protocol for today based on current readiness, sleep "
            "quality, and training load. Include modalities, durations, and priorities."
        ),
        "nutrition": (
            "Provide today's nutrition strategy including macronutrient targets, meal "
            "timing, and pre/post-workout recommendations based on the planned training."
        ),
        "auto": (
            "Review the user's current readiness, sleep, and training load, then "
            "decide whether today should be a training day, recovery day, or active "
            "rest day. If training, provide a complete plan. If recovery, provide a "
            "recovery protocol."
        ),
    }[focus]

    conversation = aria_memory.load_conversation(user_id, "plan")
    inject_context = _build_user_context(user_id) if not conversation else None

    result = _safe_agent_call(
        get_agent().chat,
        user_id=user_id,
        user_message=focus_prompt,
        conversation=conversation,
        tools=ARIA_TOOLS,
        inject_context=inject_context,
    )

    return ok({
        "focus": focus,
        "plan": result["answer"],
        "toolCallsMade": result.get("toolCallsMade", []),
        "model": result.get("model"),
        "usage": result.get("usage"),
        "generatedAt": _now_iso(),
    })


# ---------------------------------------------------------------------------
# POST /aria/voice
# ---------------------------------------------------------------------------

def handle_post_aria_voice(user_id: str, body: dict[str, Any]) -> dict:
    """
    Process a voice transcript and return a coaching response suitable for TTS.

    Request body:
      transcript  (str, required)  – raw voice-to-text transcript
    """
    transcript = str(body.get("transcript") or "").strip()
    if not transcript:
        raise RouteError(400, "Request body must include non-empty 'transcript'.")

    context = _build_user_context(user_id)

    result = _safe_agent_call(
        get_agent().process_voice,
        transcript=transcript,
        context=context,
    )

    return ok({
        "answer": result["answer"],
        "processedTranscript": result.get("processedTranscript", transcript),
        "model": result.get("model"),
        "usage": result.get("usage"),
        "timestamp": _now_iso(),
    })


# ---------------------------------------------------------------------------
# POST /aria/insights/generate
# ---------------------------------------------------------------------------

def handle_post_aria_insights_generate(user_id: str, _body: dict[str, Any]) -> dict:
    """
    Generate and persist proactive coaching insights from the user's data.

    Returns the newly generated insights.
    """
    context = _build_user_context(user_id)

    result = _safe_agent_call(
        get_agent().generate_insights,
        context=context,
    )

    insights = result.get("insights", [])
    insight_ids = aria_memory.save_bulk_insights(user_id, insights)
    for i, insight in enumerate(insights):
        if i < len(insight_ids):
            insight["insightId"] = insight_ids[i]

    return ok({
        "insights": insights,
        "count": len(insights),
        "model": result.get("model"),
        "usage": result.get("usage"),
        "generatedAt": _now_iso(),
    })


# ---------------------------------------------------------------------------
# GET /aria/insights
# ---------------------------------------------------------------------------

def handle_get_aria_insights(user_id: str, days: int = 7) -> dict:
    """
    Retrieve stored ARIA insights for the last N days.

    If no insights exist, generates a fresh set and returns those.
    """
    insights = aria_memory.load_insights(user_id, days)

    if not insights:
        # Auto-generate on first load
        context = _build_user_context(user_id)
        try:
            result = get_agent().generate_insights(context=context)
            generated = result.get("insights", [])
            aria_memory.save_bulk_insights(user_id, generated)
            insights = generated
        except ARIAError:
            insights = []

    return ok({
        "insights": insights,
        "count": len(insights),
        "periodDays": days,
        "retrievedAt": _now_iso(),
    })


# ---------------------------------------------------------------------------
# GET /aria/conversation
# ---------------------------------------------------------------------------

def handle_get_aria_conversation(user_id: str, thread_id: str = "current") -> dict:
    """Retrieve the ARIA conversation history for a thread."""
    messages = aria_memory.load_conversation(user_id, thread_id)
    return ok({
        "threadId": thread_id,
        "messages": messages,
        "messageCount": len(messages),
    })


# ---------------------------------------------------------------------------
# DELETE /aria/conversation
# ---------------------------------------------------------------------------

def handle_delete_aria_conversation(user_id: str, thread_id: str = "current") -> dict:
    """Reset the ARIA conversation, clearing all stored messages for the thread."""
    aria_memory.clear_conversation(user_id, thread_id)
    return ok({
        "threadId": thread_id,
        "cleared": True,
        "clearedAt": _now_iso(),
    })
