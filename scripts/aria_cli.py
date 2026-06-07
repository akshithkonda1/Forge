#!/usr/bin/env python3
"""ARIA CLI — interact with Forge's ARIA coach from the terminal.

Examples:
  python3 scripts/aria_cli.py status
  python3 scripts/aria_cli.py chat "How should I train today?"
  python3 scripts/aria_cli.py analyze "Why is my HRV declining?"
  python3 scripts/aria_cli.py plan --focus workout
  python3 scripts/aria_cli.py lifestyle --focus nutrition
  python3 scripts/aria_cli.py voice "check my sleep last night"
  python3 scripts/aria_cli.py insights generate
  python3 scripts/aria_cli.py insights list --days 7
  python3 scripts/aria_cli.py conversation show
  python3 scripts/aria_cli.py conversation clear
  python3 scripts/aria_cli.py tools get_lifestyle_dashboard

By default calls the running dev server (FORGE_API_BASE_URL, default http://127.0.0.1:3001).
Use --local to invoke the Lambda handler in-process (no server required).
"""

from __future__ import annotations

import argparse
import json
import os
import sys
import urllib.error
import urllib.request
from pathlib import Path
from typing import Any

ROOT = Path(__file__).resolve().parents[1]
API_DIR = ROOT / "backend" / "api"
DEFAULT_USER = os.environ.get("FORGE_USER_ID", "local-dev-user")
API_BASE = os.environ.get("FORGE_API_BASE_URL", "http://127.0.0.1:3001").rstrip("/")
TIMEOUT = int(os.environ.get("FORGE_ARIA_TIMEOUT", "120"))


def _ensure_local_path() -> None:
    sys.path[:0] = [str(API_DIR)]


def _local_event(method: str, path: str, body: dict | None = None, query: dict | None = None) -> dict:
    payload: dict[str, Any] = {
        "requestContext": {"http": {"method": method, "path": path}},
        "queryStringParameters": query or {},
    }
    if body is not None:
        payload["body"] = json.dumps(body)
    return payload


def _http_request(method: str, path: str, body: dict | None = None) -> tuple[int, dict]:
    url = f"{API_BASE}{path}"
    data = json.dumps(body).encode("utf-8") if body is not None else None
    headers = {"Content-Type": "application/json"}
    req = urllib.request.Request(url, data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=TIMEOUT) as resp:
            return resp.status, json.loads(resp.read().decode("utf-8"))
    except urllib.error.HTTPError as exc:
        raw = exc.read().decode("utf-8") or "{}"
        try:
            payload = json.loads(raw)
        except json.JSONDecodeError:
            payload = {"message": raw}
        return exc.code, payload


def _local_request(method: str, path: str, body: dict | None = None, query: dict | None = None) -> tuple[int, dict]:
    _ensure_local_path()
    from handler import handler  # noqa: WPS433

    response = handler(_local_event(method, path, body, query), None)
    status = int(response.get("statusCode", 500))
    raw_body = response.get("body") or "{}"
    try:
        payload = json.loads(raw_body)
    except json.JSONDecodeError:
        payload = {"message": raw_body}
    return status, payload


def request(method: str, path: str, body: dict | None = None, query: dict | None = None, *, local: bool) -> tuple[int, dict]:
    if query:
        query_str = "&".join(f"{k}={v}" for k, v in query.items())
        path = f"{path}?{query_str}" if query_str else path
    if local:
        return _local_request(method, path.split("?")[0], body, query)
    return _http_request(method, path.split("?")[0], body)


def _print_json(payload: dict) -> None:
    print(json.dumps(payload, indent=2, default=str))


def _print_answer(payload: dict, key: str = "answer") -> None:
    if key in payload and payload[key]:
        print(payload[key])
        return
    if "message" in payload and isinstance(payload["message"], dict):
        print(payload["message"].get("content", ""))
        return
    if "analysis" in payload:
        print(payload["analysis"])
        return
    if "plan" in payload:
        print(payload["plan"])
        return
    _print_json(payload)


def cmd_status(args: argparse.Namespace) -> int:
    code, payload = request("GET", "/health", local=args.local)
    if code != 200:
        print(f"Health check failed ({code})", file=sys.stderr)
        _print_json(payload)
        return 1
    aria = payload.get("aria", {})
    print("ARIA status")
    print(f"  backend:   {aria.get('backend', 'unknown')}")
    print(f"  chat:      {aria.get('chatModel', 'n/a')}")
    print(f"  analysis:  {aria.get('analysisModel', 'n/a')}")
    print(f"  backup:    {aria.get('backupModel', 'n/a')}")
    print(f"  features:  {', '.join(aria.get('features', []))}")
    return 0


def cmd_chat(args: argparse.Namespace) -> int:
    body = {"content": args.message, "threadId": args.thread}
    code, payload = request("POST", "/aria/chat", body, local=args.local)
    if code == 503:
        print("ARIA unavailable (configure ARIA_BACKEND / API keys).", file=sys.stderr)
        _print_json(payload)
        return 1
    if code != 200:
        print(f"Chat failed ({code})", file=sys.stderr)
        _print_json(payload)
        return 1
    _print_answer(payload)
    if args.verbose and payload.get("toolCallsMade"):
        print("\n[tools]", json.dumps(payload["toolCallsMade"], indent=2))
    return 0


def cmd_analyze(args: argparse.Namespace) -> int:
    body = {"question": args.question, "thinkingBudget": args.thinking_budget}
    code, payload = request("POST", "/aria/analyze", body, local=args.local)
    if code != 200:
        print(f"Analyze failed ({code})", file=sys.stderr)
        _print_json(payload)
        return 1
    _print_answer(payload, key="analysis")
    return 0


def cmd_plan(args: argparse.Namespace) -> int:
    body = {"focus": args.focus}
    code, payload = request("POST", "/aria/plan", body, local=args.local)
    if code != 200:
        print(f"Plan failed ({code})", file=sys.stderr)
        _print_json(payload)
        return 1
    _print_answer(payload, key="plan")
    return 0


def cmd_lifestyle(args: argparse.Namespace) -> int:
    body = {"focus": args.focus}
    code, payload = request("POST", "/aria/lifestyle", body, local=args.local)
    if code != 200:
        print(f"Lifestyle coach failed ({code})", file=sys.stderr)
        _print_json(payload)
        return 1
    _print_answer(payload, key="coaching")
    return 0


def cmd_voice(args: argparse.Namespace) -> int:
    body = {"transcript": args.transcript}
    code, payload = request("POST", "/aria/voice", body, local=args.local)
    if code != 200:
        print(f"Voice failed ({code})", file=sys.stderr)
        _print_json(payload)
        return 1
    _print_answer(payload)
    return 0


def cmd_insights(args: argparse.Namespace) -> int:
    if args.action == "generate":
        code, payload = request("POST", "/aria/insights/generate", {}, local=args.local)
    else:
        code, payload = request("GET", "/aria/insights", query={"days": str(args.days)}, local=args.local)
    if code != 200:
        print(f"Insights failed ({code})", file=sys.stderr)
        _print_json(payload)
        return 1
    insights = payload.get("insights", [])
    if not insights:
        print("No insights returned.")
        return 0
    for i, insight in enumerate(insights, 1):
        title = insight.get("title", "Insight")
        priority = insight.get("priority", "medium")
        rec = insight.get("recommendation", "")
        print(f"{i}. [{priority}] {title}")
        if rec:
            print(f"   → {rec}")
    return 0


def cmd_conversation(args: argparse.Namespace) -> int:
    if args.action == "clear":
        code, payload = request("DELETE", "/aria/conversation", query={"threadId": args.thread}, local=args.local)
    else:
        code, payload = request("GET", "/aria/conversation", query={"threadId": args.thread}, local=args.local)
    if code != 200:
        print(f"Conversation failed ({code})", file=sys.stderr)
        _print_json(payload)
        return 1
    if args.action == "clear":
        print(f"Cleared thread '{args.thread}'.")
        return 0
    messages = payload.get("messages", [])
    if not messages:
        print(f"Thread '{args.thread}' is empty.")
        return 0
    for msg in messages:
        role = msg.get("role", "?")
        content = msg.get("content", "")
        if isinstance(content, list):
            content = " ".join(
                block.get("text", "") for block in content if isinstance(block, dict)
            )
        print(f"[{role}] {content}\n")
    return 0


def cmd_tools(args: argparse.Namespace) -> int:
    _ensure_local_path()
    from aria_tools import handle_tool_call  # noqa: WPS433

    tool_input: dict[str, Any] = {}
    if args.tool_input:
        tool_input = json.loads(args.tool_input)
    try:
        result = handle_tool_call(DEFAULT_USER, args.tool_name, tool_input)
    except Exception as exc:
        print(f"Tool error: {exc}", file=sys.stderr)
        return 1
    _print_json(result if isinstance(result, dict) else {"result": result})
    return 0


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Forge ARIA CLI")
    parser.add_argument(
        "--local",
        action="store_true",
        help="Invoke handler in-process instead of HTTP (no dev server required)",
    )
    parser.add_argument("--verbose", "-v", action="store_true", help="Show tool calls and extra metadata")

    sub = parser.add_subparsers(dest="command", required=True)

    sub.add_parser("status", help="Show ARIA configuration from /health")

    chat = sub.add_parser("chat", help="Send a chat message to ARIA")
    chat.add_argument("message", help="User message")
    chat.add_argument("--thread", default="current", help="Conversation thread id")

    analyze = sub.add_parser("analyze", help="Run deep analysis with extended thinking")
    analyze.add_argument("question", help="Analysis question")
    analyze.add_argument("--thinking-budget", type=int, default=10000, dest="thinking_budget")

    plan = sub.add_parser("plan", help="Generate today's workout/recovery plan")
    plan.add_argument("--focus", default="auto", choices=["auto", "workout", "recovery", "nutrition"])

    lifestyle = sub.add_parser("lifestyle", help="Lifestyle coaching (nutrition, wellbeing, holistic)")
    lifestyle.add_argument("--focus", default="holistic", choices=["nutrition", "wellbeing", "holistic"])

    voice = sub.add_parser("voice", help="Process a voice transcript")
    voice.add_argument("transcript", help="Spoken query text")

    insights = sub.add_parser("insights", help="Generate or list proactive insights")
    insights.add_argument("action", choices=["generate", "list"])
    insights.add_argument("--days", type=int, default=7)

    conversation = sub.add_parser("conversation", help="Show or clear conversation history")
    conversation.add_argument("action", choices=["show", "clear"])
    conversation.add_argument("--thread", default="current")

    tools = sub.add_parser("tools", help="Call an ARIA tool directly (no LLM)")
    tools.add_argument("tool_name", help="Tool name, e.g. get_lifestyle_dashboard")
    tools.add_argument("--input", dest="tool_input", default="", help='JSON tool input, e.g. \'{"days": 7}\'')

    return parser


def main() -> int:
    parser = build_parser()
    args = parser.parse_args()
    handlers = {
        "status": cmd_status,
        "chat": cmd_chat,
        "analyze": cmd_analyze,
        "plan": cmd_plan,
        "lifestyle": cmd_lifestyle,
        "voice": cmd_voice,
        "insights": cmd_insights,
        "conversation": cmd_conversation,
        "tools": cmd_tools,
    }
    return handlers[args.command](args)


if __name__ == "__main__":
    sys.exit(main())