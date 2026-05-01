# FORGE Backend

Shared AWS-backed backend for both Forge clients.

## AI Router

The shared Lambda now exposes `POST /ai/router`, a Python-based Bedrock router that:

- starts with Claude Sonnet 4.6,
- escalates to Claude Opus 4.7 if no answer arrives within the configured SLA window,
- escalates again to Kimi K2 Thinking if needed,
- activates more models immediately as `packageSizeBytes` grows toward the 10 GB cap.

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

- `answer`: the first successful answer returned inside the routing window,
- `selectedModel`: the model slot and Bedrock model ID that won,
- `routing`: package size, initial fanout, launched models, and timeout policy,
- `results`: per-model latency and outcome metadata,
- `supportingAnswers`: any additional successful answers received inside the consensus window.

### 10 GB behavior

The 10 GB limit is a routing limit, not a raw prompt size. Large datasets should be passed as:

- package metadata,
- short inline previews, or
- S3 object references that the router can sample for a lightweight preview.

This avoids trying to push multi-GB payloads directly through API Gateway, Lambda, or a single model context window.

### Model configuration

Defaults:

- Slot 1: `anthropic.claude-sonnet-4-6`
- Slot 2: `anthropic.claude-opus-4-7`
- Slot 3: `moonshot.kimi-k2-thinking`

The third slot is configurable with `AI_ROUTER_MODEL_3_ID`. As of May 1, 2026, AWS Bedrock documents `moonshot.kimi-k2-thinking` as the runtime model ID for Kimi K2 Thinking, so that is now the router's default third model.
