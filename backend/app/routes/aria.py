"""ARIA route handlers.

Routes:
  POST /aria/chat                – Four-turn pipeline chat (tools optional)
  POST /aria/analyze             – Deep analysis with Claude Opus + extended thinking
  POST /aria/plan                – Personalized plan via four-turn pipeline
  POST /aria/lifestyle           – Lifestyle coaching via four-turn pipeline
  POST /aria/voice               – Voice transcript via four-turn pipeline
  POST /aria/insights/generate   – Generate proactive coaching insights
  GET  /aria/insights            – Retrieve stored insights
  GET  /aria/conclusions         – Deterministic data conclusions + offline templates
  POST /aria/brief               – Proactive morning/evening/post-workout coaching brief
  GET  /aria/conversation        – Retrieve ARIA conversation history
  DELETE /aria/conversation      – Reset ARIA conversation
"""
from __future__ import annotations

from datetime import datetime, timezone
from typing import Any

from ai import aria_memory
from ai.aria_agent import ARIAError, get_agent
from ai.aria_tools import ARIA_TOOLS
from core.responses import RouteError, ok
from services import aria_brief, aria_enrichment, coach_context, conclusions_store
from services.aria_pipeline import PipelineIncompleteError, run_four_turn_pipeline
from storage import dynamodb, keys


def _now_iso() -> str:
    return datetime.now(timezone.utc).isoformat()


def _build_user_context(user_id: str) -> str:
    ctx = coach_context.gather_user_context(user_id)
    summary = aria_memory.load_user_summary(user_id)
    if summary and summary.get("summary"):
        ctx["ariaSummary"] = summary["summary"]
    return coach_context.context_to_prompt_block(ctx)


def _trainer_message(
    *,
    content: str,
    rich_card: dict[str, Any] | None,
    tool_calls_made: list[dict[str, Any]],
) -> dict[str, Any]:
    now = _now_iso()
    msg_id = f"aria-{int(datetime.now(timezone.utc).timestamp() * 1000)}"
    tool_names = aria_enrichment.tool_name_list(tool_calls_made)
    message: dict[str, Any] = {
        "id": msg_id,
        "role": "trainer",
        "content": content,
        "timestamp": now,
    }
    if rich_card:
        message["richCard"] = rich_card
    if tool_names:
        message["toolCallsMade"] = tool_names
    return message


def _safe_agent_call(fn, *args, **kwargs) -> dict[str, Any]:
    try:
        return fn(*args, **kwargs)
    except ARIAError as exc:
        raise RouteError(exc.status_code, exc.message) from exc


def _load_conclusions(user_id: str) -> dict[str, Any]:
    try:
        return conclusions_store.get_or_refresh_conclusions(user_id)
    except Exception as exc:
        raise RouteError(503, f"Unable to load conclusions: {exc}") from exc


def _pipeline_or_template(
    *,
    user_id: str,
    user_message: str,
    conclusions: dict[str, Any],
    profile_context: str,
    mode: str,
) -> dict[str, Any]:
    """Run the four-turn pipeline; on failure return offline template fallback."""
    try:
        return run_four_turn_pipeline(
            user_message=user_message,
            conclusions=conclusions,
            profile_context=profile_context,
            mode=mode,
        )
    except PipelineIncompleteError as exc:
        templates = conclusions.get("offlineTemplates") or {}
        fallback = templates.get(mode) or templates.get("chat") or conclusions.get("coachingBrief", "")
        raise RouteError(
            404,
            exc.message,
            code="aria_pipeline_incomplete",
        ) from exc
    except ARIAError as exc:
        templates = conclusions.get("offlineTemplates") or {}
        fallback = templates.get(mode) or templates.get("chat") or ""
        if fallback:
            return {
                "answer": fallback,
                "model": None,
                "usage": {"turnsCompleted": 0, "fallback": True},
                "pipelineIncomplete": True,
            }
        raise RouteError(exc.status_code, exc.message) from exc


def handle_post_aria_brief(user_id: str, body: dict[str, Any]) -> dict:
    focus = str(body.get("focus") or "auto").lower()
    valid = {"morning", "evening", "post-workout", "auto", "midday"}
    if focus not in valid:
        focus = "auto"

    use_llm = bool(body.get("useLLM", body.get("use_llm", False)))
    brief = aria_brief.build_proactive_brief(user_id, focus=focus)

    if use_llm:
        conclusions = _load_conclusions(user_id)
        profile_context = _build_user_context(user_id)
        prompt = (
            f"Write a proactive {brief['focus']} coaching brief in 2-3 sentences. "
            f"Headline: {brief['headline']}. Facts: {brief['body']}"
        )
        try:
            result = run_four_turn_pipeline(
                user_message=prompt,
                conclusions=conclusions,
                profile_context=profile_context,
                mode="dashboard",
            )
            if result.get("answer"):
                brief["body"] = result["answer"]
                brief["notificationCopy"] = aria_brief.notification_copy(
                    brief["headline"],
                    brief["body"],
                )
                brief["llmEnhanced"] = True
                brief["model"] = result.get("model")
        except (PipelineIncompleteError, ARIAError):
            brief["llmEnhanced"] = False

    item = {
        **keys.aria_brief_key(user_id, brief.get("dailyScores", {}).get("date", "")[:10] or _now_iso()[:10], brief["focus"]),
        **{k: v for k, v in brief.items() if k != "dailyScores"},
        "dailyScoresDate": (brief.get("dailyScores") or {}).get("date"),
    }
    dynamodb.put_item(item)

    if bool(body.get("deliverPush", body.get("push", False))):
        from services import push_dispatch

        push_dispatch.send_push_to_user(
            user_id,
            title=brief.get("title", "ARIA Brief"),
            body=brief.get("notificationCopy") or brief.get("headline", ""),
            data={
                "briefFocus": brief.get("focus", "auto"),
                "trainingDecision": brief.get("trainingDecision", ""),
            },
        )

    return ok(brief)


def handle_get_aria_conclusions(user_id: str) -> dict:
    conclusions = _load_conclusions(user_id)
    return ok({
        "conclusions": conclusions,
        "coveragePct": conclusions.get("coveragePct"),
        "coachingBrief": conclusions.get("coachingBrief"),
        "compoundFlags": conclusions.get("compoundFlags"),
        "offlineTemplates": conclusions.get("offlineTemplates"),
        "retrievedAt": _now_iso(),
    })


def handle_post_aria_chat(user_id: str, body: dict[str, Any]) -> dict:
    content = str(body.get("content") or "").strip()
    if not content:
        raise RouteError(400, "Request body must include non-empty 'content'.")

    thread_id = str(body.get("threadId") or body.get("thread_id") or "current")
    use_tools = body.get("useTools", body.get("use_tools", False))
    conclusions = _load_conclusions(user_id)
    profile_context = _build_user_context(user_id)

    if use_tools:
        conversation = aria_memory.load_conversation(user_id, thread_id)
        inject_context = profile_context if not conversation else None
        result = _safe_agent_call(
            get_agent().chat,
            user_id=user_id,
            user_message=content,
            conversation=conversation,
            tools=ARIA_TOOLS,
            inject_context=inject_context,
        )
        tool_calls_made = result.get("toolCallsMade", [])
    else:
        try:
            result = run_four_turn_pipeline(
                user_message=content,
                conclusions=conclusions,
                profile_context=profile_context,
                mode="chat",
            )
        except PipelineIncompleteError as exc:
            templates = conclusions.get("offlineTemplates") or {}
            fallback = templates.get("chat", conclusions.get("coachingBrief", ""))
            return ok({
                "threadId": thread_id,
                "message": _trainer_message(content=fallback, rich_card=None, tool_calls_made=[]),
                "toolCallsMade": [],
                "pipelineIncomplete": True,
                "turnsCompleted": exc.turn - 1,
                "offlineTemplate": True,
                "coachingBrief": conclusions.get("coachingBrief"),
            })
        tool_calls_made = []

    rich_card = aria_enrichment.maybe_rich_card(user_id, content, tool_calls_made)
    trainer_msg = _trainer_message(
        content=result["answer"],
        rich_card=rich_card,
        tool_calls_made=tool_calls_made,
    )

    user_msg = {
        "role": "user",
        "content": content,
        "id": f"user-{int(datetime.now(timezone.utc).timestamp() * 1000)}",
        "timestamp": _now_iso(),
    }
    assistant_msg = {
        "role": "assistant",
        "content": result["answer"],
        "id": trainer_msg["id"],
        "timestamp": trainer_msg["timestamp"],
    }
    if rich_card:
        assistant_msg["richCard"] = rich_card
    if trainer_msg.get("toolCallsMade"):
        assistant_msg["toolCallsMade"] = trainer_msg["toolCallsMade"]

    aria_memory.append_messages(user_id, [user_msg, assistant_msg], thread_id)

    response: dict[str, Any] = {
        "threadId": thread_id,
        "message": trainer_msg,
        "toolCallsMade": aria_enrichment.tool_name_list(tool_calls_made),
        "toolCallDetails": tool_calls_made,
        "model": result.get("model"),
        "usage": result.get("usage"),
        "coachingBrief": conclusions.get("coachingBrief"),
    }
    if result.get("turnsCompleted"):
        response["turnsCompleted"] = result["turnsCompleted"]
    return ok(response)


def handle_post_aria_analyze(user_id: str, body: dict[str, Any]) -> dict:
    question = str(body.get("question") or body.get("content") or "").strip()
    if not question:
        raise RouteError(400, "Request body must include non-empty 'question'.")

    thinking_budget = max(1024, min(32000, int(body.get("thinkingBudget", 10000))))
    context = _build_user_context(user_id)
    conclusions = _load_conclusions(user_id)
    context = f"{context}\n\nCONCLUSIONS:\n{conclusions.get('coachingBrief', '')}"

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
        "coachingBrief": conclusions.get("coachingBrief"),
    })


def _pipeline_endpoint(
    user_id: str,
    *,
    user_message: str,
    mode: str,
    persist_thread: str | None = None,
) -> dict[str, Any]:
    conclusions = _load_conclusions(user_id)
    profile_context = _build_user_context(user_id)
    try:
        result = run_four_turn_pipeline(
            user_message=user_message,
            conclusions=conclusions,
            profile_context=profile_context,
            mode=mode,
        )
    except PipelineIncompleteError:
        templates = conclusions.get("offlineTemplates") or {}
        result = {
            "answer": templates.get(mode) or templates.get("chat") or conclusions.get("coachingBrief", ""),
            "model": None,
            "usage": {"turnsCompleted": 0, "fallback": True},
            "pipelineIncomplete": True,
        }

    if persist_thread:
        user_msg = {"role": "user", "content": user_message}
        assistant_msg = {"role": "assistant", "content": result["answer"]}
        aria_memory.append_messages(user_id, [user_msg, assistant_msg], persist_thread)

    return {**result, "coachingBrief": conclusions.get("coachingBrief")}


def handle_post_aria_plan(user_id: str, body: dict[str, Any]) -> dict:
    focus = str(body.get("focus") or "auto").lower()
    valid_focus = {"workout", "recovery", "nutrition", "auto"}
    if focus not in valid_focus:
        focus = "auto"

    focus_prompt = {
        "workout": "Generate a complete workout plan for today based on readiness and training history.",
        "recovery": "Design a recovery protocol for today based on readiness, sleep, and training load.",
        "nutrition": "Provide today's nutrition strategy based on planned training and recent intake.",
        "auto": "Decide whether today is training, recovery, or active rest and provide the plan.",
    }[focus]

    result = _pipeline_endpoint(user_id, user_message=focus_prompt, mode="plan")
    return ok({
        "focus": focus,
        "plan": result["answer"],
        "toolCallsMade": [],
        "model": result.get("model"),
        "usage": result.get("usage"),
        "generatedAt": _now_iso(),
        "coachingBrief": result.get("coachingBrief"),
        "pipelineIncomplete": result.get("pipelineIncomplete", False),
        "turnsCompleted": result.get("usage", {}).get("turnsCompleted"),
    })


def handle_post_aria_lifestyle(user_id: str, body: dict[str, Any]) -> dict:
    focus = str(body.get("focus") or "holistic").lower()
    valid_focus = {"nutrition", "wellbeing", "holistic"}
    if focus not in valid_focus:
        focus = "holistic"

    focus_prompt = {
        "nutrition": "Review nutrition gaps and give one specific meal recommendation for today.",
        "wellbeing": "Review wellbeing habits and recommend the highest-impact habit for today.",
        "holistic": "Review lifestyle dashboard and give one prioritized focus with training, nutrition, and recovery actions.",
    }[focus]

    result = _pipeline_endpoint(
        user_id,
        user_message=focus_prompt,
        mode="lifestyle",
        persist_thread="lifestyle",
    )
    return ok({
        "focus": focus,
        "coaching": result["answer"],
        "toolCallsMade": [],
        "model": result.get("model"),
        "usage": result.get("usage"),
        "generatedAt": _now_iso(),
        "coachingBrief": result.get("coachingBrief"),
        "pipelineIncomplete": result.get("pipelineIncomplete", False),
    })


def handle_post_aria_voice(user_id: str, body: dict[str, Any]) -> dict:
    transcript = str(body.get("transcript") or "").strip()
    if not transcript:
        raise RouteError(400, "Request body must include non-empty 'transcript'.")

    result = _pipeline_endpoint(user_id, user_message=transcript, mode="voice")
    return ok({
        "answer": result["answer"],
        "processedTranscript": transcript,
        "model": result.get("model"),
        "usage": result.get("usage"),
        "timestamp": _now_iso(),
        "coachingBrief": result.get("coachingBrief"),
        "pipelineIncomplete": result.get("pipelineIncomplete", False),
    })


def handle_post_aria_insights_generate(user_id: str, _body: dict[str, Any]) -> dict:
    context = _build_user_context(user_id)
    conclusions = _load_conclusions(user_id)
    context = f"{context}\n\nCONCLUSIONS:\n{conclusions.get('coachingBrief', '')}"

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


def handle_get_aria_insights(user_id: str, days: int = 7) -> dict:
    insights = aria_memory.load_insights(user_id, days)

    if not insights:
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


def handle_get_aria_conversation(user_id: str, thread_id: str = "current") -> dict:
    raw_messages = aria_memory.load_conversation(user_id, thread_id)
    messages = aria_enrichment.normalize_conversation_messages(
        raw_messages,
        thread_id=thread_id,
    )
    return ok({
        "threadId": thread_id,
        "messages": messages,
        "messageCount": len(messages),
    })


def handle_delete_aria_conversation(user_id: str, thread_id: str = "current") -> dict:
    aria_memory.clear_conversation(user_id, thread_id)
    return ok({
        "threadId": thread_id,
        "cleared": True,
        "clearedAt": _now_iso(),
    })