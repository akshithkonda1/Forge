"""Dummy-only chat turn: ingest → personal model → stance → conversation.

Pinned to ``dummy_orchestrator.respond(engine="lambda")`` through
``fuse_turn``, never the SimRunner stub. Multi-turn state comes only from
the request/session history (local ``_turn_from_history`` on sanitized turns).
Memory-off never reads notes, ``remember_short_term``, ``last_insights``,
or persisted fusion.
"""

from __future__ import annotations

import os
import time
import uuid
from types import SimpleNamespace
from typing import Any

from backend._paths import ensure_lambda_on_path

ensure_lambda_on_path()

from aria_core import aria_guidance_policy  # noqa: E402
from aria_core import speak_guard  # noqa: E402
from aria_core import state_read  # noqa: E402
from routes.aria import (  # noqa: E402
    _history_role,
    _history_text,
    sanitize_inbound_chat_payload,
)
from security import MAX_CHAT_MESSAGE_CHARS, sanitize_user_text  # noqa: E402
from services import editable_memory  # noqa: E402
from services import guidance  # noqa: E402
from backend.ai.simrunner.aria_simrunner.dummy_orchestrator import (  # noqa: E402
    ENGINE_LAMBDA,
    respond as dummy_respond,
)

from . import conversation
from . import install as install_mod
from . import logging as chatlog

ENGINE = "dummy"
SCHEMA_VERSION = chatlog.SCHEMA_VERSION
REDACTED_PLACEHOLDER = "[redacted]"


def _turn_from_history(history: Any) -> tuple[int, list[str]]:
    """Turn index and prior user texts from request/session history only.

    Copied from the 382 helper. ``routes.aria`` also defines a later
    ``_turn_from_history(body) -> int`` that shadows it after #380 merged.
    Dummy chat must keep the history-list contract.
    """
    if not isinstance(history, list) or not history:
        return 0, []
    prior: list[str] = []
    user_count = 0
    for item in history:
        text = _history_text(item)
        if not text:
            continue
        role = _history_role(item)
        if role in ("", "user", "human"):
            prior.append(text)
            user_count += 1
    return user_count, prior


def _sanitize_or_placeholder(text: str, needles: list[str] | None) -> str:
    """Sanitize before fuse/log. Never fall back to the raw secret text."""
    cleaned = chatlog.sanitize_logged_text(text, needles)
    return cleaned if cleaned else REDACTED_PLACEHOLDER


def _sanitize_history(history: list | None, needles: list[str] | None) -> list:
    """Sanitize every history text field before turn-index or Dummy prior_turns."""
    if not isinstance(history, list):
        return []
    out: list = []
    for item in history:
        if isinstance(item, str):
            out.append(_sanitize_or_placeholder(item, needles))
            continue
        if not isinstance(item, dict):
            continue
        row = dict(item)
        text = str(row.get("content") or row.get("message") or row.get("text") or "")
        cleaned = _sanitize_or_placeholder(text, needles)
        if "content" in row or not (row.get("message") or row.get("text")):
            row["content"] = cleaned
        elif "message" in row:
            row["message"] = cleaned
        else:
            row["text"] = cleaned
        out.append(row)
    return out


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


def _file_dummy_people(
    user_id: str,
    payload: dict[str, Any],
    *,
    memory_enabled: bool,
    safety_band: str,
) -> None:
    """Dummy/stub only. Remember-me off and SAFETY_LOCK_BANDS write nothing."""
    if not memory_enabled:
        return
    from services import coach_context

    coach_context.file_people_tags(
        user_id,
        payload,
        allow_ingest=True,
        safety_lock=safety_band in guidance.SAFETY_LOCK_BANDS,
    )


def _prepare_payload(payload: dict[str, Any], *, memory_enabled: bool) -> dict[str, Any]:
    raw = payload if isinstance(payload, dict) else {}
    clean = sanitize_inbound_chat_payload(raw)
    if not memory_enabled:
        clean = _strip_memory_fields(clean)
    return clean


def _last_assistant(history: list | None) -> str:
    if not isinstance(history, list):
        return ""
    for item in reversed(history):
        if not isinstance(item, dict):
            continue
        role = str(item.get("role") or item.get("speaker") or "").strip().lower()
        if role in {"assistant", "aria", "bot"}:
            return str(item.get("content") or item.get("message") or item.get("text") or "")
    return ""


def _ctx_from_payload(body: dict[str, Any]) -> SimpleNamespace:
    """Request-context scores for Iris speak. No second fuse, no Dynamo."""
    context = body.get("context") if isinstance(body.get("context"), dict) else {}
    sleep = context.get("sleep") if isinstance(context.get("sleep"), dict) else {}
    readiness = context.get("readiness") if isinstance(context.get("readiness"), dict) else {}
    training = context.get("training") if isinstance(context.get("training"), dict) else {}

    def _num(*keys: str, bag: dict) -> Any:
        for key in keys:
            value = bag.get(key)
            if isinstance(value, (int, float)):
                return value
        return None

    return SimpleNamespace(
        readiness=SimpleNamespace(
            recovery_score=_num("recoveryScore", "recovery_score", bag=readiness)
        ),
        training=SimpleNamespace(
            weekly_load_score=_num("weeklyLoadScore", "weekly_load_score", bag=training)
        ),
        sleep=SimpleNamespace(
            duration_minutes=_num("durationMinutes", "duration_minutes", bag=sleep)
        ),
    )


def _cpu_seconds() -> float | None:
    try:
        import resource

        return float(resource.getrusage(resource.RUSAGE_SELF).ru_utime)
    except Exception:
        return None


def _relationship_level(payload: dict[str, Any]) -> int:
    """Relationship level (1-10) from the Dummy payload; 1 when absent."""
    for source in (payload, payload.get("context") if isinstance(payload.get("context"), dict) else {}):
        raw = source.get("relationship_level") if isinstance(source, dict) else None
        try:
            return max(1, min(10, int(raw)))
        except (TypeError, ValueError):
            continue
    return 1


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
    install_pseudonym: str | None = None,
    config_dir: Any = None,
    last_rating: str | None = None,
    commit_sha: str | None = None,
    triage_topic: str | None = None,
) -> dict[str, Any]:
    """One Dummy chat turn. Never calls ``generate_response_live`` or Bedrock.

    ``triage_topic`` is the previous turn's ``safety.reply_topic`` — the same
    echo the app sends to ``/ai/chat`` — so a triage answer resolves the same
    way on Dummy as in production.
    """
    assert_dummy_engine(engine)
    started = time.perf_counter()
    cpu0 = _cpu_seconds()
    safe = sanitize_user_text(str(message or ""), max_chars=MAX_CHAT_MESSAGE_CHARS)
    if not safe:
        raise ValueError("message is required.")

    if memory_enabled is None:
        memory_enabled = True
    memory_enabled = bool(memory_enabled)
    mem_row = editable_memory.CompanionMemorySettings(memory_enabled=memory_enabled)
    memory_enabled = editable_memory.auto_ingest_allowed(mem_row)

    raw_payload = payload if isinstance(payload, dict) else {}
    needles = chatlog.collect_needles(raw_payload, safe)
    # Sanitize before keys and before write so replay from the log matches.
    # Empty sanitize must never restore the raw text (G).
    spoken_in = _sanitize_or_placeholder(safe, needles)
    body = _prepare_payload(raw_payload, memory_enabled=memory_enabled)
    body["message"] = spoken_in
    context = body.get("context")
    if isinstance(context, dict) and not (context.get("timestamp") or context.get("ts")):
        context = dict(context)
        context["timestamp"] = "2026-01-15T12:00:00Z"
        body["context"] = context
    # Sanitize first. Never hand raw turns to the route body helper, and
    # do not add history/recentTurns/messages fields that would be re-read raw.
    sanitized_history = _sanitize_history(history, needles)
    turn_index, prior = _turn_from_history(sanitized_history)
    last_spoken = _last_assistant(sanitized_history)
    prior_spoken = conversation.prior_spoken_from_history(sanitized_history)

    # Phrase key / turn seed from the per-install pseudonym, never a real uid.
    # Searched the repo first: no existing per-install id; see install.py.
    pseudonym = str(install_pseudonym or "").strip() or install_mod.load_or_create_pseudonym(
        config_dir
    )
    # Pseudonym + turn only. Dummy seed is a third sha256 input, never a raw uid.
    phrase = state_read.phrase_key(pseudonym, turn_index, seed)
    # Explicit seed wins inside turn_seed — that seed is the phrase_key above.
    turn_s = state_read.turn_seed(None, spoken_in, seed=phrase)

    ctx = _ctx_from_payload(body)
    pending_triage = guidance.parse_triage_topic(triage_topic)
    triage_token = guidance.triage_reply_topic(*pending_triage) if pending_triage else None
    guardrail = guidance.assess(
        spoken_in,
        triage_topic=triage_token,
        relationship_level=_relationship_level(raw_payload),
    )
    if guardrail is not None:
        # Safety copy is guidance.py only. Skip Dummy hypertune so a broken
        # orchestrator cannot replace the cardiac / CPR / crisis line.
        envelope = {
            "message": guardrail.message,
            "prose_summary": guardrail.prose,
            "guidance_band": guardrail.band,
            "emergency_escalation": guardrail.wants_escalation,
            "confidence_reason": guardrail.confidence_reason,
            "suggested_actions": list(guardrail.suggested_actions),
            "response_type": "clarification",
        }
        if guardrail.safety is not None:
            envelope["safety"] = guardrail.safety
    else:
        # Engine pin: Dummy chat always uses dummy_orchestrator.respond(engine="lambda")
        # through fuse_turn — never the SimRunner stub, even if ARIA_BEDROCK_ENABLED=true.
        row = dummy_respond(
            spoken_in,
            engine=ENGINE_LAMBDA,
            chat_payload=body,
            prior_turns=prior,
            seed=int(phrase),
            fuse_user_id="",
            load_learner=False,
        )
        envelope = dict(row)
        envelope.pop("user_id", None)
        if "guidance_band" not in envelope:
            envelope["guidance_band"] = guidance.classify_band(spoken_in)
    envelope = conversation.apply_conversation(
        envelope,
        spoken_in,
        ctx,
        seed=phrase,
        prior=prior,
        memory_enabled=memory_enabled,
        last_spoken=last_spoken,
        last_rating=str(last_rating or ""),
        prior_spoken=prior_spoken,
    )
    envelope = speak_guard.guard_envelope(envelope, topic=spoken_in)
    _file_dummy_people(
        user_id,
        body,
        memory_enabled=memory_enabled,
        safety_band=str(envelope.get("guidance_band") or ""),
    )
    if guardrail is None:
        # Same care line /ai/chat and the phone lead a coaching reply with.
        envelope = aria_guidance_policy.with_care_line(
            envelope,
            spoken_in,
            safety_band=str(envelope.get("guidance_band") or guidance.COACH),
        )

    wall_ms = int((time.perf_counter() - started) * 1000)
    cpu1 = _cpu_seconds()
    cpu_ms = int((cpu1 - cpu0) * 1000) if cpu0 is not None and cpu1 is not None else 0

    turn_id = f"{session_id or 'anon'}-{turn_index + 1:04d}-{uuid.uuid4().hex[:8]}"
    sid = session_id or f"sess-{uuid.uuid4().hex[:12]}"
    sha = str(commit_sha or chatlog.git_commit_sha() or chatlog._UNKNOWN_SHA)
    record = chatlog.build_record(
        session_id=sid,
        turn_id=turn_id,
        turn=turn_index,
        seed=phrase,
        install_pseudonym=pseudonym,
        memory_enabled=memory_enabled,
        user_message=spoken_in,
        envelope=envelope,
        payload=body,
        request_history=prior,
        needles=needles,
        wall_ms=wall_ms,
        cpu_ms=cpu_ms,
        thin=conversation.data_is_thin(ctx),
        small_talk=conversation.is_small_talk(spoken_in, prior),
        safety=conversation._safety_turn(spoken_in, ctx),
        number_ask=bool(conversation._NUMBER_ASK_RE.search(spoken_in)),
        ctx=ctx,
        commit_sha=sha,
    )
    log_path = None
    if persist_log:
        log_path = chatlog.append_record(record, log_dir=log_dir)

    card = envelope.get("card") if isinstance(envelope.get("card"), dict) else {}
    orch = envelope.get("orchestration") if isinstance(envelope.get("orchestration"), dict) else {}
    return {
        **envelope,
        "engine": ENGINE,
        "dummy_engine": orch.get("engine") or ENGINE_LAMBDA,
        "schema_version": envelope.get("schema_version") or "1.1",
        "log_schema_version": SCHEMA_VERSION,
        "session_id": sid,
        "turn_id": turn_id,
        "turn": turn_index,
        "seed": phrase,
        "turn_seed": turn_s,
        "memory_enabled": memory_enabled,
        "install_pseudonym": pseudonym,
        "user_turn_key": record["user_turn_key"],
        "commit_sha": record["commit_sha"],
        "log_path": str(log_path) if log_path else None,
        "log_record": record,
        "card_action": card.get("action") or card.get("recommendation"),
        "reasoning_source": "dummy-chat",
        "model": "lambda-deterministic",
        "needles": needles,
    }


def run_local_chat_turn(body: dict[str, Any], *, user_id: str) -> dict[str, Any]:
    """HTTP adapter for the optional local Dummy server. Dummy only."""
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
        triage_topic=payload.get("triage_topic"),
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
        install_pseudonym: str | None = None,
        config_dir: Any = None,
    ) -> None:
        from backend.ai import aria_cli

        if payload is None:
            profile_row = aria_cli.PROFILES.get(profile) or aria_cli.PROFILES["depleted"]
            payload = {"context": profile_row["context"]}
        self.payload = payload
        self.user_id = user_id
        self.memory_enabled = bool(memory_enabled)
        self.log_dir = log_dir
        self.config_dir = config_dir if config_dir is not None else log_dir
        self.session_id = session_id or f"sess-{uuid.uuid4().hex[:12]}"
        self.install_pseudonym = install_pseudonym or install_mod.load_or_create_pseudonym(
            self.config_dir
        )
        self.history: list[dict[str, str]] = []
        # Pending voice-first triage question, echoed on the next turn.
        self.pending_triage: str | None = None
        self.last_turn_id: str | None = None
        self.last_rating: str | None = None
        self.log_path: str | None = None
        # Replay SHA once at session start — never a per-turn git call.
        self.commit_sha = chatlog.git_commit_sha()
        self.needles = chatlog.collect_needles(payload if isinstance(payload, dict) else {}, "")

    def turn(self, message: str) -> dict[str, Any]:
        result = run_turn(
            message,
            history=self.history,
            payload=self.payload,
            user_id=self.user_id,
            memory_enabled=self.memory_enabled,
            session_id=self.session_id,
            log_dir=self.log_dir,
            install_pseudonym=self.install_pseudonym,
            config_dir=self.config_dir,
            last_rating=self.last_rating,
            commit_sha=self.commit_sha,
            triage_topic=self.pending_triage,
        )
        # A triage question is answered exactly once; the next turn is fresh
        # unless this reply opened a new one.
        safety = result.get("safety") if isinstance(result.get("safety"), dict) else {}
        self.pending_triage = (
            str(safety.get("reply_topic") or "") or None
            if safety.get("phase") == "triage"
            else None
        )
        # Consume a thumbs-down warmer after exactly one reply.
        self.last_rating = None
        # Safety-session turns (emergency, triage, the triage answer) never
        # re-enter later rows via request_history: "no, it was an accident"
        # only reads as harmless on its own.
        band = str(result.get("guidance_band") or "")
        private = isinstance(result.get("safety"), dict) or band in (
            guidance.EMERGENCY,
            guidance.TRIAGE,
            guidance.CARE,
        )
        self.history.append(
            {
                "role": "user",
                "content": chatlog.REDACTED_USER_TURN if private else str(message),
            }
        )
        self.history.append({"role": "assistant", "content": str(result.get("message") or "")})
        self.last_turn_id = str(result.get("turn_id") or "")
        self.log_path = result.get("log_path")
        extra = result.get("needles") or []
        for item in extra:
            if item not in self.needles:
                self.needles.append(item)
        return result

    def reset(self) -> None:
        self.history = []
        self.pending_triage = None
        self.last_turn_id = None
        self.last_rating = None
        self.session_id = f"sess-{uuid.uuid4().hex[:12]}"

    def set_memory(self, enabled: bool) -> None:
        self.memory_enabled = bool(enabled)

    def rate(self, rating: str, note: str = "", turn_id: str | None = None) -> dict[str, Any] | None:
        tid = turn_id or self.last_turn_id
        if not tid:
            return None
        self.last_rating = str(rating or "").strip().lower() or None
        return chatlog.set_feedback(
            tid,
            rating=rating,
            note=note or None,
            session_id=self.session_id,
            log_dir=self.log_dir,
            needles=self.needles,
        )

    def export(self, dest: Any = None) -> Any:
        return chatlog.export_session(
            self.session_id,
            dest=dest,
            log_dir=self.log_dir,
            needles=self.needles,
        )

    def purge(self) -> int:
        return chatlog.purge_logs(self.log_dir)
