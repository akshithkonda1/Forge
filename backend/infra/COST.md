# Forge AWS cost control

Plan-only. **No apply.** Bedrock stays off (`aria_bedrock_enabled` default
false). Scout stays off (`enable_scout` default false). The CloudWatch
dashboard stays off (`enable_cost_dashboard` default false — $3/month).

## Token audit

Every production Converse call goes through `BedrockGateway.converse`
(`backend/infra/lambda/ai_router.py`). That function now refuses to build a
client when Bedrock is off, when `is_aria_paused()` is true (including SSM
fail-paused), or when the per-user daily cap is exhausted.

| Call site | Entry | Prompt shape (approx.) | `max_tokens` | Notes |
| --- | --- | --- | --- | --- |
| `POST /ai/chat` | `generate_response_live` → `_default_converse` | System: persona + one specialist + learning law + security (~1.5–2.5k tok). User: ground-truth block capped at 4k chars + isolated message. | **512** (was 700) | Deterministic pass first. One Converse. Voice tool uses this path with a 150-token voice instruction. |
| `POST /ai/router` | `AIRouter.route` | Short router system (~80 tok) + question + package previews now capped at **6k chars** / **1kB** preview. | **512** default, hard cap **800** (was 1000 uncapped) | Starts **one** model. Escalates only on timeout. Optional consensus is a **second** Converse if two models answer — the redundant cost. |
| `/coach/*` | `_safe_route` → `AIRouter` | Same as router + coach context block | same | Pause-gated at the handler. Falls back if Bedrock is off. |
| `POST /workouts/form-check` `mode=briefing` | `generate_coach_text` | `live_system_prompt` + briefing task + snapshot ≤4k chars | 512 | **Not** handler-gated (degraded path stays up). Gateway + `is_aria_paused()` still block Converse. |
| `POST /sleep/environment-check` | `generate_coach_vision` | Sleep specialist + image | 512 | Same: no Converse while paused. |
| `POST /ai/voice/tool` | `generate_response_live(voice_mode=True)` | Same as chat + 150-token voice cap | 512 | HTTP stays up; Converse does not. TTS (ElevenLabs / Fish) is outside AWS. |
| `POST /ai/archetype` | simrunner `bedrock_client` when live | Short JSON instruction | 700 (simrunner only) | Lambda wraps and falls back locally. |
| Scout `GrokBrain` | `plan` + `synthesize` | Plan ~200 tok out; synth 512 | 200 / **512** (was 700) | **Off** unless `enable_scout` and `aria_bedrock_enabled`. User-data no longer hardcodes Bedrock on. |
| SimRunner `bedrock_client.converse` | `--live` CLI only | Eval prompts | 700 | Not in the Lambda plan. Dummy orchestrator never calls it. |

**Not Bedrock:** `/ai/observe`, `/watch/aria/suggest`, `/chat/threads/current/messages`, weekly-review, intelligence, dashboard. No EventBridge, no cron, no warmer, no summarizer job.

**Redundant calls (still possible when Bedrock is on):**

1. Router consensus — one extra Converse after two successes.
2. Router timeout escalation — a second/third model.
3. Chat runs deterministic `generate_response` first (local, $0) then one live call.

Safe caching now in the gateway:

- **Response cache:** 120s in-process, identical (model, system, user, max_tokens). Skips images. Double-taps and identical router questions do not Converse again.
- **Prompt cache:** `cachePoint` on system prompts ≥ 4000 chars. Dropped automatically if Bedrock rejects the field.

## Pause = zero spend

`BedrockGateway.converse` is the choke point. Tests in
`backend/tests/test_aria_pause_zero_spend.py` mock the Bedrock client and
assert **zero** `converse` invocations when `ARIA_PAUSED=true` or SSM fails
paused — including chat, router, coach, form-check briefing, sleep
environment-check, and voice tool. `/health` and `/ai/voice/bootstrap` stay
up.

## Idle near zero

| Knob | Default | Why |
| --- | --- | --- |
| Lambda memory | 256 MB arm64 | Enough for JSON + one sleep image. Validation 128–512. |
| Lambda timeout | 15s | Matches HTTP API integration. Validation 5–20s. |
| Reserved concurrency | `null` | Free cap if set; **0 forbidden**. |
| Provisioned concurrency | forbidden | CI cheap-guard. |
| NAT / VPC endpoints / RDS | none | Lambda is not in a VPC. |
| Scout EC2 + EIP | `enable_scout=false` | Only always-on compute; allowlisted. |
| Log retention | **14d prod / 7d else** (was 30/14) | 7–14 day band. |
| CloudWatch dashboard | `enable_cost_dashboard=false` | $3/month if turned on. |
| Alarms | 7 standard | Inside the 10-alarm free tier. |
| CloudTrail | `create_cloudtrail=false` | Extra trails bill. |

## Visibility

Existing `aws_budgets_budget.spend_guard` ($25/mo, default on, first two
budgets free) now alerts at:

- 80% **ACTUAL**
- 100% **ACTUAL**
- 100% **FORECASTED**

`spend_guard_notification_email` stays empty for Akshith to fill in.
Optional `aws_cloudwatch_dashboard.cost_usage` is behind
`enable_cost_dashboard` (default false).

Per-user daily caps (env + Terraform, inert while Bedrock is off):

- `aria_daily_request_cap` default **40**
- `aria_daily_token_cap` default **20000** (reserves `max_tokens` before Converse)

## Monthly cost table

us-east-1 public list prices. Scripted arithmetic (not hand-added).
**Scout off. Dashboard off. CloudTrail off. Bedrock off unless the “on”
column.**

### Assumptions

- 30-day month.
- **10** API requests / user / day (dashboard, health, chat, writes).
- When Bedrock is on: **3** chats / user / day and **0.2** router calls / user / day.
- Chat: 1800 input + 400 output tokens. Router: 2500 + 400, 1.1 Converse/call (rare escalate/consensus).
- Model mix: 90% Claude Sonnet 5.5, 10% Claude Opus 5.5 (timeout / consensus).
- Lambda 256 MB arm64, 300 ms average.
- DynamoDB on-demand: 8 RRU + 2 WRU per API request.
- Logs ~2 KB / request; 7–14 day retention.
- Lambda always-free: 1M requests + 400k GB-s. Logs: first 5 GB ingest free.
- Cognito Essentials: 10k MAU free — all three scales sit inside that.

### Prices used

| Item | Rate | Source |
| --- | --- | --- |
| Lambda arm64 duration | $0.0000133334 / GB-s | [AWS Lambda pricing](https://aws.amazon.com/lambda/pricing/) |
| Lambda requests | $0.20 / 1M | same |
| HTTP API | $1.00 / 1M | [API Gateway pricing](https://aws.amazon.com/api-gateway/pricing/) |
| DynamoDB on-demand | $1.25 / 1M WRU, $0.25 / 1M RRU | [DynamoDB pricing](https://aws.amazon.com/dynamodb/pricing/) |
| CloudWatch Logs ingest | $0.50 / GB (first 5 GB free) | [CloudWatch pricing](https://aws.amazon.com/cloudwatch/pricing/) |
| CloudWatch dashboard | $3 / dashboard / month (flag off) | same |
| AWS Budgets (no actions) | first 2 free | [Budgets](https://aws.amazon.com/aws-cost-management/aws-budgets/) |
| Claude Sonnet 5.5 | $2 / $10 per 1M in/out | [Anthropic pricing](https://platform.claude.com/docs/en/about-claude/pricing); Bedrock list is on [Bedrock pricing](https://aws.amazon.com/bedrock/pricing/) |
| Claude Opus 5.5 | $5 / $25 per 1M in/out | same (Opus 5 family list) |

Bedrock Marketplace / CRIS can differ by a few percent from the Anthropic
list. Treat the “on” column as an order-of-magnitude, not an invoice.

### Estimate (USD / month)

| Users | API calls | Chats (if on) | Infra (Bedrock **off**) | Tokens (Bedrock **on**) | Total **off** | Total **on** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 5 | 1,500 | 450 | $0.01 | $4.27 | **$0.01** | **$4.28** |
| 100 | 30,000 | 9,000 | $0.17 | $85.49 | **$0.17** | **$85.66** |
| 1,000 | 300,000 | 90,000 | $1.65 | $854.91 | **$1.65** | **$856.56** |

Infra breakdown at 1,000 users: HTTP API $0.30, DynamoDB $1.35, Lambda $0
(still inside the always-free GB-s/request grants), logs $0 (0.57 GB < 5 GB
free).

**Paused:** token column is $0 — Converse never runs. Infra stays the
health/dashboard pennies.

**What would make this expensive:** `aria_bedrock_enabled=true` without the
daily cap, `enable_scout=true` (t4g.small + EIP ≈ mid-teens/month plus Grok
tokens), `enable_cost_dashboard=true` (+$3), a second CloudTrail, or
provisioned concurrency (CI-blocked).

Leave `spend_guard_notification_email` for Akshith. The $25 budget fires
before the 100-user Bedrock-on estimate.
