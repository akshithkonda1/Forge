"""Interactive Dummy-only ARIA chat. ``python -m backend.ai.aria_chat``."""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

from backend.ai import aria_cli
from . import logging as chatlog
from .session import ChatSession, ENGINE

_HELP = """Commands
  /up [turn_id]     thumbs up (default: last turn)
  /down [turn_id]   thumbs down (default: last turn)
  /note <text>      free-text note on the last (or given) turn
  /reset            new session; history cleared
  /memory off       memory-off — no notes / STM / last_insights / fusion
  /memory on        allow request-payload memory fields only (still no Dynamo)
  /export [path]    copy sanitized JSONL into fixtures (or path)
  /purge            delete local JSONL logs (memory-off does not do this)
  /help             this text
  /quit             leave
Dummy-only. Bedrock stays off. Logs go to backend/ai/chat_sessions/ (gitignored)
or $ARIA_CHAT_LOG_DIR.
"""


def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="python -m backend.ai.aria_chat",
        description="Dummy-only open-ended ARIA chat for local founder tuning.",
    )
    parser.add_argument("-p", "--profile", choices=sorted(aria_cli.PROFILES), default="depleted")
    parser.add_argument("--user-id", default="local-founder")
    parser.add_argument("--memory", choices=("on", "off"), default="on")
    parser.add_argument("--log-dir", default=None)
    parser.add_argument("--json", action="store_true", help="Print raw turn JSON.")
    parser.add_argument("-m", "--message", help="One shot, then exit.")
    parser.add_argument(
        "--context-file",
        help="JSON /ai/chat-shaped body instead of a built-in profile.",
    )
    parser.add_argument(
        "--serve",
        action="store_true",
        help="Local Dummy HTTP server. Refused unless ARIA_LOCAL_CHAT=1.",
    )
    parser.add_argument("--host", default="127.0.0.1")
    parser.add_argument("--port", type=int, default=8765)
    return parser


def _print_turn(message: str, result: dict, *, raw: bool) -> None:
    if raw:
        printable = {
            k: result[k]
            for k in (
                "turn_id",
                "turn",
                "seed",
                "engine",
                "guidance_band",
                "message",
                "prose_summary",
                "card_action",
                "memory_enabled",
            )
            if k in result
        }
        fusion = result.get("fusion") if isinstance(result.get("fusion"), dict) else {}
        printable["stance"] = fusion.get("stance")
        print(json.dumps(printable, indent=2))
        return
    stance = (result.get("fusion") or {}).get("stance") or ""
    band = result.get("guidance_band") or "coach"
    print(f"ARIA ▸ [{ENGINE} · {band}" + (f" · {stance}" if stance else "") + "]")
    print(result.get("message") or "")
    print(f"  (turn {result.get('turn_id')})")


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)
    if args.serve:
        from .endpoint import serve

        serve(host=args.host, port=args.port)
        return 0
    payload = None
    if args.context_file:
        payload = json.loads(Path(args.context_file).read_text(encoding="utf-8"))
    session = ChatSession(
        payload=payload,
        user_id=args.user_id,
        memory_enabled=args.memory == "on",
        log_dir=args.log_dir,
        profile=args.profile,
    )
    label = aria_cli.PROFILES.get(args.profile, {}).get("label", args.profile)
    print(
        f"ARIA Dummy chat · {label} · memory={'on' if session.memory_enabled else 'off'}"
    )
    print(f"engine={ENGINE} · logs={session.log_dir or chatlog.default_log_dir()}")
    print("Type a message, /help, or /quit. Bedrock stays off.")

    pending_note_turn: str | None = None

    def handle_command(line: str) -> bool:
        nonlocal pending_note_turn
        parts = line.split(maxsplit=2)
        cmd = parts[0].lower()
        arg1 = parts[1] if len(parts) > 1 else ""
        rest = parts[2] if len(parts) > 2 else ""
        if cmd in {"/quit", "/exit"}:
            return True
        if cmd == "/help":
            print(_HELP)
            return False
        if cmd == "/reset":
            session.reset()
            print(f"reset · session {session.session_id}")
            return False
        if cmd == "/memory":
            flag = arg1.strip().lower()
            if flag in {"off", "on"}:
                session.set_memory(flag == "on")
                print(f"memory {'on' if session.memory_enabled else 'off'}")
            else:
                print("usage: /memory off | /memory on")
            return False
        if cmd in {"/up", "/down"}:
            tid = arg1 or None
            row = session.rate("up" if cmd == "/up" else "down", turn_id=tid)
            pending_note_turn = (row or {}).get("turn_id") if row else (tid or session.last_turn_id)
            print(f"rated {cmd[1:]} · {pending_note_turn or 'no turn'}")
            return False
        if cmd == "/note":
            note = (arg1 + (" " + rest if rest else "")).strip()
            if not note:
                print("usage: /note <text>")
                return False
            tid = pending_note_turn or session.last_turn_id
            row = chatlog.set_feedback(
                tid or "",
                note=note,
                session_id=session.session_id,
                log_dir=session.log_dir,
            )
            print(f"note saved · {(row or {}).get('turn_id') or tid}")
            return False
        if cmd == "/export":
            dest = Path(arg1) if arg1 else None
            path = session.export(dest)
            print(f"exported {path}")
            return False
        if cmd == "/purge":
            n = session.purge()
            print(f"purged {n} log file(s)")
            return False
        print("unknown command — /help")
        return False

    def one(message: str) -> None:
        result = session.turn(message)
        _print_turn(message, result, raw=args.json)

    if args.message:
        one(args.message)
        return 0

    while True:
        try:
            line = input("\nyou ▸ ").strip()
        except (EOFError, KeyboardInterrupt):
            print()
            break
        if not line:
            continue
        if line.startswith("/"):
            if handle_command(line):
                break
            continue
        try:
            one(line)
        except Exception as exc:
            print(f"error: {exc}", file=sys.stderr)
    return 0
