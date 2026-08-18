# FORGE Backend

One AWS backend for every Forge client — iPhone, Android, web. Same Cognito, same API, same ARIA, same Dynamo. The clients differ; the resources do not.

```
backend/
  infra/          Terraform + the deployable Lambda (ARIA, routes, Bedrock)
  ai/             Local ARIA: CLI, SimRunner, evaluation harness
  app/            Thin app package
  tests/          Unit tests (stdlib unittest)
  dev_server.py   http://127.0.0.1:3001 wrapping the Lambda handler
  requirements.txt
  pyproject.toml
```

Production code is `backend/infra/lambda`. Terraform zips that folder. Do not grow a second handler tree.

## Implementation Plan

See `IMPLEMENTATION_PLAN.md`. New routes go in `backend/infra/lambda/handler.py` and `backend/infra/lambda/routes/`.

## Implemented Routes

Phase 1 — client-unblocking reads:

- `GET /me`
- `PUT /me/profile`
- `GET /dashboard/today`
- `GET /sleep?days=14`
- `GET /workouts/today`
- `GET /workouts/history?days=30`
- `GET /progress/summary?days=30`
- `GET /chat/threads/current`
- `POST /chat/threads/current/messages`

Phase 2 — ingestion:

- `POST /health/batch` — normalized metric writes
- `POST /sleep/sessions`
- `POST /workouts/logs`
- `POST /integrations/{provider}/sync` — queues a sync job and flips the connection to `syncing`

Phase 4 — AI coach (wraps `POST /ai/router`):

- `POST /coach/messages`
- `POST /coach/workout-plan`
- `POST /coach/sleep-insight`
- `POST /coach/progress-review`

Each coach route gathers a bounded user-context package via `services/coach_context.py` and falls back to a deterministic answer if Bedrock is unreachable, so clients and tests can run without AWS credentials.

All routes return deterministic seed data when no persisted data exists, so clients can move from local mocks to API calls before ingestion pipelines are populated.

## User Category Organizer

`organize_users.py` groups user JSON by the same profile dimensions shown in the iOS onboarding app:

- fitness goals
- experience level
- preferred workout types
- coaching style
- connected devices
- weekly schedule

Example:

```bash
python3 backend/organize_users.py users.json --category fitness-goal --pretty
```

Use `--category all` to emit every grouping at once.

## AI Router

The shared Lambda now exposes `POST /ai/router`, a Python-based Bedrock router that:

- starts with Claude Sonnet 4.6,
- escalates to Claude Opus 4.7 if no answer arrives within the configured SLA window,
- escalates again to Kimi K2.5 if needed,
- activates more models immediately as `packageSizeBytes` grows toward the 10 GB cap.

The primary default model is Claude Sonnet 4.6. Kimi K2.5 is only used as the third-slot fallback.

### Request shape

```json
{
  "question": "What should today's training plan be?",
  "context": "User is recovering from a hard long run and slept 6h 20m.",
  "packageSizeBytes": 3221225472,
  "packages": [
    {
      "id": "sleep-summary",
      "bytes": 15360,
      "preview": "Sleep efficiency 91%, REM 1h 40m, HRV 68..."
    },
    {
      "id": "whoop-export",
      "bytes": 734003200,
      "s3Key": "private/user-123/whoop/export.csv"
    }
  ],
  "settings": {
    "modelTimeoutSeconds": 5,
    "overallTimeoutSeconds": 14,
    "consensusWindowSeconds": 1,
    "maxTokens": 1000,
    "temperature": 0.2
  }
}
```

### Response shape

The router returns:

- `answer`: an alias of `finalAnswer` for backward compatibility,
- `finalAnswer`: the answer actually returned to the caller,
- `finalAnswerSource`: how the final answer was produced,
- `selectedModel`: the first successful model that answered inside the routing window,
- `routing`: package size, initial fanout, launched models, and timeout policy,
- `results`: per-model latency and outcome metadata,
- `supportingAnswers`: any additional successful answers received inside the consensus window.

Final answer rules:

- if 1 model answer is used, `finalAnswer` is that model's answer,
- if 2 model answers are used, `finalAnswer` is the consensus built from those 2 answers,
- if 3 model answers are used, `finalAnswer` is the consensus built from all 3 answers.

### 10 GB behavior

The 10 GB limit is the total amount of data the router can gather for a single request. It is a routing limit, not a raw prompt-size limit. Large datasets should be passed as:

- package metadata,
- short inline previews, or
- S3 object references that the router can sample for a lightweight preview.

The router uses declared package sizes, per-package byte counts, and S3 object metadata to estimate how much data is being gathered in one go and to decide how many models should share the load. This avoids trying to push multi-GB payloads directly through API Gateway, Lambda, or a single model context window.

### Model configuration

Defaults:

- Default start model / Slot 1: `anthropic.claude-sonnet-4-6`
- Slot 2: `anthropic.claude-opus-4-7`
- Slot 3 fallback: `moonshotai.kimi-k2.5`

The third slot is configurable with `AI_ROUTER_MODEL_3_ID`. As of May 1, 2026, AWS Bedrock documents `moonshotai.kimi-k2.5` as the runtime model ID for Kimi K2.5, so that is the router's default third-slot fallback model. The router still starts with Claude Sonnet 4.6 by default.
