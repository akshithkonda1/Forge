"""Dummy-only chat turn: ingest → personal model → stance → conversation.

Multi-turn state comes only from the request/session history
(``routes.aria._turn_from_history``). Memory-off never reads notes,
``remember_short_term``, ``last_insights``, or persisted fusion.
"""

from __future__ import annotations

import os
import uuid
from typing import Any

from backend._paths import ensure_lambda_on_path

ensure_lambda_on_path()

from aria_core import speak_guard  # noqa: E402
from aria_core import state_read  # noqa: E402
from routes.aria import (  # noqa: E402
    _turn_from_history,
    sanitize_inbound_chat_payload,
)
from security import MAX_CHAT_MESSAGE_CHARS, sanitize_user_text  # noqa: E402
from services import aria_engine  # noqa: E402
from services import editable_memory  # noqa: E402
from services import fusion as fusion_mod  # noqa: E402
from services import guidance  # noqa: E402

from . import conversation
from . import logging as chatlog

ENGINE = "dummy"
SCHEMA_VERSION = chatlog.SCHEMA_VERSION


def _construct_remote_client(*_args: Any, **_kwargs: Any) -> None:
    """Never called on the Dummy path. Tests patch this to raise."""
    raise RuntimeError("Dummy chat refuses remote model clients")


def assert_dummy_engine(requested: str | None = None) -> str:
    """Routing gate: Dummy only. Never constructs Bedrock/Grok/Claude."""
    engine = (
        requested
        or os.getenv("ARIA_CHAT_ENGINE")
        or ENGINE
    ).strip().lower()
    if engine in {"", "dummy", "lambda", "local"}:
        return ENGINE
    _construct_remote_client(engine)
    raise RuntimeError(f"aria_chat is Dummy-only; refused engine={engine!r}")


def _strip_memory_fields(payload: dict[str, Any]) -> dict[str, Any]:
    """Drop companion memory fields so memory-off cannot see them on the request."""
    clean = dict(payload)
    clean.pop("notes", None)
    clean.pop("memory", None)
    clean.pop("last_insights", None)
    clean.pop("lastInsights", None)
    context = clean.get("context")
    if isinstance(context, dict):
        context = dict(context)
        context.pop("last_insights", None)
        context.pop("lastInsights", None)
        context.pop("notes", None)
        context.pop("current_goals", None)
        context.pop("currentGoals", None)
        clean["context"] = context
    return clean


def _prepare_payload(payload: dict[str, Any], *, memory_enabled: bool) -> dict[str, Any]:
    raw = payload if isinstance(payload, dict) else {}
    clean = sanitize_inbound_chat_payload(raw)
    if not memory_enabled:
        clean = _strip_memory_fields(clean)
    return clean


def run_turn(
    message: str,
    *,
    history: list | None = None,
    payload: dict[str, Any] | None = None,
    user_id: str = "local-founder",
    memory_enabled: bool | None = None,
    seed: int | None = None,
    voice_mode: bool = False,
    session_id: str | None = None,
    log_dir: Any = None,
    engine: str | None = None,
    persist_log: bool = True,
) -> dict[str, Any]:
    """One Dummy chat turn. Never calls ``generate_response_live`` or Bedrock."""
    assert_dummy_engine(engine)
    safe = sanitize_user_text(str(message or ""), max_chars=MAX_CHAT_MESSAGE_CHARS)
    if not safe:
        raise ValueError("message is required.")

    if memory_enabled is None:
        memory_enabled = True
    memory_enabled = bool(memory_enabled)
    # Honor the same contract as editable_memory.auto_ingest_allowed without
    # reading Dynamo settings (that would be a memory read on Dummy chat).
    mem_row = editable_memory.CompanionMemorySettings(memory_enabled=memory_enabled)
    memory_enabled = editable_memory.auto_ingest_allowed(mem_row)

    body = _prepare_payload(payload or {}, memory_enabled=memory_enabled)
    body["message"] = safe
    # Stable clock so two identical Dummy turns do not drift on ctx.timestamp.
    context = body.get("context")
    if isinstance(context, dict) and not (context.get("timestamp") or context.get("ts")):
        context = dict(context)
        context["timestamp"] = "2026-01-15T12:00:00Z"
        body["context"] = context
    turn_index, prior = _turn_from_history(history)
    permissions = aria_engine.DataPermissions.from_payload(body.get("permissions"))

    # Empty fuse user_id when memory is off: skip load_body_snapshot + persona
    # Dynamo. Personal model still runs via generate_response (cold-start).
    fuse_uid = "" if not memory_enabled else ""
    fused = fusion_mod.fuse_turn(
        fuse_uid,
        body,
        permissions,
        persist=False,
        include_stored=False,
        load_learner=False,
    )
    ctx = fused.context
    phrase = state_read.phrase_key(
        ctx,
        safe,
        user_id=user_id,
        turn=turn_index,
        seed=seed,
    )
    envelope = aria_engine.generate_response(
        safe,
        ctx,
        permissions=permissions,
        voice_mode=voice_mode,
        persona=None,
        baselines=fused.baselines,
        seed=phrase,
    )
    sidecar = fused.fusion_sidecar()
    existing = envelope.get("fusion") if isinstance(envelope.get("fusion"), dict) else {}
    envelope["fusion"] = {**sidecar, **existing}
    if "guidance_band" not in envelope:
        envelope["guidance_band"] = guidance.classify_band(safe)

    envelope = conversation.apply_conversation(
        envelope,
        safe,
        ctx,
        seed=phrase,
        prior=prior,
    )
    envelope = speak_guard.guard_envelope(envelope, topic=safe)

    turn_id = f"{session_id or 'anon'}-{turn_index + 1:04d}-{uuid.uuid4().hex[:8]}"
    sid = session_id or f"sess-{uuid.uuid4().hex[:12]}"
    record = chatlog.build_record(
        session_id=sid,
        turn_id=turn_id,
        turn=turn_index,
        seed=phrase,
        user_id=user_id,
        memory_enabled=memory_enabled,
        user_message=safe,
        envelope=envelope,
        payload=body,
    )
    log_path = None
    if persist_log:
        log_path = chatlog.append_record(record, log_dir=log_dir)

    card = envelope.get("card") if isinstance(envelope.get("card"), dict) else {}
    return {
        **envelope,
        "engine": ENGINE,
        "schema_version": envelope.get("schema_version") or "1.1",
        "log_schema_version": SCHEMA_VERSION,
        "session_id": sid,
        "turn_id": turn_id,
        "turn": turn_index,
        "seed": phrase,
        "memory_enabled": memory_enabled,
        "user_id": user_id,
        "log_path": str(log_path) if log_path else None,
        "log_record": record,
        "card_action": card.get("action") or card.get("recommendation"),
        "reasoning_source": "dummy-chat",
        "model": "lambda-deterministic",
    }


def run_local_chat_turn(body: dict[str, Any], *, user_id: str) -> dict[str, Any]:
    """HTTP adapter for ``POST /ai/chat/local``. Dummy only."""
    payload = body if isinstance(body, dict) else {}
    assert_dummy_engine(payload.get("engine"))
    message = str(payload.get("message") or "")
    history = payload.get("history") if payload.get("history") is not None else payload.get("session_history")
    memory = payload.get("memory_enabled")
    if memory is None:
        memory = payload.get("memory")
    if isinstance(memory, str):
        memory = memory.strip().lower() not in {"0", "false", "off", "no"}
    elif memory is None:
        memory = True
    return run_turn(
        message,
        history=history if isinstance(history, list) else None,
        payload=payload,
        user_id=user_id,
        memory_enabled=bool(memory),
        seed=payload.get("seed"),
        voice_mode=bool(payload.get("voice_mode")),
        session_id=str(payload.get("session_id") or "") or None,
        persist_log=bool(payload.get("persist_log", True)),
    )


class ChatSession:
    """In-process Dummy chat. History is the only multi-turn store."""

    def __init__(
        self,
        *,
        payload: dict[str, Any] | None = None,
        user_id: str = "local-founder",
        memory_enabled: bool = True,
        log_dir: Any = None,
        session_id: str | None = None,
        profile: str = "depleted",
    ) -> None:
        from backend.ai import aria_cli

        if payload is None:
            profile_row = aria_cli.PROFILES.get(profile) or aria_cli.PROFILES["depleted"]
            payload = {"context": profile_row["context"]}
        self.payload = payload
        self.user_id = user_id
        self.memory_enabled = bool(memory_enabled)
        self.log_dir = log_dir
        self.session_id = session_id or f"sess-{uuid.uuid4().hex[:12]}"
        self.history: list[dict[str, str]] = []
        self.last_turn_id: str | None = None
        self.log_path: str | None = None

    def turn(self, message: str) -> dict[str, Any]:
        result = run_turn(
            message,
            history=self.history,
            payload=self.payload,
            user_id=self.user_id,
            memory_enabled=self.memory_enabled,
            session_id=self.session_id,
            log_dir=self.log_dir,
        )
        self.history.append({"role": "user", "content": str(message)})
        self.history.append({"role": "assistant", "content": str(result.get("message") or "")})
        self.last_turn_id = str(result.get("turn_id") or "")
        self.log_path = result.get("log_path")
        return result

    def reset(self) -> None:
        self.history = []
        self.last_turn_id = None
        self.session_id = f"sess-{uuid.uuid4().hex[:12]}"

    def set_memory(self, enabled: bool) -> None:
        self.memory_enabled = bool(enabled)

    def rate(self, rating: str, note: str = "", turn_id: str | None = None) -> dict[str, Any] | None:
        tid = turn_id or self.last_turn_id
        if not tid:
            return None
        return chatlog.set_feedback(
            tid,
            rating=rating,
            note=note or None,
            session_id=self.session_id,
            log_dir=self.log_dir,
        )

    def export(self, dest: Any = None) -> Any:
        return chatlog.export_session(
            self.session_id, dest=dest, log_dir=self.log_dir
        )
