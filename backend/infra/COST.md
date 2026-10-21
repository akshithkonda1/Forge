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
| `POST /ai/router` | `AIRouter.route` | Shared rails + per-tier role + isolated question. Package previews capped at **6k chars** / **1kB**. | **512** default and hard cap (was 800) | Complexity ladder. One model on T1–T3. T4 is three drafts + Sonnet synthesis. Timeout/self-assess may add **one** extra Converse, never a jump to ensemble. |
| `/coach/*` | `_safe_route` → `AIRouter` | Same as router + coach context block | same | Pause-gated at the handler. Falls back if Bedrock is off. |
| `POST /workouts/form-check` `mode=briefing` | `generate_coach_text` | `live_system_prompt` + briefing task + snapshot ≤4k chars | 512 | **Not** handler-gated (degraded path stays up). Gateway + `is_aria_paused()` still block Converse. |
| `POST /sleep/environment-check` | `generate_coach_vision` | Sleep specialist + image | 512 | Same: no Converse while paused. |
| `POST /ai/voice/tool` | `generate_response_live(voice_mode=True)` | Same as chat + 150-token voice cap | 512 | HTTP stays up; Converse does not. TTS (ElevenLabs / Fish) is outside AWS. |
| `POST /ai/archetype` | simrunner `bedrock_client` when live | Short JSON instruction | 700 (simrunner only) | Lambda wraps and falls back locally. |
| Scout `GrokBrain` | `plan` + `synthesize` | Plan ~200 tok out; synth 512 | 200 / **512** (was 700) | **Off** unless `enable_scout` and `aria_bedrock_enabled`. User-data no longer hardcodes Bedrock on. |
| SimRunner `bedrock_client.converse` | `--live` CLI only | Eval prompts | 700 | Not in the Lambda plan. Dummy orchestrator never calls it. |

**Not Bedrock:** `/ai/observe`, `/watch/aria/suggest`, `/chat/threads/current/messages`, weekly-review, intelligence, dashboard. No EventBridge, no cron, no warmer, no summarizer job.

**Redundant calls (still possible when Bedrock is on):**

1. Tier 4 ensemble — three independent drafts plus one Sonnet synthesis. Classifier-gated (~0.5% of traffic), never package-size fan-out.
2. Timeout or Sonnet self-assess — at most **one** extra Converse, one step up the ladder.
3. Chat runs deterministic `generate_response` first (local, $0) then the classified live call.

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
- Chat: 1800 input + 400 output tokens. Router: 2500 + 400. The mix below already prices T4's four Converse calls; there is no extra 1.1× multiplier.
- Escalation mix (compute × complexity, not cheap-vs-strong): **88% / 8% / 3.5% / 0.5%** = Tier 1 Sonnet / Tier 2 Grok 4.7 / Tier 3 Opus / Tier 4 ensemble.
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
| Grok 4.7 Global CRIS | $2 / $6 per 1M in/out | [Grok 4.7 model card](https://docs.aws.amazon.com/bedrock/latest/userguide/model-card-xai-grok-4-7.html) (Geo is $2.20 / $6.60; Scout default is `global.xai.grok-4.7`) |
| t4g.small Linux us-east-1 | $0.0168 / hour | [EC2 on-demand](https://aws.amazon.com/ec2/pricing/on-demand/) |
| Public IPv4 (EIP) | $0.005 / hour | [VPC pricing](https://aws.amazon.com/vpc/pricing/) |
| EBS gp3 | $0.08 / GB-month | [EBS pricing](https://aws.amazon.com/ebs/pricing/) |

Bedrock Marketplace / CRIS can differ by a few percent from the Anthropic
list. Treat the “on” column as an order-of-magnitude, not an invoice.

### Per-tier token cost (USD / request)

Same 1800/400 chat and 2500/400 router sizes. Tier 4 = Sonnet + Grok + Opus
drafts plus a Sonnet synthesis at the same size (four Converse calls).

| Tier | Model | Chat | Router | Expected mix |
| --- | --- | ---: | ---: | ---: |
| 1 | Claude Sonnet 5.5 `global.anthropic.claude-sonnet-5-5` | $0.0076 | $0.0090 | 88% |
| 2 | Grok 4.7 `global.xai.grok-4.7` | $0.0060 | $0.0074 | 8% |
| 3 | Claude Opus 5.5 `global.anthropic.claude-opus-5-5` | $0.0190 | $0.0225 | 3.5% |
| 4 | Ensemble (3 drafts + Sonnet synth) | $0.0402 | $0.0479 | 0.5% |
| Blend | 88/8/3.5/0.5 | **$0.008034** | **$0.009539** | 100% |

Cheaper than the previous 90/10 Sonnet/Opus blend ($0.00874 chat, $0.011385
router with a 1.1× escalate/consensus factor) because default traffic stays
on Sonnet, Grok output is $6/1M not $10, and ensemble is rare.

### Estimate (USD / month)

| Users | API calls | Chats (if on) | Infra (Bedrock **off**) | Tokens (Bedrock **on**) | Total **off** | Total **on** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| 5 | 1,500 | 450 | $0.01 | $3.90 | **$0.01** | **$3.91** |
| 100 | 30,000 | 9,000 | $0.17 | $78.03 | **$0.17** | **$78.20** |
| 1,000 | 300,000 | 90,000 | $1.65 | $780.29 | **$1.65** | **$781.94** |

Infra breakdown at 1,000 users: HTTP API $0.30, DynamoDB $1.35, Lambda $0
(still inside the always-free GB-s/request grants), logs $0 (0.57 GB < 5 GB
free).

**Paused:** token column is $0 — Converse never runs. Infra stays the
health/dashboard pennies.

**What would make this expensive:** `aria_bedrock_enabled=true` without the
daily cap, `enable_scout=true` (the box is ~$17/month before tokens — see
the Scout handoff scenario below), `enable_cost_dashboard=true` (+$3), a
second CloudTrail, or provisioned concurrency (CI-blocked).

Leave `spend_guard_notification_email` for Akshith. The $25 budget fires
before the 100-user Bedrock-on estimate **without** Scout. With Scout on,
raise `spend_guard_limit_usd` (README suggests 45) — the box alone is most
of the $25 guard.

## Scout handoff scenario

`enable_scout=true`. Combined with the ARIA ~3 chats/day baseline above.
Scripted arithmetic (same rounding as the baseline table). Dashboard and
CloudTrail stay off.

### Return format used

**Short cited digest — not a full research summary.** Scout already clips
the payload:

- `GrokBrain` / `_SYNTH_SYSTEM` (`backend/scout/brain.py`): JSON with
  **one or two plain sentences**, ≤4 points, short caveats.
- Stored brief: `answer[:400]`, each point `text[:320]`, ≤3 caveats `[:200]`.
- Clients then front-clip the answer to **420 characters**:
  `gate.CLIENT_EVIDENCE_CHARS`, `web_research._clip` /
  `web_research.evidence_from_brief`, `AriaWebParsers.maxEvidenceChars`
  (`AriaWebEvidence.swift` / `scoutBrief`).

ARIA’s follow-up therefore consumes ~420 characters of evidence plus up to
four source titles — not the pages Scout read (those stay on the box;
`retention.working_set` is dumped after the run).

### Assumptions

- **1 complex handoff / user / week** (example: a user with Asperger’s
  asking about dementia studies). Unique weekly questions, so the 6h
  `BriefCache` misses.
- 30-day month ⇒ **30/7 ≈ 4.286** handoffs / user / month.
- Loop (`backend/scout/agent.py`): **plan → ≤3 SearXNG queries → read ≤5
  pages → synthesize**. SearXNG is self-hosted on the Scout box — **$0
  search API**. Page fetch egress stays inside the first 100 GB EC2 free
  grant at these scales.
- **AI off:** `RulesBrain` (no Grok, no ARIA Converse). The t4g.small +
  EIP + 16 GB gp3 **still bills** — Scout is always-on when the flag is
  on. Follow-up chat is deterministic HTTP only.
- **AI on:** `GrokBrain` plan (`max_tokens` 200) + synth (`max_tokens`
  512, each page `text[:2500]`) on Grok 4.7 Global CRIS, **plus** one
  extra ARIA Converse that consumes the 420-char digest. That follow-up
  is **in addition to** the 3 chats/day baseline (same-week complex case,
  not a replacement chat).
- Grok 4.7 reasoning is on by default on the model card. The gateway
  does **not** add Claude’s 1024-token thinking headroom for Grok
  (`converse_request_shape` only does that for Claude 5.x), and Scout
  caps plan/synth at 200/512, so billed output is modeled at those
  completions — not a large reasoning dump.
- Scout `POST /scout/research` is an HTTP API proxy to EC2 (no extra
  Lambda). The follow-up `POST /ai/chat` is a normal Lambda + Dynamo
  request.
- One shared Scout box for all three user counts. 730-hour AWS month
  for always-on compute: **$12.26** instance + **$3.65** IPv4 +
  **$1.28** gp3 = **$17.19** (matches `scout.tf` / `backend/scout/README.md`
  “about $17/month before tokens”).
- Same ARIA mix as the baseline: 88/8/3.5/0.5 Sonnet/Grok/Opus/ensemble; chat
  1800+400; router 2500+400 (no 1.1×).

### Per-handoff tokens (AI on)

| Stage | In / out | Priced as | $ / handoff |
| --- | ---: | --- | ---: |
| Scout plan | 150 / 100 | Grok 4.7 Global $2 / $6 | $0.0009 |
| SearXNG + read ≤5 pages | — | self-hosted on the box | $0 |
| Scout synthesize | 3400 / 400 | Grok 4.7 Global $2 / $6 | $0.0092 |
| ARIA follow-up (420-char digest) | 2000 / 400 | 88/8/3.5/0.5 suite mix | $0.0085 |
| **Tokens / handoff** | | | **$0.0186** |

Plan/synth sizes follow the code: short planner prompt vs. five 2500-char
page blocks into a 512-token JSON brief. Follow-up is a baseline chat
plus the clipped digest inside the 4000-char user context.

### Combined estimate (USD / month)

ARIA baseline **plus** Scout handoffs. Infra column includes the $17.19
box and the extra HTTP (Scout route + follow-up). Token column is ARIA
3 chats/day **plus** Grok plan/synth **plus** the follow-up Converse.

| Users | Handoffs | Infra (AI **off**) | Tokens (AI **on**) | Combined **off** | Combined **on** | Per user **off** | Per user **on** |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| 5 | 21 | $17.20 | $4.30 | **$17.20** | **$21.50** | **$3.44** | **$4.30** |
| 100 | 429 | $17.36 | $85.99 | **$17.36** | **$103.35** | **$0.17** | **$1.03** |
| 1,000 | 4,286 | $18.87 | $859.85 | **$18.87** | **$878.72** | **$0.02** | **$0.88** |

At 5 users the box dominates (~$3.44/user with AI off). At 1,000 users
it amortizes to pennies and tokens take over.

**Paused:** Grok and the ARIA follow-up Converse are $0 (`BedrockGateway`
choke). RulesBrain can still search. The box still bills **$17.19**.

**Paused + Scout off:** back to the baseline table’s health/dashboard
pennies.
