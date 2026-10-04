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

- **It is health related.** Symptoms, body parts, injuries, medications, supplements, nutrition, sleep, heat. No lookup wording is needed ("I have a fever"), and one unambiguous keyword is enough (`fever`). Bare `stress`, `stressed`, `anxious`, and `anxiety` do **not** wake Scout on their own and do not get a 988 line or chip.
- **It is a lookup on anything else** ("look up", "what is", "latest on", evidence, weather), with at least two keywords.

It stays off for questions about the user's own data ("how did I sleep", "my HRV", "should I train"). If the same prompt also asks for outside facts, it turns on.

Ambiguous everyday words do not wake Scout alone: `back`, `period`, `cold`, `hot`, `condition`, `drug`, `iron`, `sugar`, `mood`, `heart`, and similar. They count only with another health word, a lookup cue, or an activity word ("my back hurts", "iron supplement", "is it too hot to run"). "I'm back from work", "hot take", "what a period of my life", and "cold brew is great" stay off.

## Safety tiers

Crisis wording is **not** kept in `gate.py`. The gate asks `backend/infra/lambda/aria_core/guidance.py` for the Scout tier and reuses that copy. Templates are fixed — never model-written, never filled from the user's words — and they work with Bedrock off. Chat `classify_band()` wins: a chat EMERGENCY is always the Scout emergency tier, never urgent. Suggested actions use exactly `Call 911` and `Call or text 988` (the app's tap-to-call chips). Safety searches use one fixed query per kind (for example `medical emergency warning signs`). The stress tier never sets `safety_lock`.

| Tier | Example | Opens with | 911 | 988 | Search | Lock |
|---|---|---|---|---|---|---|
| Emergency now | chest pain, can't breathe, stroke signs, overdose, passed out, seizure, heavy bleeding | `Call 911 now. This needs emergency help right away.` + steps | yes | no | yes, fixed query | yes |
| Self-harm with intent/plan | "I want to die" | `Call or text 988 now.` plus call 911 if in danger right now | yes | yes | **no** | yes |
| Self-harm thoughts, no plan | "I don't want to be here" | glad-you-told-me 988 offer | no | yes | **no** | yes |
| Urgent, not emergency | fever for several days; chest tightness after a workout that went away | `Let's get this checked today by a doctor or urgent care.` + that symptom's `Call 911 if` | no | no | yes, fixed query | no |
| Stress | panic attack, or burnout with a hopeless cue | coaching first, then `If it ever feels like too much, 988 is there to call or text, not just for a crisis.` | no | yes | yes, fixed query | **no** |
| Ordinary health | "I have a fever" | no safety line | no | no | yes | no |

The emergency, urgent, and self-harm lines are the **first** thing in the answer, so the clients' 420-character front-clip (`AriaWebParsers.maxEvidenceChars` in `AriaWebEvidence.swift`, `web_research._clip`, `gate.CLIENT_EVIDENCE_CHARS`) cannot drop them. The stress line is **after** the coaching or research text. Self-harm tiers return the reviewed reply with the 988 source and never start a Scout run. If a crisis request is rate limited or the lookup fails, the reply is still a **200** that carries the safety line and a fixed https source.

Chat `assess()` / `classify_band()` are unchanged: ARIA still speaks the existing emergency and 988 copy. `heavy bleeding` stays a Scout-only extra so the Swift lexicon does not need a cycle-word exclusion.

A query-only body is a handoff (`from_handoff`): the caller already decided, so no lookup wording is needed. It is still scrubbed and still gets the safety line.

A yes is a mission brief: scrubbed keywords, preferred sources, `retain: false`. Names after a relationship word, numbers, and contacts never enter the brief.

- `POST /gate` returns that decision and does not search.
- `POST /research` runs the same gate. `activate: false` means no SearXNG call and no Bedrock call. Self-harm returns the fixed reply without searching.

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
