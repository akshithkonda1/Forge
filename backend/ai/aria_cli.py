#!/usr/bin/env python3
"""ARIA engine — a literal, runnable driver.

Pick a user, ask a question, and watch ARIA reason over their data. This wraps
the deployed engine (`services/aria_engine`) so you can run the exact same
coaching core the Lambda runs behind `POST /ai/chat`, straight from a terminal.

Examples
--------
    # A depleted founder asks whether to train — offline, deterministic engine
    python -m backend.ai.aria_cli --profile depleted -m "should I train today?"

    # A primed athlete, voice mode (prose only, no card)
    python -m backend.ai.aria_cli -p primed -m "how's my recovery?" --voice

    # Your own context (the /ai/chat request body shape), from a file or stdin
    python -m backend.ai.aria_cli -m "how did I sleep?" --context-file ctx.json
    echo '{"context": {...}}' | python backend/aria_cli.py -m "..." --context-stdin

    # Live Claude reasoning on Bedrock (falls back to deterministic with no AWS)
    python -m backend.ai.aria_cli -p mixed -m "what should I do today?" --live

    # Redact a domain, interactive session, raw JSON, list the sample users
    python -m backend.ai.aria_cli -p depleted -m "..." --deny sleep,training
    python -m backend.ai.aria_cli -p primed --repl
    python -m backend.ai.aria_cli -p mixed -m "..." --json
    python -m backend.ai.aria_cli --list-profiles
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
from backend._paths import ensure_lambda_on_path

ensure_lambda_on_path()

from services import aria_engine  # noqa: E402


# --- Sample users ------------------------------------------------------------
#
# Each profile is a `/ai/chat`-shaped request body (the rich, camelCase context).
# They span the engine's main branches so the script is useful with zero setup.
PROFILES: dict[str, dict] = {
    "depleted": {
        "label": "Maya — founder, mid-cut, running on fumes",
        "blurb": "Low recovery, HRV falling, fragmented short sleep, high load → protect recovery.",
        "context": {
            "sleep": {"durationMinutes": 360, "deepMinutes": 45, "remMinutes": 70,
                      "efficiency": 0.82, "hrv": 44, "restingHR": 58, "nightsAvailable": 14},
            "readiness": {"hrv7DayTrend": -14, "hrv30DayBaseline": 60,
                          "recoveryScore": 47, "hrvDaysAvailable": 7},
            "training": {"lastWorkoutType": "strength", "lastWorkoutDurationMinutes": 65,
                         "hoursSinceLastWorkout": 16, "weeklyLoadScore": 88},
            "activity": {"steps3DayAvg": 6200, "activeCalories3DayAvg": 480},
            "chronotype": {"typicalSleepOnset": "00:30", "typicalWakeTime": "07:00",
                           "consistencyScore": 0.6},
            "profile": {"primaryGoal": "build-muscle", "experienceLevel": "intermediate",
                        "coachingStyle": "balanced"},
            "lifestyle": {"recentPatterns": ["late_caffeine", "high_stress_week"]},
        },
    },
    "primed": {
        "label": "Diego — endurance athlete, well recovered",
        "blurb": "Strong sleep, HRV above baseline, plenty of rest → green to push.",
        "context": {
            "sleep": {"durationMinutes": 470, "deepMinutes": 105, "remMinutes": 110,
                      "efficiency": 0.93, "hrv": 78, "restingHR": 48, "nightsAvailable": 21},
            "readiness": {"hrv7DayTrend": 6, "hrv30DayBaseline": 72,
                          "recoveryScore": 84, "hrvDaysAvailable": 14},
            "training": {"lastWorkoutType": "easy run", "lastWorkoutDurationMinutes": 40,
                         "hoursSinceLastWorkout": 40, "weeklyLoadScore": 55},
            "activity": {"steps3DayAvg": 11200, "activeCalories3DayAvg": 720},
            "profile": {"primaryGoal": "improve-endurance", "experienceLevel": "advanced",
                        "coachingStyle": "push-hard"},
        },
    },
    "mixed": {
        "label": "Priya — performance athlete, conflicting signals",
        "blurb": "Good sleep but a sharp HRV drop → signals diverge, calibrate intensity.",
        "context": {
            "sleep": {"durationMinutes": 460, "deepMinutes": 100, "remMinutes": 105,
                      "efficiency": 0.92, "hrv": 70, "restingHR": 50, "nightsAvailable": 14},
            "readiness": {"hrv7DayTrend": -12, "hrv30DayBaseline": 66,
                          "recoveryScore": 68, "hrvDaysAvailable": 7},
            "training": {"lastWorkoutType": "intervals", "lastWorkoutDurationMinutes": 55,
                         "hoursSinceLastWorkout": 20, "weeklyLoadScore": 74},
            "progress": {"workoutsCompleted30d": 19, "newPersonalRecords": 2,
                         "trainingLoadTrend": "rising"},
            "profile": {"primaryGoal": "athletic-performance", "experienceLevel": "advanced",
                        "coachingStyle": "data-driven"},
        },
    },
    "sparse": {
        "label": "Sam — new user, almost no data yet",
        "blurb": "Goal set but no sleep/HRV/activity → ARIA should ask, not guess.",
        "context": {
            "profile": {"primaryGoal": "lose-fat", "experienceLevel": "beginner",
                        "coachingStyle": "patient"},
        },
    },
}


def _load_body(args: argparse.Namespace) -> tuple[dict, str]:
    """Resolve the request body and a human label from the chosen source."""
    if args.context_stdin:
        return json.loads(sys.stdin.read()), "custom (stdin)"
    if args.context_file:
        return json.loads(Path(args.context_file).read_text(encoding="utf-8")), f"custom ({args.context_file})"
    if args.context_json:
        return json.loads(args.context_json), "custom (inline)"
    profile = PROFILES[args.profile]
    return {"context": profile["context"]}, profile["label"]


def _permissions(args: argparse.Namespace) -> aria_engine.DataPermissions:
    if args.permissions_json:
        return aria_engine.DataPermissions.from_payload(json.loads(args.permissions_json))
    payload: dict = {}
    if args.allow:
        payload["allow"] = [d.strip() for d in args.allow.split(",") if d.strip()]
    if args.deny:
        payload["deny"] = [d.strip() for d in args.deny.split(",") if d.strip()]
    return aria_engine.DataPermissions.from_payload(payload or None)


def respond(message: str, body: dict, *, voice: bool, live: bool,
            permissions: aria_engine.DataPermissions) -> dict:
    """Run the engine for one message and return ARIA's response envelope."""
    context = aria_engine.ARIAContext.from_payload(body)
    reason = aria_engine.generate_response_live if live else aria_engine.generate_response
    return reason(message, context, permissions=permissions, voice_mode=voice)


# --- Rendering ---------------------------------------------------------------

_RULE = "─" * 70


def render(message: str, envelope: dict, *, label: str) -> str:
    """Pretty-print ARIA's response for a terminal."""
    rtype = envelope.get("response_type", "?")
    conf = envelope.get("confidence")
    reason = envelope.get("confidence_reason") or ""
    head = f"ARIA · {label} · {rtype}"
    if conf is not None:
        head += f"  (confidence {conf:.2f}{' — ' + reason if reason else ''})"

    lines = [_RULE, head, _RULE, f"you ▸ {message}", "", envelope.get("message", "")]

    recommendation = envelope.get("recommendation")
    if recommendation:
        lines += ["", f"▸ recommendation: {recommendation}"]

    card = envelope.get("card")
    if isinstance(card, dict) and card:
        lines.append("")
        lines.append("▸ card")
        for key, value in card.items():
            lines.append(f"    {key}: {value}")

    actions = envelope.get("suggested_actions") or []
    if actions:
        lines += ["", "suggested: " + "  ·  ".join(actions)]

    restricted = envelope.get("restricted_domains") or []
    if restricted:
        lines.append("restricted: " + ", ".join(restricted))

    footer = f"model: {envelope.get('model', '?')}"
    if envelope.get("reasoning_source"):
        footer += f" · source: {envelope['reasoning_source']}"
    if envelope.get("reasoning_error"):
        footer += f" · live error: {envelope['reasoning_error']}"
    lines += [_RULE, footer]
    return "\n".join(lines)


# --- CLI ---------------------------------------------------------------------

def _build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(
        prog="aria",
        description="Run the ARIA coaching engine over a user's data.",
        formatter_class=argparse.RawDescriptionHelpFormatter,
    )
    parser.add_argument("-m", "--message", help="The user's question for ARIA.")
    parser.add_argument("-p", "--profile", choices=sorted(PROFILES), default="depleted",
                        help="Built-in sample user (default: depleted).")
    parser.add_argument("--context-file", help="Path to a JSON /ai/chat request body.")
    parser.add_argument("--context-json", help="Inline JSON /ai/chat request body.")
    parser.add_argument("--context-stdin", action="store_true", help="Read the JSON body from stdin.")
    parser.add_argument("--voice", action="store_true", help="Voice mode: prose only, no card.")
    parser.add_argument("--live", action="store_true",
                        help="Use the live Bedrock path (falls back to deterministic without AWS).")
    parser.add_argument("--allow", help="Comma-separated domains to allow (denies the rest).")
    parser.add_argument("--deny", help="Comma-separated domains to deny.")
    parser.add_argument("--permissions-json", help="Inline JSON permissions payload.")
    parser.add_argument("--json", action="store_true", help="Print the raw response envelope as JSON.")
    parser.add_argument("--repl", action="store_true", help="Interactive session over one user's data.")
    parser.add_argument("--list-profiles", action="store_true", help="List the built-in sample users.")
    return parser


def main(argv: list[str] | None = None) -> int:
    args = _build_parser().parse_args(argv)

    if args.list_profiles:
        for name in sorted(PROFILES):
            print(f"{name:<9} {PROFILES[name]['label']}\n          {PROFILES[name]['blurb']}")
        return 0

    body, label = _load_body(args)
    permissions = _permissions(args)

    def answer(message: str) -> None:
        envelope = respond(message, body, voice=args.voice, live=args.live, permissions=permissions)
        if args.json:
            print(json.dumps(envelope, indent=2))
        else:
            print(render(message, envelope, label=label))

    if args.repl:
        print(f"ARIA · {label}\nType a message (blank line or Ctrl-D to quit).")
        while True:
            try:
                message = input("\nyou ▸ ").strip()
            except EOFError:
                print()
                break
            if not message:
                break
            answer(message)
        return 0

    if not args.message:
        _build_parser().error("provide --message, or use --repl / --list-profiles")
    answer(args.message)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
