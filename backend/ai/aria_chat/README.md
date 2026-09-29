# Dummy-only ARIA chat

Open-ended chat for tuning ARIA locally **before** Grok / Claude / Bedrock are
connected. Dummy is the only engine. Bedrock stays off.

Every turn still runs the product path:

`ingest (fuse_turn) → personal model (adapt) → stance → speak_guard`

The conversational layer sits on top. It does not bypass speak_guard, the
vitals / digit scrub, medical-boundary guidance (`classify_band` / refer-out /
911), or the no-metric-dump rules.

## Run

From the repo root:

```bash
python -m backend.ai.aria_chat
python -m backend.ai.aria_chat -p primed
python -m backend.ai.aria_chat -m "hey, how's it going?"
```

REPL commands: `/up` `/down` `/note <text>` `/reset` `/memory off` `/memory on`
`/export` `/help` `/quit`.

## Logs

Default directory: `backend/ai/chat_sessions/` (gitignored). Override with
`ARIA_CHAT_LOG_DIR` or use `~/.forge/aria_chat/` by pointing that env var.

Each session is a JSONL file. Schema `schema_version=1`, `engine=dummy`, plus
`seed` / `turn`, stance + guidance band + reason, reply (`message`,
`prose_summary`, `card_action`), a feedback hook, and a
`context_snapshot_ref` (no raw PII). Calendar titles and partner / cycle tokens
are redacted **before** write, even when memory is off.

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
compared to Dummy.

## Local HTTP endpoint

`POST /ai/chat/local` on the Lambda handler / `dev_server.py` is **refused**
unless `ARIA_LOCAL_CHAT=1` (or `FORGE_ARIA_LOCAL_CHAT=1`) **and** the
environment is not production-like. It routes only to Dummy. It never
constructs a Bedrock / Grok / Claude client.

```bash
ARIA_LOCAL_CHAT=1 ENVIRONMENT=local python backend/dev_server.py
```

## Memory

Multi-turn state comes **only** from the request / session `history` passed in
(`routes.aria._turn_from_history`). `/memory off` matches
`editable_memory.memory_enabled=False`: no notes, no `remember_short_term`, no
`last_insights`, no persisted fusion snapshot.

## What this is not

Not a live model. Not Bedrock. Not a new memory store. Not a change to
Terraform or AWS.
