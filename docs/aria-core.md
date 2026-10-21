# ARIA core

Production coaching logic lives in `backend/infra/lambda/aria_core/` (stdlib
only, SimRunner-importable). The Lambda zip is that `lambda/` tree. Bedrock
is **off** until `ARIA_BEDROCK_ENABLED` is set. Do not apply Terraform from
this document.

## Kill switch and budgets

These are unchanged and fail closed:

- `ARIA_PAUSED` / SSM pause: `BedrockGateway.converse` never runs. HTTP for
  chat/router/coach returns 503. `/health` stays up.
- Per-user daily cap: 40 requests / 20 000 tokens (`token_budget`). Reserved
  **before** Converse using `max_tokens`.
- `LIVE_MAX_TOKENS` / `DEFAULT_MAX_TOKENS` / `HARD_MAX_TOKENS` = **512**.
- `aria_bedrock_enabled` Terraform default remains false.

## Three-model suite

This is an escalation ladder by **compute and task complexity**, not
cheap-fast vs strong.

| Tier | Role | Exact id (code + Terraform fallback) | Router slot |
| --- | --- | --- | ---: |
| 1 | Default. Intent, short replies, insights, simple next move. | `global.anthropic.claude-sonnet-5-5` | 1 |
| 2 | More complex than Sonnet should handle alone (multi-domain fit, travel vs training). | `global.xai.grok-4.7` | 3 |
| 3 | Complex reasoning and planning (multi-week, many constraints). | `global.anthropic.claude-opus-5-5` | 2 |
| 4 | Most complex only. All three draft independently, then a Sonnet synthesis / consensus step. | all three + Sonnet finalizer | 1+2+3 |

Router slots stay 1 = Sonnet, 2 = Opus, 3 = Grok so
`scripts/update_model_ids.py` keeps family anchors. The ladder selects by
**family**, not slot order.

Chat (`generate_response_live`) uses the same classifier. Voice mode and
medical-safety turns stay on Tier 1. Package size never fans out models.

## Complexity classifier

`aria_core.complexity.classify_complexity` is local and deterministic.
It does **not** spend a model call to rank itself.

Signals (codes in `reasons`, never user text):

- question length
- plan intent / multi-constraint plan
- tradeoff / reconcile language
- multi-domain pairs (sleep×train, travel×train, …)
- context conflict (low readiness, short sleep, overreached)
- package count ≥ 3

Holds that cannot spend up the ladder:

- `voice_mode`
- `safety_hold_tier1` (diagnose / prescribe / emergency)
- `injection_hold_tier1`

Bands:

- score `< 3` → Tier 1
- score `≥ 3` → Tier 2
- score `≥ 8` → Tier 3
- score `≥ 10` **and** plan **and** tradeoff → Tier 4

Self-assess: Sonnet (or Grok) may bump **one** step if
`needs_escalation` is true **and** `confidence ≤ 0.45`. Never jumps to
ensemble. Timeout uses the same one-step bump. Escalation is logged via
`escalation_log` (tier, score, reason codes, model ids — no question
text, no health numbers).

## Per-tier prompts and structured output

Every live system prompt, every tier, includes:

1. ARIA identity + soul rails (`aria_core.soul`)
2. Security law (`security.AI_SECURITY_DIRECTIVE`, including memory /
   calendar / tool output as untrusted and health opt-in)
3. The tier responsibility from `aria_core.suite.TIER_RESPONSIBILITY`

Structured contract (router always; chat live overlay accepts it):

```json
{
  "answer": "user-visible text on rails",
  "confidence": 0.0,
  "needs_escalation": false,
  "escalation_reason": "short_code_no_pii"
}
```

Tier 4 drafts are independent. The synthesizer (`consensus_system_prompt`)
is a consensus finalizer: keep agreement, safest common ground on
conflict, no model names, no new facts. Drafts are wrapped as untrusted
tool output before synthesis.

## Rails, soul, memory

Identical on every tier:

- Lifestyle coach, not a doctor. Never diagnose / treat / prescribe.
- Never say “recovery”. Never shame. Never push past comfort.
- Name real progress when it is real. Anything medical → a doctor.
- Personalities (Coach / Friend / Drill Sergeant, or a fusion) are flavor
  only. Rails win.
- Memory: dreams and health_constraints stay out unless `shareHealth` /
  `shareDreams` **and** item `shareOptIn`. `clinical_data` is fail-closed
  unless the permission payload explicitly grants it.
- Untrusted isolation: user message, memory, calendar, contacts, tool
  output, package preview (`aria_core.untrusted.isolate`).
- Logs: `privacy.redact_for_log` strips secrets and raw health tokens.

`aria_core.rails.apply_to_envelope` sanitizes spoken fields after every
path, including the deterministic (Bedrock-off) envelope.

## Module map

| Module | Job |
| --- | --- |
| `aria_engine.py` | Deterministic envelope + live overlay |
| `complexity.py` | Classifier, self-assess, PII-free audit |
| `suite.py` | Roles, shared prefix, JSON parse, draft isolation |
| `soul.py` / `rails.py` | Personalities + output rails |
| `untrusted.py` / `privacy.py` | Isolation, health opt-in, log redaction |
| `ai_router.py` | `BedrockGateway.converse` choke point + ladder |

## Cost mix

Pinned in `backend/infra/COST.md` and `backend/infra/tests/test_cost_table.py`.

Expected traffic: **88% T1 / 8% T2 / 3.5% T3 / 0.5% T4**.

Per-request token cost at 1800/400 (chat): T1 $0.0076, T2 $0.0060,
T3 $0.0190, T4 $0.0402, blend **$0.008034** (was $0.00874 at 90/10
Sonnet/Opus). Monthly Bedrock-on tokens at 5 / 100 / 1,000 users:
**$3.90 / $78.03 / $780.29**.

## Tests

- `backend/tests/test_aria_complexity.py` — classifier vectors and router
  routing to each tier, including the all-three path
- `backend/tests/test_aria_adversarial.py` — injection, health, rails, authz
- `backend/tests/test_aria_suite_evals.py` — SimRunner lambda-vs-stub, voice
  check, rails
- `backend/tests/test_aria_engine.py` — chat live ensemble
- `backend/infra/tests/test_cost_table.py` — mix and monthly tables

## Owner decisions

1. Suite is Sonnet → Grok 4.7 → Opus → rare ensemble. Not cheap vs strong.
2. Classifier is deterministic + one-step self-assess. No extra ranker model.
3. Most traffic must resolve at Tier 1. Escalation is justified and logged
   without PII.
4. Rails / soul / memory filter are identical on every tier.
5. Bedrock stays off by default. No AWS apply from this work. Voice/TTS is
   a separate consolidation and is not changed here.
6. Slot ids stay 1/2/3 = Sonnet/Opus/Grok so model-id updater anchors hold.
