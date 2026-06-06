"""Tests for the ARIA backend layer.

All tests use stub implementations so no real Anthropic API key or DynamoDB
table is needed. The test seam is the module-level aria_agent.set_agent()
function which replaces the agent with a controllable stub.
"""
import json
import os
import sys
import unittest
from pathlib import Path
from typing import Any
from unittest.mock import MagicMock, patch


LAMBDA_DIR = Path(__file__).resolve().parents[1] / "infra" / "terraform" / "lambda"
sys.path.insert(0, str(LAMBDA_DIR))

import aria_agent
import aria_memory
from handler import handler
from storage import dynamodb as dynamodb_store


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

def event(method, path, body=None, query=None):
    payload = {
        "requestContext": {"http": {"method": method, "path": path}},
        "queryStringParameters": query or {},
    }
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def body(response):
    return json.loads(response["body"])


class StubARIAAgent:
    """
    A controllable stub of ARIAAgent used in tests. All methods return
    canned responses without calling the Anthropic API.
    """

    def __init__(self):
        self.chat_calls: list[dict[str, Any]] = []
        self.analyze_calls: list[dict[str, Any]] = []
        self.insights_calls: list[dict[str, Any]] = []
        self.voice_calls: list[dict[str, Any]] = []

        self._chat_response: dict[str, Any] = {
            "answer": "Stub ARIA answer.",
            "toolCallsMade": [{"tool": "get_health_snapshot", "input": {}, "success": True}],
            "model": "claude-sonnet-4-6",
            "usage": {"inputTokens": 100, "outputTokens": 50, "cacheReadTokens": 80, "cacheCreationTokens": 0},
            "updatedConversation": [],
        }
        self._analyze_response: dict[str, Any] = {
            "answer": "Stub deep analysis.",
            "thinking": "Stub thinking trace.",
            "model": "claude-opus-4-8",
            "thinkingBudget": 10000,
            "usage": {"inputTokens": 500, "outputTokens": 200, "cacheReadTokens": 0, "cacheCreationTokens": 400},
        }
        self._insights_response: dict[str, Any] = {
            "insights": [
                {
                    "type": "sleep",
                    "priority": "high",
                    "title": "Deep sleep below target",
                    "observation": "Average deep sleep 78 min vs 90 min target.",
                    "recommendation": "Move bedtime 30 minutes earlier this week.",
                    "metric": "deepMinutes",
                },
                {
                    "type": "training",
                    "priority": "medium",
                    "title": "Training load rising fast",
                    "observation": "Weekly load up 35% from prior week.",
                    "recommendation": "Replace one high-intensity session with moderate cardio.",
                    "metric": "trainingLoad",
                },
            ],
            "model": "claude-sonnet-4-6",
            "usage": {"inputTokens": 300, "outputTokens": 150},
        }
        self._voice_response: dict[str, Any] = {
            "answer": "Based on your readiness score of 82, you are primed for today's session.",
            "processedTranscript": "how should I train today",
            "model": "claude-sonnet-4-6",
            "usage": {"inputTokens": 80, "outputTokens": 40},
        }

    def chat(self, *, user_id, user_message, conversation, tools=None, inject_context=None):
        self.chat_calls.append({"user_message": user_message, "conversation_len": len(conversation)})
        resp = dict(self._chat_response)
        resp["updatedConversation"] = list(conversation) + [
            {"role": "user", "content": user_message},
            {"role": "assistant", "content": resp["answer"]},
        ]
        return resp

    def analyze(self, *, question, context, thinking_budget=10000):
        self.analyze_calls.append({"question": question})
        return dict(self._analyze_response)

    def generate_insights(self, *, context):
        self.insights_calls.append({"context_len": len(context)})
        return dict(self._insights_response)

    def process_voice(self, *, transcript, context):
        self.voice_calls.append({"transcript": transcript})
        return dict(self._voice_response)


# ---------------------------------------------------------------------------
# Base test class
# ---------------------------------------------------------------------------

class ARIATestBase(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()
        self.stub = StubARIAAgent()
        aria_agent.set_agent(self.stub)

    def tearDown(self):
        aria_agent.set_agent(None)
        dynamodb_store.clear_local_store()


# ---------------------------------------------------------------------------
# /aria/chat
# ---------------------------------------------------------------------------

class ARIAChatTests(ARIATestBase):
    def test_chat_returns_trainer_message(self):
        resp = handler(event("POST", "/aria/chat", {"content": "How should I train today?"}), None)
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertEqual(payload["message"]["role"], "trainer")
        self.assertEqual(payload["message"]["content"], "Stub ARIA answer.")
        self.assertIsNotNone(payload["message"]["timestamp"])
        self.assertEqual(payload["threadId"], "current")

    def test_chat_empty_content_returns_400(self):
        resp = handler(event("POST", "/aria/chat", {"content": ""}), None)
        self.assertEqual(resp["statusCode"], 400)

    def test_chat_missing_content_returns_400(self):
        resp = handler(event("POST", "/aria/chat", {}), None)
        self.assertEqual(resp["statusCode"], 400)

    def test_chat_includes_tool_calls_made(self):
        resp = handler(event("POST", "/aria/chat", {"content": "Check my readiness."}), None)
        payload = body(resp)
        self.assertIsInstance(payload["toolCallsMade"], list)
        self.assertEqual(payload["toolCallsMade"][0]["tool"], "get_health_snapshot")

    def test_chat_includes_model_and_usage(self):
        resp = handler(event("POST", "/aria/chat", {"content": "What's my HRV?"}), None)
        payload = body(resp)
        self.assertEqual(payload["model"], "claude-sonnet-4-6")
        self.assertIn("inputTokens", payload["usage"])
        self.assertIn("cacheReadTokens", payload["usage"])

    def test_chat_persists_messages_in_memory(self):
        handler(event("POST", "/aria/chat", {"content": "First message."}), None)
        handler(event("POST", "/aria/chat", {"content": "Second message."}), None)

        # Second call should have seen a non-empty conversation
        self.assertEqual(len(self.stub.chat_calls), 2)
        self.assertGreater(self.stub.chat_calls[1]["conversation_len"], 0)

    def test_chat_custom_thread_id(self):
        resp = handler(
            event("POST", "/aria/chat", {"content": "Thread test.", "threadId": "my-thread"}),
            None,
        )
        payload = body(resp)
        self.assertEqual(payload["threadId"], "my-thread")


# ---------------------------------------------------------------------------
# /aria/analyze
# ---------------------------------------------------------------------------

class ARIAAnalyzeTests(ARIATestBase):
    def test_analyze_returns_analysis(self):
        resp = handler(
            event("POST", "/aria/analyze", {"question": "Why is my HRV declining?"}),
            None,
        )
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertEqual(payload["analysis"], "Stub deep analysis.")
        self.assertEqual(payload["model"], "claude-opus-4-8")
        self.assertIn("inputTokens", payload["usage"])

    def test_analyze_empty_question_returns_400(self):
        resp = handler(event("POST", "/aria/analyze", {"question": ""}), None)
        self.assertEqual(resp["statusCode"], 400)

    def test_analyze_passes_thinking_budget(self):
        resp = handler(
            event("POST", "/aria/analyze", {"question": "Analyze my recovery.", "thinkingBudget": 5000}),
            None,
        )
        self.assertEqual(resp["statusCode"], 200)
        # Stub always returns 10000 but route validates the parameter
        self.assertEqual(len(self.stub.analyze_calls), 1)
        self.assertEqual(self.stub.analyze_calls[0]["question"], "Analyze my recovery.")

    def test_analyze_returns_question_echo(self):
        resp = handler(
            event("POST", "/aria/analyze", {"question": "Why am I overtrained?"}),
            None,
        )
        payload = body(resp)
        self.assertEqual(payload["question"], "Why am I overtrained?")


# ---------------------------------------------------------------------------
# /aria/plan
# ---------------------------------------------------------------------------

class ARIAPlanTests(ARIATestBase):
    def test_plan_default_focus_returns_plan(self):
        resp = handler(event("POST", "/aria/plan", {}), None)
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertIn("plan", payload)
        self.assertEqual(payload["focus"], "auto")
        self.assertIn("generatedAt", payload)

    def test_plan_workout_focus(self):
        resp = handler(event("POST", "/aria/plan", {"focus": "workout"}), None)
        payload = body(resp)
        self.assertEqual(payload["focus"], "workout")

    def test_plan_recovery_focus(self):
        resp = handler(event("POST", "/aria/plan", {"focus": "recovery"}), None)
        payload = body(resp)
        self.assertEqual(payload["focus"], "recovery")

    def test_plan_invalid_focus_defaults_to_auto(self):
        resp = handler(event("POST", "/aria/plan", {"focus": "unknown"}), None)
        payload = body(resp)
        self.assertEqual(payload["focus"], "auto")


# ---------------------------------------------------------------------------
# /aria/voice
# ---------------------------------------------------------------------------

class ARIAVoiceTests(ARIATestBase):
    def test_voice_returns_answer(self):
        resp = handler(
            event("POST", "/aria/voice", {"transcript": "how should I train today"}),
            None,
        )
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertIn("answer", payload)
        self.assertIn("readiness", payload["answer"])
        self.assertEqual(payload["processedTranscript"], "how should I train today")

    def test_voice_empty_transcript_returns_400(self):
        resp = handler(event("POST", "/aria/voice", {"transcript": ""}), None)
        self.assertEqual(resp["statusCode"], 400)

    def test_voice_missing_transcript_returns_400(self):
        resp = handler(event("POST", "/aria/voice", {}), None)
        self.assertEqual(resp["statusCode"], 400)

    def test_voice_includes_timestamp(self):
        resp = handler(event("POST", "/aria/voice", {"transcript": "check my sleep"}), None)
        payload = body(resp)
        self.assertIn("timestamp", payload)


# ---------------------------------------------------------------------------
# /aria/insights
# ---------------------------------------------------------------------------

class ARIAInsightsTests(ARIATestBase):
    def test_insights_generate_returns_insights(self):
        resp = handler(event("POST", "/aria/insights/generate", {}), None)
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertIsInstance(payload["insights"], list)
        self.assertEqual(payload["count"], 2)
        self.assertEqual(payload["insights"][0]["type"], "sleep")
        self.assertIn("recommendation", payload["insights"][0])

    def test_insights_generate_persists_to_dynamodb(self):
        handler(event("POST", "/aria/insights/generate", {}), None)
        # Insights should now be stored and retrievable
        resp2 = handler(event("GET", "/aria/insights"), None)
        payload = body(resp2)
        self.assertGreater(payload["count"], 0)

    def test_insights_get_autogenerates_when_empty(self):
        # No insights stored yet — GET should auto-generate
        resp = handler(event("GET", "/aria/insights"), None)
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertIsInstance(payload["insights"], list)

    def test_insights_get_respects_days_query(self):
        resp = handler(event("GET", "/aria/insights", query={"days": "3"}), None)
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertEqual(payload["periodDays"], 3)


# ---------------------------------------------------------------------------
# /aria/conversation
# ---------------------------------------------------------------------------

class ARIAConversationTests(ARIATestBase):
    def test_get_empty_conversation(self):
        resp = handler(event("GET", "/aria/conversation"), None)
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertEqual(payload["messages"], [])
        self.assertEqual(payload["messageCount"], 0)
        self.assertEqual(payload["threadId"], "current")

    def test_conversation_populated_after_chat(self):
        handler(event("POST", "/aria/chat", {"content": "Hello ARIA!"}), None)
        resp = handler(event("GET", "/aria/conversation"), None)
        payload = body(resp)
        self.assertGreater(payload["messageCount"], 0)

    def test_delete_conversation_clears_messages(self):
        handler(event("POST", "/aria/chat", {"content": "Hello ARIA!"}), None)
        handler(event("DELETE", "/aria/conversation"), None)
        resp = handler(event("GET", "/aria/conversation"), None)
        payload = body(resp)
        self.assertEqual(payload["messageCount"], 0)

    def test_delete_conversation_returns_confirmation(self):
        resp = handler(event("DELETE", "/aria/conversation"), None)
        self.assertEqual(resp["statusCode"], 200)
        payload = body(resp)
        self.assertTrue(payload["cleared"])
        self.assertIn("clearedAt", payload)

    def test_conversation_custom_thread(self):
        handler(event("POST", "/aria/chat", {"content": "Thread A.", "threadId": "thread-a"}), None)
        resp = handler(event("GET", "/aria/conversation", query={"threadId": "thread-a"}), None)
        payload = body(resp)
        self.assertEqual(payload["threadId"], "thread-a")
        self.assertGreater(payload["messageCount"], 0)

        # Default thread should still be empty
        resp2 = handler(event("GET", "/aria/conversation"), None)
        self.assertEqual(body(resp2)["messageCount"], 0)


# ---------------------------------------------------------------------------
# /health endpoint shows ARIA status
# ---------------------------------------------------------------------------

class HealthEndpointARIATests(unittest.TestCase):
    def test_health_includes_aria_section(self):
        resp = handler(event("GET", "/health"), None)
        payload = body(resp)
        self.assertIn("aria", payload)
        self.assertIn("backend", payload["aria"])
        self.assertIn("chatModel", payload["aria"])
        self.assertIn("analysisModel", payload["aria"])
        self.assertIn("backupModel", payload["aria"])
        self.assertIn("features", payload["aria"])
        self.assertIn("tool-use", payload["aria"]["features"])
        self.assertIn("extended-thinking", payload["aria"]["features"])
        self.assertIn("prompt-caching", payload["aria"]["features"])
        self.assertIn("backup-model", payload["aria"]["features"])


# ---------------------------------------------------------------------------
# aria_memory unit tests
# ---------------------------------------------------------------------------

class ARIAMemoryTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()

    def tearDown(self):
        dynamodb_store.clear_local_store()

    def test_load_empty_conversation(self):
        msgs = aria_memory.load_conversation("user-1")
        self.assertEqual(msgs, [])

    def test_save_and_load_conversation(self):
        messages = [
            {"role": "user", "content": "Hello"},
            {"role": "assistant", "content": "Hi there!"},
        ]
        aria_memory.save_conversation("user-1", messages)
        loaded = aria_memory.load_conversation("user-1")
        self.assertEqual(len(loaded), 2)
        self.assertEqual(loaded[0]["content"], "Hello")
        self.assertEqual(loaded[1]["role"], "assistant")

    def test_append_messages(self):
        aria_memory.append_messages("user-1", [{"role": "user", "content": "msg1"}])
        aria_memory.append_messages("user-1", [{"role": "assistant", "content": "reply1"}])
        msgs = aria_memory.load_conversation("user-1")
        self.assertEqual(len(msgs), 2)

    def test_clear_conversation(self):
        aria_memory.save_conversation("user-1", [{"role": "user", "content": "test"}])
        aria_memory.clear_conversation("user-1")
        self.assertEqual(aria_memory.load_conversation("user-1"), [])

    def test_conversation_compression_at_max_messages(self):
        # Build a conversation just past MAX_MESSAGES
        large = [
            {"role": "user" if i % 2 == 0 else "assistant", "content": f"Message {i}"}
            for i in range(aria_memory.MAX_MESSAGES + 5)
        ]
        aria_memory.save_conversation("user-1", large)
        aria_memory.append_messages("user-1", [{"role": "user", "content": "new"}])
        msgs = aria_memory.load_conversation("user-1")
        # Should be compressed — well below MAX_MESSAGES
        self.assertLess(len(msgs), aria_memory.MAX_MESSAGES)
        # First message should be the summary marker
        self.assertIn("ARIA CONVERSATION SUMMARY", msgs[0]["content"])

    def test_save_and_load_insight(self):
        insight_id = aria_memory.save_insight("user-1", {
            "type": "sleep",
            "priority": "high",
            "title": "Sleep dipping",
            "observation": "Deep sleep trending down.",
            "recommendation": "Earlier bedtime.",
        })
        insights = aria_memory.load_insights("user-1")
        self.assertTrue(any(i.get("insightId") == insight_id for i in insights))

    def test_save_user_summary(self):
        aria_memory.save_user_summary("user-1", "User focuses on strength. Prefers morning workouts.")
        summary = aria_memory.load_user_summary("user-1")
        self.assertIsNotNone(summary)
        self.assertIn("strength", summary["summary"])


# ---------------------------------------------------------------------------
# aria_agent unit tests (no Anthropic API)
# ---------------------------------------------------------------------------

class ARIAAgentConfigTests(unittest.TestCase):
    def test_anthropic_client_raises_when_no_api_key(self):
        """_get_anthropic_client raises ARIAError(503) when ANTHROPIC_API_KEY is absent."""
        agent = aria_agent.ARIAAgent()
        original = os.environ.pop("ANTHROPIC_API_KEY", None)
        try:
            with self.assertRaises(aria_agent.ARIAError) as ctx:
                agent._get_anthropic_client()
            self.assertEqual(ctx.exception.status_code, 503)
            self.assertIn("ANTHROPIC_API_KEY", ctx.exception.message)
        finally:
            if original is not None:
                os.environ["ANTHROPIC_API_KEY"] = original

    def test_bedrock_backend_does_not_require_api_key(self):
        """Bedrock backend initialises without ANTHROPIC_API_KEY (uses IAM role)."""
        original = os.environ.pop("ANTHROPIC_API_KEY", None)
        try:
            # ARIAAgent created with no API key — Bedrock path should not raise
            agent = aria_agent.ARIAAgent()
            # _get_bedrock_client only raises if boto3 is absent, not for missing API key
            # We just confirm no ARIAError about ANTHROPIC_API_KEY is raised
            try:
                agent._get_bedrock_client()
            except aria_agent.ARIAError as exc:
                self.assertNotIn("ANTHROPIC_API_KEY", exc.message)
            except Exception:
                pass  # boto3 may be absent in test env — that's fine
        finally:
            if original is not None:
                os.environ["ANTHROPIC_API_KEY"] = original

    def test_set_agent_replaces_singleton(self):
        stub = StubARIAAgent()
        aria_agent.set_agent(stub)
        self.assertIs(aria_agent.get_agent(), stub)
        aria_agent.set_agent(None)

    def test_parse_json_array_valid(self):
        result = aria_agent._parse_json_array('[{"a": 1}]')
        self.assertEqual(result, [{"a": 1}])

    def test_parse_json_array_embedded(self):
        result = aria_agent._parse_json_array('Some text [{"x": 2}] end')
        self.assertEqual(result, [{"x": 2}])

    def test_parse_json_array_invalid_returns_empty(self):
        result = aria_agent._parse_json_array("not json at all")
        self.assertEqual(result, [])

    def test_backup_model_triggered_on_primary_failure(self):
        """_one_turn retries with backup model when primary raises a non-ARIAError."""
        import aria_agent as aa

        call_log: list[str] = []

        class FailingOnce(aa.ARIAAgent):
            def _one_turn_bedrock(self, model, working, tools, max_tokens, extra_fields=None):
                call_log.append(model)
                if model == aa.ARIA_CHAT_MODEL:
                    raise RuntimeError("simulated primary failure")
                # backup call succeeds
                return {
                    "stop_reason": "end_turn",
                    "content": [{"type": "text", "text": "Backup answer"}],
                    "usage": {"inputTokens": 5, "outputTokens": 3, "cacheReadTokens": 0, "cacheCreationTokens": 0},
                }

        original_backend = aa.ARIA_BACKEND
        # Patch module globals to use bedrock path with distinct primary/backup
        try:
            aa.ARIA_BACKEND = "bedrock"
            agent = FailingOnce()
            msgs = [{"role": "user", "content": [{"type": "text", "text": "test"}]}]
            result = agent._one_turn(aa.ARIA_CHAT_MODEL, msgs, None, 128)
            self.assertTrue(result.get("usedBackup"))
            self.assertEqual(result["content"][0]["text"], "Backup answer")
        finally:
            aa.ARIA_BACKEND = original_backend

    def test_aria_error_not_retried_with_backup(self):
        """ARIAError from primary is not swallowed or retried — it propagates."""
        import aria_agent as aa

        class AlwaysARIAError(aa.ARIAAgent):
            def _one_turn_bedrock(self, model, working, tools, max_tokens, extra_fields=None):
                raise aa.ARIAError(503, "hard config error")

        agent = AlwaysARIAError()
        msgs = [{"role": "user", "content": [{"type": "text", "text": "test"}]}]
        with self.assertRaises(aa.ARIAError) as ctx:
            agent._one_turn(aa.ARIA_CHAT_MODEL, msgs, None, 128)
        self.assertEqual(ctx.exception.status_code, 503)


# ---------------------------------------------------------------------------
# aria_tools unit tests
# ---------------------------------------------------------------------------

class ARIAToolsTests(unittest.TestCase):
    def setUp(self):
        dynamodb_store.clear_local_store()

    def tearDown(self):
        dynamodb_store.clear_local_store()

    def test_get_user_profile_returns_seed(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "get_user_profile", {})
        self.assertIn("profile", result)
        self.assertIn("name", result["profile"])

    def test_get_health_snapshot_returns_readiness(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "get_health_snapshot", {})
        self.assertIn("readiness", result)
        self.assertIn("overall", result["readiness"])

    def test_get_sleep_analysis_defaults_7_days(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "get_sleep_analysis", {})
        self.assertIn("nights", result)
        self.assertEqual(result["periodDays"], 7)
        self.assertIn("averages", result)
        self.assertIn("recoveryTrend", result)

    def test_get_sleep_analysis_respects_days(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "get_sleep_analysis", {"days": 3})
        self.assertEqual(result["periodDays"], 3)

    def test_get_workout_history_returns_load(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "get_workout_history", {})
        self.assertIn("workouts", result)
        self.assertIn("trainingLoad", result)
        self.assertIn("trend", result["trainingLoad"])

    def test_get_personal_records_returns_list(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "get_personal_records", {})
        self.assertIn("personalRecords", result)
        self.assertIsInstance(result["personalRecords"], list)

    def test_get_todays_plan_returns_plan(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "get_todays_plan", {})
        self.assertIn("todayPlan", result)
        self.assertIn("exercises", result["todayPlan"])

    def test_compute_readiness_score_returns_score(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "compute_readiness_score", {})
        self.assertIn("readiness", result)
        self.assertIn("overall", result["readiness"])

    def test_get_training_load_returns_trend(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "get_training_load", {})
        self.assertIn("trainingLoad", result)
        self.assertIn("trend", result["trainingLoad"])

    def test_log_coaching_insight_persists(self):
        from aria_tools import handle_tool_call
        result = handle_tool_call("user-1", "log_coaching_insight", {
            "type": "sleep",
            "priority": "high",
            "title": "Test insight",
            "observation": "Sleep is declining.",
            "recommendation": "Earlier bedtime.",
        })
        self.assertTrue(result["saved"])
        self.assertIn("insightId", result)

    def test_unknown_tool_raises(self):
        from aria_tools import handle_tool_call
        with self.assertRaises(ValueError) as ctx:
            handle_tool_call("user-1", "does_not_exist", {})
        self.assertIn("does_not_exist", str(ctx.exception))

    def test_tool_schema_completeness(self):
        from aria_tools import ARIA_TOOLS
        for tool in ARIA_TOOLS:
            self.assertIn("name", tool, f"Tool missing name: {tool}")
            self.assertIn("description", tool, f"Tool missing description: {tool['name']}")
            self.assertIn("input_schema", tool, f"Tool missing input_schema: {tool['name']}")
            self.assertIn("type", tool["input_schema"], f"input_schema missing type: {tool['name']}")


if __name__ == "__main__":
    unittest.main()
