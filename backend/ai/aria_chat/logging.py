"""Local JSONL session eval logs. Redact before write. Dummy-only."""

from __future__ import annotations

import hashlib
import json
import os
import re
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

SCHEMA_VERSION = 1
ENGINE = "dummy"

_PARTNER_NEEDLE = re.compile(
    r"(?i)\b(partner_cycle|partner_name|partner_phase|partner_day|"
    r"support_cycle|cycle:fertile|cycle:tww|cycle:bleeding)\b"
)
_SPOKEN_METRIC = re.compile(
    r"(?i)\b\d+(?:\.\d+)?\s*(bpm|ms|mmhg|hrv|kcal|spo2|acwr)\b"
)


def default_log_dir() -> Path:
    """Gitignored local dir. Override with ``ARIA_CHAT_LOG_DIR``."""
    env = (os.getenv("ARIA_CHAT_LOG_DIR") or "").strip()
    if env:
        return Path(env).expanduser()
    return REPO_ROOT / "backend" / "ai" / "chat_sessions"


def default_export_dir() -> Path:
    return REPO_ROOT / "backend" / "ai" / "aria_chat" / "fixtures"


def _collect_needles(payload: dict[str, Any], message: str) -> list[str]:
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
    # Dedup while preserving order.
    seen: set[str] = set()
    out: list[str] = []
    for item in needles:
        if item not in seen:
            seen.add(item)
            out.append(item)
    return out


def _scrub_string(text: str, needles: list[str]) -> str:
    cleaned = sanitize_user_memory_text(text) or str(text or "")
    for needle in needles:
        if needle:
            cleaned = cleaned.replace(needle, _BUSY_WINDOW_LABEL)
    cleaned = _DENIED_LIFESTYLE.sub("", cleaned)
    cleaned = _PARTNER_NEEDLE.sub("", cleaned)
    return re.sub(r"\s{2,}", " ", cleaned).strip()


def _scrub_obj(value: Any, needles: list[str]) -> Any:
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
    profile = ctx.get("profile") if isinstance(ctx.get("profile"), dict) else {}
    snapshot = {
        "domains": sorted(k for k, v in ctx.items() if v),
        "memory_enabled": bool(memory_enabled),
        "turn": int(turn),
        "seed": int(seed),
        "profile_goal": profile.get("primaryGoal") or profile.get("primary_goal"),
        "engine": ENGINE,
    }
    raw = json.dumps(snapshot, sort_keys=True, separators=(",", ":"))
    return "sha256:" + hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]


def build_record(
    *,
    session_id: str,
    turn_id: str,
    turn: int,
    seed: int,
    user_id: str,
    memory_enabled: bool,
    user_message: str,
    envelope: dict[str, Any],
    payload: dict[str, Any],
) -> dict[str, Any]:
    """Build a versioned JSONL row. Redact before the caller writes."""
    needles = _collect_needles(payload, user_message)
    clean_user = _scrub_string(user_message, needles)
    fusion = envelope.get("fusion") if isinstance(envelope.get("fusion"), dict) else {}
    brief = (
        envelope.get("contextualization")
        if isinstance(envelope.get("contextualization"), dict)
        else {}
    )
    card = envelope.get("card") if isinstance(envelope.get("card"), dict) else {}
    band = str(envelope.get("guidance_band") or "coach")
    stance = str(fusion.get("stance") or brief.get("stance") or "")
    reason = str(
        envelope.get("confidence_reason")
        or brief.get("reason")
        or fusion.get("evidence_key")
        or band
    )
    record = {
        "schema_version": SCHEMA_VERSION,
        "engine": ENGINE,
        "session_id": session_id,
        "turn_id": turn_id,
        "turn": int(turn),
        "seed": int(seed),
        "user_id": str(user_id or "local-founder"),
        "memory_enabled": bool(memory_enabled),
        "user_turn": clean_user,
        "stance": {
            "chosen": stance,
            "guidance_band": band,
            "reason": reason,
        },
        "reply": {
            "message": str(envelope.get("message") or ""),
            "prose_summary": str(envelope.get("prose_summary") or ""),
            "card_action": str(card.get("action") or card.get("recommendation") or ""),
        },
        "feedback": {"rating": None, "note": ""},
        "context_snapshot_ref": context_snapshot_ref(
            payload, memory_enabled=memory_enabled, turn=turn, seed=seed
        ),
        "timestamp": datetime.now(timezone.utc).isoformat(),
    }
    return _scrub_obj(record, needles)


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
) -> dict[str, Any] | None:
    """Set thumbs up/down + optional note on a prior turn. Local rewrite."""
    directory = Path(log_dir) if log_dir is not None else default_log_dir()
    if not directory.exists():
        return None
    paths: list[Path]
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
    note_clean = sanitize_user_memory_text(note) if note else None
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
            updated = row
            out.append(json.dumps(row, ensure_ascii=False))
            changed = True
        if changed:
            path.write_text("\n".join(out) + ("\n" if out else ""), encoding="utf-8")
            if updated is not None:
                return updated
    return updated


def export_session(
    session_id: str,
    *,
    dest: Path | None = None,
    log_dir: Path | None = None,
) -> Path:
    """Copy a sanitized session into repo fixtures (or ``dest``)."""
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
    # Re-scrub on export in case an older line slipped.
    lines = []
    for line in source.read_text(encoding="utf-8").splitlines():
        if not line.strip():
            continue
        try:
            row = json.loads(line)
        except json.JSONDecodeError:
            continue
        row = _scrub_obj(row, [])
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


def contains_spoken_metric_digits(text: str) -> bool:
    return bool(_SPOKEN_METRIC.search(text or ""))
