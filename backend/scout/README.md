# ARIA Scout

The agentic research sidecar ARIA calls when a turn needs the open web. The process stays up. It does not search until the gate says yes: anything health related, or a lookup on any other topic.

```
ARIA prompt ── gate.evaluate ── no ──▶ keep talking, Scout idle
                 │
                yes (scrubbed mission only)
                 ▼
EC2 t4g.small: Caddy → Scout :8088 → SearXNG
                         └─▶ Grok on Bedrock synthesizes, then the working set is dumped
```

## Gate

`backend/scout/gate.py` reads the prompt and flips Scout on when:

- **It is health related.** Symptoms, body parts, injuries, medications, supplements, nutrition, sleep, stress, heat. No lookup wording is needed ("I have a fever"), and one keyword is enough (`fever`).
- **It is a lookup on anything else** ("look up", "what is", "latest on", evidence, weather), with at least two keywords.

It stays off for questions about the user's own data ("how did I sleep", "my HRV", "should I train"). If the same prompt also asks for outside facts, it turns on.

**Crisis language is researched too.** For an emergency ("chest pain", "can't breathe", "overdose"), the decision carries "If this is an emergency, call 911 now." For self-harm, it carries a 988 line, and Scout searches for crisis support instead of the user's words. The server always puts that line at the end of the answer. It shortens the answer so the line survives the clients' 420-character clip. If Scout is rate limited or the lookup fails, the reply is still a 200 that carries the safety line and a fixed source.

A query-only body is a handoff (`from_handoff`): the caller already decided, so no lookup wording is needed. It is still scrubbed and still gets the safety line.

A yes is a mission brief: scrubbed keywords, preferred sources, `retain: false`. Names after a relationship word, numbers, and contacts never enter the brief.

- `POST /gate` returns that decision and does not search.
- `POST /research` runs the same gate. `activate: false` means no SearXNG call and no Bedrock call.

## Dump

`retention.working_set` holds the mission and pages only for the run, then clears them. The 6h cache key is a hash of the scrubbed keywords, not the prompt and not the page text. Callers must not write the brief into sleep, training, nutrition, or durable memory.

## Turn it on

```bash
cd backend/infra
export TF_VAR_scout_shared_key="$(openssl rand -hex 32)"   # never commit this
terraform apply -var enable_scout=true -var spend_guard_limit_usd=45
terraform output scout_research_url
```

- Grok needs Bedrock model access for `global.xai.grok-4.7`. The Scout box enables Bedrock for itself only.
- About $17/month before tokens (t4g.small). SearXNG stays self-hosted; synthesis stays on Bedrock.
- No SSH. Use SSM Session Manager.

## Run locally

```bash
python -m unittest backend.tests.test_scout_gate
python -m unittest backend.tests.test_scout
```
