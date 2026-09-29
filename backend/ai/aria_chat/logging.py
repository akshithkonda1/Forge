"""Local JSONL session eval logs. Redact before write. Dummy-only.

Schema v2 records engine, commit SHA, seed, hashed user+turn key, stance,
and per-turn telemetry as reason codes / counts only. Never a raw uid.
"""

from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from backend._paths import REPO_ROOT, ensure_lambda_on_path

ensure_lambda_on_path()

from routes.aria import (  # noqa: E402
    sanitize_inbound_chat_payload,
    sanitize_user_memory_text,
    _DENIED_LIFESTYLE,
    _BUSY_WINDOW_LABEL,
)

SCHEMA_VERSION = 2
ENGINE = "dummy"

ALLOWED_STANCE_INPUTS = frozenset({
    "protect",
    "proceed",
    "fuel",
    "clarify",
    "band_coach",
    "band_first_aid",
    "band_emergency",
    "band_refer_out",
    "thin_data",
    "small_talk",
    "safety_protect",
    "sleep_short",
    "load_high",
    "recovery_low",
    "number_ask",
})
ALLOWED_WAKE_REASONS = frozenset({"data_delta", "question", "digest", "always_on"})
ALLOWED_RESEARCH_HITS = frozenset({"hit", "miss"})

_PARTNER_NEEDLE = re.compile(
    r"(?i)\b(partner_cycle|partner_name|partner_phase|partner_day|"
    r"support_cycle|cycle:fertile|cycle:tww|cycle:bleeding)\b"
)
_SPOKEN_METRIC = re.compile(
    r"(?i)\b\d+(?:\.\d+)?\s*(bpm|ms|mmhg|hrv|kcal|spo2|acwr)\b"
)
_MEMORY_KEYS = frozenset({
    "memory_prompt_block",
    "persona",
    "recentPatterns",
    "recent_patterns",
    "last_insights",
    "lastInsights",
    "notes",
    "current_goals",
    "currentGoals",
    "memory",
})


def default_log_dir() -> Path:
    """Gitignored local dir. Override with ``ARIA_CHAT_LOG_DIR``."""
    env = (os.getenv("ARIA_CHAT_LOG_DIR") or "").strip()
    if env:
        return Path(env).expanduser()
    return REPO_ROOT / "backend" / "ai" / "chat_sessions"


def default_export_dir() -> Path:
    return REPO_ROOT / "backend" / "ai" / "aria_chat" / "fixtures"


def git_commit_sha() -> str:
    pinned = (os.getenv("ARIA_CHAT_COMMIT") or os.getenv("GITHUB_SHA") or "").strip()
    if pinned:
        return pinned[:40]
    try:
        out = subprocess.check_output(
            ["git", "rev-parse", "HEAD"],
            cwd=str(REPO_ROOT),
            text=True,
            timeout=3,
        )
        return (out or "").strip()[:40] or "unknown"
    except Exception:
        return "unknown"


def user_turn_key(pseudonym: str, turn: int) -> str:
    """Hashed install-pseudonym + turn. Never a raw user id."""
    raw = f"{pseudonym}|{int(turn)}"
    return "utk:" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def collect_needles(payload: dict[str, Any], message: str) -> list[str]:
    needles: list[str] = []
    events = payload.get("calendar_events") if isinstance(payload, dict) else None
    if isinstance(events, list):
        for event in events:
            if not isinstance(event, dict):
                continue
            for key in ("title", "summary", "name"):
                value = event.get(key)
                text = str(value or "").strip()
                if text and text != _BUSY_WINDOW_LABEL:
                    needles.append(text)
    blob = json.dumps(payload, default=str) + " " + str(message or "")
    for match in _PARTNER_NEEDLE.finditer(blob):
        needles.append(match.group(0))
    seen: set[str] = set()
    out: list[str] = []
    for item in needles:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def sanitize_logged_text(text: str, needles: list[str] | None = None) -> str:
    """Same inbound sanitizer ingest uses, then needle + partner scrub."""
    raw = str(text or "")
    clean_payload = sanitize_inbound_chat_payload({"message": raw})
    cleaned = sanitize_user_memory_text(str(clean_payload.get("message") or raw)) or ""
    return _scrub_string(cleaned, list(needles or []))


def _scrub_string(text: str, needles: list[str]) -> str:
    cleaned = sanitize_user_memory_text(text) or str(text or "")
    for needle in needles:
        if needle:
            cleaned = cleaned.replace(needle, _BUSY_WINDOW_LABEL)
    cleaned = _DENIED_LIFESTYLE.sub("", cleaned)
    cleaned = _PARTNER_NEEDLE.sub("", cleaned)
    return re.sub(r"\s{2,}", " ", cleaned).strip()


def _drop_memory_keys(value: Any) -> Any:
    if isinstance(value, dict):
        return {
            str(k): _drop_memory_keys(v)
            for k, v in value.items()
            if str(k) not in _MEMORY_KEYS
        }
    if isinstance(value, list):
        return [_drop_memory_keys(item) for item in value]
    return value


def _scrub_obj(value: Any, needles: list[str]) -> Any:
    value = _drop_memory_keys(value)
    if isinstance(value, str):
        return _scrub_string(value, needles)
    if isinstance(value, list):
        return [_scrub_obj(item, needles) for item in value]
    if isinstance(value, dict):
        return {str(k): _scrub_obj(v, needles) for k, v in value.items()}
    return value


def context_snapshot_ref(
    payload: dict[str, Any],
    *,
    memory_enabled: bool,
    turn: int,
    seed: int,
) -> str:
    """Stable hash of a sanitized, PII-free context snapshot for later replay."""
    clean = sanitize_inbound_chat_payload(payload if isinstance(payload, dict) else {})
    ctx = clean.get("context") if isinstance(clean.get("context"), dict) else {}
    snapshot = {
        "domains": sorted(k for k, v in ctx.items() if v),
        "memory_off": not bool(memory_enabled),
        "turn": int(turn),
        "seed": int(seed),
        "engine": ENGINE,
    }
    raw = json.dumps(snapshot, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def stance_inputs_from(
    envelope: dict[str, Any],
    *,
    thin: bool = False,
    small_talk: bool = False,
    safety: bool = False,
    number_ask: bool = False,
    ctx: Any = None,
) -> list[str]:
    """Reason codes only — never raw vitals or free text."""
    codes: list[str] = []
    fusion = envelope.get("fusion") if isinstance(envelope.get("fusion"), dict) else {}
    brief = (
        envelope.get("contextualization")
        if isinstance(envelope.get("contextualization"), dict)
        else {}
    )
    stance = str(fusion.get("stance") or brief.get("stance") or "")
    if stance in {"protect", "proceed", "fuel", "clarify"}:
        codes.append(stance)
    band = str(envelope.get("guidance_band") or "coach")
    band_code = f"band_{band}"
    if band_code in ALLOWED_STANCE_INPUTS:
        codes.append(band_code)
    if thin:
        codes.append("thin_data")
    if small_talk:
        codes.append("small_talk")
    if safety:
        codes.append("safety_protect")
    if number_ask:
        codes.append("number_ask")
    recovery = getattr(getattr(ctx, "readiness", None), "recovery_score", None)
    load = getattr(getattr(ctx, "training", None), "weekly_load_score", None)
    sleep_min = getattr(getattr(ctx, "sleep", None), "duration_minutes", None)
    if isinstance(recovery, (int, float)) and recovery < 55:
        codes.append("recovery_low")
    if isinstance(load, (int, float)) and load >= 80:
        codes.append("load_high")
    if isinstance(sleep_min, (int, float)) and sleep_min < 400:
        codes.append("sleep_short")
    return [c for c in codes if c in ALLOWED_STANCE_INPUTS]


def empty_agent_telemetry() -> dict[str, Any]:
    """Dummy has no agent / research / LLM path. Log zeros, not inventions."""
    return {
        "agents_woken": [],
        "agent_writes": [],
        "research": [],
        "subagent_spawn_count": 0,
        "max_depth": 0,
        "budget_exhausted": False,
        "llm_calls": 0,
        "network_calls": 0,
    }


def build_record(
    *,
    session_id: str,
    turn_id: str,
    turn: int,
    seed: int,
    install_pseudonym: str,
    memory_enabled: bool,
    user_message: str,
    envelope: dict[str, Any],
    payload: dict[str, Any],
    request_history: list[str] | None = None,
    needles: list[str] | None = None,
    wall_ms: int | None = None,
    cpu_ms: int | None = None,
    thin: bool = False,
    small_talk: bool = False,
    safety: bool = False,
    number_ask: bool = False,
    ctx: Any = None,
) -> dict[str, Any]:
    """Build a versioned JSONL row. Redact before the caller writes."""
    found = list(needles or []) or collect_needles(payload, user_message)
    clean_user = sanitize_logged_text(user_message, found)
    history = [sanitize_logged_text(item, found) for item in (request_history or [])]
    fusion = envelope.get("fusion") if isinstance(envelope.get("fusion"), dict) else {}
    brief = (
        envelope.get("contextualization")
        if isinstance(envelope.get("contextualization"), dict)
        else {}
    )
    card = envelope.get("card") if isinstance(envelope.get("card"), dict) else {}
    band = str(envelope.get("guidance_band") or "coach")
    stance = str(fusion.get("stance") or brief.get("stance") or "")
    orch = envelope.get("orchestration") if isinstance(envelope.get("orchestration"), dict) else {}
    engine = str(orch.get("engine") or ENGINE)
    telemetry = empty_agent_telemetry()
    record = {
        "schema_version": SCHEMA_VERSION,
        "engine": engine if engine in {ENGINE, "lambda", "dummy"} else ENGINE,
        "commit_sha": git_commit_sha(),
        "session_id": session_id,
        "turn_id": turn_id,
        "turn": int(turn),
        "seed": int(seed),
        "install_pseudonym": str(install_pseudonym),
        "user_turn_key": user_turn_key(install_pseudonym, turn),
        "memory_off": not bool(memory_enabled),
        "user_turn": clean_user,
        "request_history": history,
        "stance": stance,
        "guidance_band": band,
        "stance_inputs": stance_inputs_from(
            envelope,
            thin=thin,
            small_talk=small_talk,
            safety=safety,
            number_ask=number_ask,
            ctx=ctx,
        ),
        "reply": {
            "message": str(envelope.get("message") or ""),
            "prose_summary": str(envelope.get("prose_summary") or ""),
            "card_action": str(card.get("action") or card.get("recommendation") or ""),
        },
        "feedback": {"rating": None, "note": ""},
        "context_snapshot_ref": context_snapshot_ref(
            payload, memory_enabled=memory_enabled, turn=turn, seed=seed
        ),
        **telemetry,
        "wall_ms": int(wall_ms) if wall_ms is not None else 0,
        "cpu_ms": int(cpu_ms) if cpu_ms is not None else 0,
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    return _scrub_obj(record, found)


def session_path(session_id: str, log_dir: Path | None = None) -> Path:
    directory = Path(log_dir) if log_dir is not None else default_log_dir()
    directory.mkdir(parents=True, exist_ok=True)
    return directory / f"{session_id}.jsonl"


def append_record(record: dict[str, Any], *, log_dir: Path | None = None) -> Path:
    """Write one already-redacted JSONL line."""
    path = session_path(str(record.get("session_id") or "session"), log_dir)
    with path.open("a", encoding="utf-8") as handle:
        handle.write(json.dumps(record, ensure_ascii=False) + "\n")
    return path


def set_feedback(
    turn_id: str,
    *,
    rating: str | None = None,
    note: str | None = None,
    session_id: str | None = None,
    log_dir: Path | None = None,
    needles: list[str] | None = None,
) -> dict[str, Any] | None:
    """Set thumbs up/down + optional note on a prior turn. Local rewrite."""
    directory = Path(log_dir) if log_dir is not None else default_log_dir()
    if not directory.exists():
        return None
    if session_id:
        paths = [directory / f"{session_id}.jsonl"]
    else:
        paths = sorted(directory.glob("*.jsonl"))
    rating_norm = None
    if rating is not None:
        key = str(rating).strip().lower()
        if key in {"up", "1", "+", "good"}:
            rating_norm = "up"
        elif key in {"down", "0", "-", "bad"}:
            rating_norm = "down"
        else:
            rating_norm = key
    note_clean = sanitize_logged_text(note, needles) if note else None
    updated: dict[str, Any] | None = None
    for path in paths:
        if not path.is_file():
            continue
        lines = path.read_text(encoding="utf-8").splitlines()
        changed = False
        out: list[str] = []
        for line in lines:
            if not line.strip():
                continue
            try:
                row = json.loads(line)
            except json.JSONDecodeError:
                out.append(line)
                continue
            if str(row.get("turn_id") or "") != str(turn_id):
                out.append(line)
                continue
            feedback = row.get("feedback") if isinstance(row.get("feedback"), dict) else {}
            if rating_norm is not None:
                feedback["rating"] = rating_norm
            if note_clean is not None:
                feedback["note"] = note_clean
            row["feedback"] = feedback
            row = _scrub_obj(row, list(needles or []))
            updated = row
            out.append(json.dumps(row, ensure_ascii=False))
            changed = True
        if changed:
            path.write_text("\n".join(out) + ("\n" if out else ""), encoding="utf-8")
            if updated is not None:
                return updated
    return updated


def _export_row_ok(row: dict[str, Any]) -> dict[str, Any]:
    """Re-run redaction. Drop memory keys. Keep speech digit-free."""
    row = _scrub_obj(row, [])
    reply = row.get("reply") if isinstance(row.get("reply"), dict) else {}
    for key in ("message", "prose_summary"):
        text = str(reply.get(key) or "")
        if _SPOKEN_METRIC.search(text) or (
            re.search(r"\d", text.replace("911", ""))
        ):
            reply[key] = re.sub(r"\d+(?:\.\d+)?", "", text)
            reply[key] = re.sub(r"\s{2,}", " ", reply[key]).strip()
    row["reply"] = reply
    return row


def export_session(
    session_id: str,
    *,
    dest: Path | None = None,
    log_dir: Path | None = None,
) -> Path:
    """Copy a sanitized session into repo fixtures (or ``dest``). Re-redacts."""
    source = session_path(session_id, log_dir)
    if not source.is_file():
        raise FileNotFoundError(f"no session log at {source}")
    target_dir = Path(dest) if dest is not None else default_export_dir()
    if target_dir.suffix == ".jsonl":
        target = target_dir
        target.parent.mkdir(parents=True, exist_ok=True)
    else:
        target_dir.mkdir(parents=True, exist_ok=True)
        target = target_dir / source.name
    lines = []
    for line in source.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        row = _export_row_ok(row)
        lines.append(json.dumps(row, ensure_ascii=False))
    target.write_text("\n".join(lines) + ("\n" if lines else ""), encoding="utf-8")
    return target


def iter_records(session_id: str, *, log_dir: Path | None = None) -> list[dict[str, Any]]:
    path = session_path(session_id, log_dir)
    if not path.is_file():
        return []
    rows: list[dict[str, Any]] = []
    for line in path.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            rows.append(json.loads(line))
        except json.JSONDecodeError:
            continue
    return rows


def purge_logs(log_dir: Path | None = None) -> int:
    """Delete local JSONL session logs. Memory-off does not do this."""
    directory = Path(log_dir) if log_dir is not None else default_log_dir()
    if not directory.exists():
        return 0
    removed = 0
    for path in directory.glob("*.jsonl"):
        path.unlink()
        removed += 1
    return removed


def contains_spoken_metric_digits(text: str) -> bool:
    return bool(_SPOKEN_METRIC.search(text or ""))
