# ARIA core — architecture map

Genuinely stdlib-only reasoning lives in `backend/infra/lambda/aria_core/`.
SimRunner imports it directly. The Lambda zip is that same tree (`infra/main.tf`
`source_dir = lambda`), so production and Dummy grade one implementation.

Bedrock is **off** unless `ARIA_BEDROCK_ENABLED` is truthy. `ARIA_PAUSED`
(fail-paused) and the per-user daily cap (40 requests / 20k tokens) wrap every
Converse. `max_tokens` default is **512**.

This pass does not touch voice / TTS (`elevenlabs_voice.py`, `fish_audio_voice.py`,
`/ai/voice/*`).

## Module boundaries

| Concern | Module | Callers |
| --- | --- | --- |
| Untrusted text (user, memory, calendar, contacts, tool output) | `untrusted.py` | `security.py`, `aria_engine.build_user_prompt`, `ai_router` prompts |
| Spoken rails (coach not doctor, never diagnose/prescribe, never "recovery", no shame) | `safety_rails.py` | `speak_guard`, `coach_context`, router critic, chat/coach routes |
| Health opt-in (conditions on-device unless `shareHealth`) | `health_privacy.py` | `fusion.fuse_turn`, `/ai/chat` memory inject |
| Three-model policy (Scout / Reasoner / Critic, cost-aware) | `model_suite.py` | `ai_router`, `aria_engine.live_system_prompt`, evals |
| Deterministic coach | `aria_engine.generate_response` | `/ai/chat`, `/ai/observe`, Dummy `engine="lambda"` |
| Body + stance fusion | `fusion.py` | `/ai/chat`, `/ai/observe` |
| Medical bands (911 / triage / refer-out) | `guidance.py` | hot path, before any model |
| Epistemic honesty | `prompt_guard.py` | estimate, never a 502 |
| Kill switch | `aria_pause.py` (Lambda, not aria_core) | handler + `BedrockGateway.converse` |
| Token budget | `token_budget.py` | `BedrockGateway.converse` |

Personality (Coach / Friend / Drill Sergeant) is a **blend**, not a menu.
`safety_rails.blend_soul` + `docs/aria-behavioral-modes.md`. Fusion stance
(protect / proceed / fuel / clarify) still comes from `fusion.stance_for_plan`.

## Request path (`POST /ai/chat`)

1. Auth JWT (`extract_user_id`). Body `user_id` cannot override.
2. Size limits (`MAX_JSON_BODY_CHARS`, `MAX_CHAT_MESSAGE_CHARS`).
3. `sanitize_user_text` + lifestyle/calendar PII strip.
4. `guidance.assess` — safety bands never reach Bedrock.
5. `fusion.fuse_turn` — body snapshot + permissions + **health opt-in**.
6. `generate_response` (deterministic). Optional one Bedrock Converse via
   `generate_response_live` when the flag is on: Scout for short replies,
   Reasoner for plan/summary/recommendation. Local critic = `speak_guard` +
   `safety_rails`.
7. Memory inject filtered by `health_privacy`. Fail closed on pause / flag off.

## Request path (`POST /ai/router`)

1. Auth required. Bedrock flag + pause + daily cap.
2. Local intent (`model_suite.classify_intent`) — no Bedrock.
3. Launch **one** producer (Scout, or Reasoner for plan/summary).
4. Escalate to the other producer **only on timeout**.
5. Local critic always. Live Grok critic only when two producers disagree
   (low agreement) or local rails wiped the answer. Never a 3-wide race.
6. Untrusted question / context / package previews are delimited.

## Three-model roles

| Role | Default model | When it runs | Typical tokens |
| --- | --- | --- | --- |
| **Scout** | Claude Sonnet 5.5 | Default first pass; short / insight / greeting / recommendation | 1 Converse, `max_tokens` 512 |
| **Reasoner** | Claude Opus 5.5 | Plan / summary first; or Scout timeout | 1 Converse, 512 |
| **Critic** | Grok 4.7 (live) or local rails | Local every turn (free). Live only on low agreement / empty local rewrite | 0 or 1 Converse, 512 |

Weighted cost units used by evals: Scout **1.0**, Reasoner **2.5**, Critic **1.1**.
The old package-size race launched 1/2/3 producers plus a consensus Converse
on 2+ successes. Mixed traffic is cheaper under the new policy because the
9 GB → 3-model case is gone.

## Health and PII

- `shareHealth` default **false**. `clinical_data` is zeroed in fusion unless opted in.
- Adaptive memory: `health_constraints` / dreams need share flag **and** per-item `shareOptIn` (`aria_context_memory.server_context`).
- Partner/cycle prefixes and calendar titles stripped before persist (`sanitize_inbound_chat_payload`).
- Logs: handler never writes the request body. `health_privacy.redact_for_log` for any string that might be health.

## Fail closed

| Gate | Default |
| --- | --- |
| Bedrock | off |
| `ARIA_PAUSED` SSM error | paused |
| Daily cap | 40 req / 20k tokens |
| Missing auth | 401 |
| Safety band | deterministic envelope, no live rephrase |
| Bedrock / parse / hallucination | deterministic fallback |

## Tests

- Adversarial: `backend/tests/test_aria_adversarial.py`
- Policy / cost: `backend/tests/test_model_suite.py`
- Router: `backend/tests/test_ai_router.py`, `test_ai_router_gate.py`
- Evals: `backend/ai/simrunner/tests/test_model_suite_eval.py`
