# Forge backend scaling

Plan-only knobs and alarms. Nothing here requires provisioned capacity.
`enable_alarms` (default true) creates **7** standard CloudWatch alarms — under
the 10-alarm free tier — all on one SNS topic
(`${name_prefix}-ops-alarms`). `treat_missing_data = notBreaching`.

## Serverless posture

What the stack on `main` actually is:

- **Zero provisioned concurrency.** The API Lambda stays unreserved
  (`lambda_reserved_concurrency = null`). A small reserved cap is optional
  and free; it is a ceiling, not a fleet.
- **HTTP API, pay per call.** API Gateway HTTP API with stage defaults of
  50 rps / burst 100 (`api_throttling_rate_limit` /
  `api_throttling_burst_limit`).
- **DynamoDB `PAY_PER_REQUEST`.** No read/write capacity. Do not switch this
  table to provisioned.
- **No always-on compute.** The only EC2 is ARIA Scout, behind
  `enable_scout` (default **false**). Nothing is created or billed while
  that flag is off.
- **No RDS, ECS, EKS, NAT, or ElastiCache.**
- **Bedrock off.** `aria_bedrock_enabled` defaults false. Dummy-offline and
  live-API-no-Bedrock keep it false.
- **Logs 14 / 7 days.** Prod-like 14, everything else 7. No unbounded groups.
- **No cost dashboard unless asked.** `enable_cost_dashboard` default false
  ($3/month). See [`COST.md`](COST.md).

A pytest cheap-guard (`backend/infra/tests/test_serverless_guard.py`) fails CI
if a future change sneaks in provisioned concurrency, provisioned Dynamo, or
always-on compute outside Scout’s `count = local.scout_count` allowlist.

## Alarms → knobs

| Alarm | Knob to turn | Cost note |
| --- | --- | --- |
| Account `AWS/Lambda` `ConcurrentExecutions` Maximum ≥ 80% of `account_concurrency_limit` | Confirm the real ceiling with `aws lambda get-account-settings` (new accounts can be as low as 10; default var is 1000). Optionally set `lambda_reserved_concurrency` to a small cap (≥ 1) and raise it later. Request an account-limit increase from AWS if the account is actually at the ceiling. | Reserved concurrency is a **free cap**. Provisioned concurrency is forbidden (it bills). |
| HTTP API 429s (access-log metric filter on `$.status` 429, sum > 0 / 5 min) | Raise `api_throttling_rate_limit` (default 50) and/or `api_throttling_burst_limit` (default 100). HTTP APIs publish no throttle metric, which is why this uses the existing access log group. | Still pay-per-call. Higher throttle only lifts the ceiling. |
| DynamoDB `ThrottledRequests` > 0 / 5 min | Keep `PAY_PER_REQUEST`. On-demand throttles are almost always a hot partition, not a missing capacity number. Spread keys; do not add `read_capacity` / `write_capacity`. | On-demand is the cheap default. Provisioned mode is a CI failure. |
| DynamoDB `SystemErrors` > 0 / 5 min | AWS-side fault. Retries already sit on the shared botocore config (2s connect / 5s read / 3 attempts). Check AWS Health; do not scale the table. | No extra spend. |
| Lambda `Errors` ≥ 1 / 5 min | Read `/aws/lambda/<prefix>-api`. Code/IAM bug, not a size knob. Memory stays 256 MB arm64 unless profiling says otherwise. | Errors are free to observe; fixing them is the cost control. |
| Lambda `Throttles` ≥ 1 / 5 min | Same as concurrency: `lambda_reserved_concurrency` (null = unreserved) or the account concurrency limit. Never provisioned concurrency. | Free cap vs billed provisioned — use the cap. |
| HTTP API `5xx` ≥ 1 / 5 min | Integration failures (Lambda errors, timeouts). See Lambda Errors. Stage timeout is already 15s, matching the function. | No scale-out lever; fix the error. |

**Cognito:** no alarm. There is no simple free quota metric for the user-pool
MAU / RPS envelope at this size. Essentials is still inside the 10k MAU free
allowance at the ~1k MAU ceiling.

## ARIA kill switch

Standard-tier String parameter `/${name_prefix}/ai/ARIA_PAUSED` (default
`"false"`, `lifecycle.ignore_changes = [value]` so a live pause is not
reverted on apply). Lambda env: `ARIA_PAUSED_PARAMETER_NAME`,
`ARIA_PAUSE_FAIL_MODE` (`open` \| `paused`, default `paused`). Cached 60s
in-process.

Pause (ARIA chat/router/coach only; voice, `/health`, and non-ARIA routes stay up):

```bash
aws ssm put-parameter --name /<prefix>/ai/ARIA_PAUSED --value true --overwrite
```

Resume:

```bash
aws ssm put-parameter --name /<prefix>/ai/ARIA_PAUSED --value false --overwrite
```

Up to ~60 s lag on warm invokes. SSM errors fail **paused** (ARIA routes
503) unless `aria_pause_fail_mode = "open"`. Unset
`ARIA_PAUSED_PARAMETER_NAME` always fails open. `/health` and voice HTTP
stay up when ARIA is paused; **no Bedrock Converse runs anywhere**
(gateway choke point + tests in `test_aria_pause_zero_spend.py`). Daily
caps: `aria_daily_request_cap` (40) and `aria_daily_token_cap` (20000),
inert while Bedrock is off. Do not set `lambda_reserved_concurrency = 0`
to pause the app — validation rejects 0; the SSM flag is the kill switch.

Spend visibility: the $25 monthly budget alerts at 80% actual, 100% actual,
and 100% forecasted. Leave `spend_guard_notification_email` empty until
Akshith fills it in.

## Teardown (deletion protection)

DynamoDB `deletion_protection_enabled` and Cognito
`deletion_protection = "ACTIVE"` default **on**
(`dynamodb_deletion_protection`, `cognito_deletion_protection`). Destroy is
two applies:

1. Set both variables to `false` and `terraform apply`.
2. Then `terraform destroy` (or a targeted destroy).

A single destroy with protection still on will fail on those two resources.
