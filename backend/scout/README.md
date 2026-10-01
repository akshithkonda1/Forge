# ARIA Scout

The agentic research sidecar ARIA calls when a turn needs the open web. The process stays up. It does not search until the gate says the prompt is a lookup.

```
ARIA prompt ── gate.evaluate ── no ──▶ keep talking, Scout idle
                 │
                yes (scrubbed mission only)
                 ▼
EC2 t4g.small: Caddy → Scout :8088 → SearXNG
                         └─▶ Grok on Bedrock synthesizes, then the working set is dumped
```

## Gate

`backend/scout/gate.py` reads the prompt and flips Scout on only for a lookup ("look up", "what is", "latest on", evidence, weather). Coaching ("should I train") stays off. Crisis language stays off — guidance owns that path.

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
