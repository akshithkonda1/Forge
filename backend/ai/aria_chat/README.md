# Dummy-only ARIA chat

Open-ended chat for tuning ARIA locally **before** Grok / Claude / Bedrock are
connected. Dummy is the only engine. Bedrock stays off.

Every turn still runs the product path:

`ingest (fuse_turn) → personal model (adapt) → stance → speak_guard`

The conversational layer sits on top. It does not bypass speak_guard, the
vitals / digit scrub, medical-boundary guidance (`classify_band` / refer-out /
911), or the no-metric-dump rules.

Chat mode pins `dummy_orchestrator.respond(engine="lambda")` through
`fuse_turn`, not the SimRunner stub, even when `ARIA_BEDROCK_ENABLED=true`.

## Voice bar (Iris)

1. **Friend first.** A warm, witty take plus one useful thought, usually 1–3
   sentences, at most one question back. No lecture paragraphs.
2. **Small talk stays small talk.** Movies, the dog, a bad day get a real
   answer on that topic. Do not pivot to health every turn; tie back to habits
   only when natural, at most about 1 turn in 3.
3. **No numbers in speech ever** — vitals, scores, hours, %, ACWR — even when
   the user asks for the number. Give the direction in words and point to the
   card for figures.
4. **Never a doctor.** No diagnose / treat / cure, and no medical terms in
   speech (`overtraining`, `fatigue`, `insomnia`, `deficiency`). Refer-out and
   emergency still escalate as they do today.
5. **Honest.** With thin data say so plainly ("I don't have enough to go on
   yet"), never a made-up read. Never claim to be human. With memory off, never
   say "I remember" about anything outside this chat.
6. **No robot tells.** No "Great question", "As an AI", or "I'd be happy to".
   No button text read aloud, no capitalized labels, no capital letter after a
   dash, and no two consecutive turns opening the same way.
7. **Follow the thread.** Later turns build on earlier user turns in the
   history instead of restarting cold.

## Run

From the repo root:

```bash
python -m backend.ai.aria_chat
python -m backend.ai.aria_chat -p primed
python -m backend.ai.aria_chat -m "hey, how's it going?"
```

REPL commands: `/up` `/down` `/note <text>` `/reset` `/memory off` `/memory on`
`/export` `/purge` `/help` `/quit`.

## Logs

Default directory: `backend/ai/chat_sessions/` (gitignored). Override with
`ARIA_CHAT_LOG_DIR` or use `~/.forge/aria_chat/` by pointing that env var.

Each session is a JSONL file. Schema `schema_version=3`, `engine=dummy` (lambda
path), plus `commit_sha`, `seed`, hashed `user_turn_key`, `install_pseudonym`,
`stance`, `stance_inputs` (reason codes only), reply (`message`,
`prose_summary`, `card_action`), a feedback hook, and a
`context_snapshot_ref` (no raw PII). Per-turn telemetry is reason codes and
counts only: `agents_woken` (`kind` + `wake_reason`), `agent_writes`
(key names + `elapsed_ms` as a measured float, or `null` with `reason: untimed_dummy` — never `0`), `research` (`topic_id` + hit/miss; empty in Dummy),
spawn count / depth / `budget_exhausted`, `llm_calls`, `network_calls`,
`wall_ms`, `cpu_ms`. Calendar titles and partner / cycle tokens
are redacted **before** write, even when memory is off. No raw user id is
logged. `/purge` deletes local logs; `/memory off` does not.

Rate a turn after the fact:

```
/down
/note too stiff — I wanted more warmth
```

or `set_feedback(turn_id, rating="down", note="...")`.

## Export fixtures

```
/export
```

writes a sanitized copy into `backend/ai/aria_chat/fixtures/` so the same
user turns + context snapshot can later be replayed against Grok / Claude and
compared to Dummy. Export re-runs redaction.

## Local HTTP endpoint

Optional and **local-only**. It lives in `backend/ai/aria_chat/endpoint.py`.
It is **not** registered in Terraform, API Gateway, or the Lambda handler.

Refused unless `ARIA_LOCAL_CHAT=1` (or `FORGE_ARIA_LOCAL_CHAT=1`) **and** the
environment is not production-like. It routes only to Dummy.

```bash
ARIA_LOCAL_CHAT=1 ENVIRONMENT=local python -m backend.ai.aria_chat --serve
```

## Memory

Multi-turn state comes **only** from the request / session `history` passed in
(`routes.aria._turn_from_history`). `/memory off` matches
`editable_memory.memory_enabled=False`: no notes, no `remember_short_term`, no
`last_insights`, no persisted fusion snapshot. Phrase keys use a per-install
pseudonym, never a real uid.

## What this is not

Not a live model. Not Bedrock. Not a new memory store. Not a change to
Terraform or AWS.
