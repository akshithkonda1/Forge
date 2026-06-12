# ARIA Backend

ARIA (Adaptive Reasoning Intelligence Architecture) is Forge's agentic AI coach layer. It sits on top of the Python Lambda in `backend/app`, uses Claude via Amazon Bedrock (default) or the Anthropic API, and grounds every response in the user's real health and training data through tool calls.

## Architecture

```text
Client (iOS / Web)
    │
    ▼
POST /aria/*  ──►  routes/aria.py
                         │
      ┌──────────────────┼──────────────────┐
      ▼                  ▼                  ▼
 conclusions_store   aria_pipeline     aria_memory
 (encrypted TTL)     (4 Bedrock turns)  (DynamoDB)
      ▲                  │
      │                  ▼
 data_fusion ──► conclusions_engine
 (WellnessSnapshot)   (DataConclusions + coachingBrief)
      ▲
 health / sleep / workout ingest hooks
```

### Modules

| Module | Role |
|--------|------|
| `ai/aria_agent.py` | Bedrock/Anthropic client, tool loop, Sonnet chat + Opus analysis |
| `ai/aria_tools.py` | Tool schemas and DynamoDB-backed implementations |
| `ai/aria_memory.py` | Conversation threads, insights, long-term user summary |
| `services/coach_context.py` | Bounded context package injected on first message |
| `services/aria_enrichment.py` | Rich card attachment + client message normalization |
| `routes/aria.py` | HTTP handlers for all `/aria/*` endpoints |

## Endpoints

All routes require a user identity (Cognito JWT in production; `local-dev-user` in local dev).

| Method | Path | Purpose |
|--------|------|---------|
| `GET` | `/aria/conclusions` | Deterministic data conclusions + offline templates |
| `POST` | `/aria/chat` | Four-turn pipeline chat (`useTools: false` default; tools optional) |
| `POST` | `/aria/analyze` | Deep analysis with Claude Opus + extended thinking |
| `POST` | `/aria/plan` | Generate today's workout/recovery/nutrition plan |
| `POST` | `/aria/lifestyle` | Nutrition, wellbeing, or holistic lifestyle coaching |
| `POST` | `/aria/voice` | Process a voice transcript for TTS-friendly replies |
| `POST` | `/aria/insights/generate` | Generate and persist proactive coaching insights |
| `GET` | `/aria/insights?days=7` | List stored insights (auto-generates if empty) |
| `GET` | `/aria/conversation?threadId=current` | Retrieve conversation history |
| `DELETE` | `/aria/conversation?threadId=current` | Clear a conversation thread |

### Chat response shape

```json
{
  "threadId": "current",
  "message": {
    "id": "aria-1718123456789",
    "role": "trainer",
    "content": "Your readiness is 82 — ...",
    "timestamp": "2026-06-11T12:00:00+00:00",
    "richCard": {
      "type": "data-chart",
      "data": {
        "title": "Sleep Quality (7-day)",
        "values": [78, 82, 85, 80, 88, 84, 86],
        "insight": "Average sleep score: 83.3.",
        "color": "3B82F6"
      }
    },
    "toolCallsMade": ["get_health_snapshot", "get_sleep_analysis"]
  },
  "toolCallsMade": ["get_health_snapshot", "get_sleep_analysis"],
  "toolCallDetails": [
    { "tool": "get_health_snapshot", "input": {}, "success": true }
  ],
  "model": "anthropic.claude-sonnet-4-6",
  "usage": { "inputTokens": 1200, "outputTokens": 180 }
}
```

Rich card types match the shared contract in `shared/api-contracts.ts`: `data-chart`, `workout-plan`, `progress-comparison`.

## Tools

ARIA can call these tools during chat and plan generation:

- `get_user_profile` — goals, experience, coaching style
- `get_health_snapshot` — readiness, HRV, steps, sleep summary
- `get_sleep_analysis` — multi-night sleep breakdown
- `get_workout_history` — recent sessions + training load
- `get_personal_records` — all-time PRs
- `get_todays_plan` — saved workout plan for today
- `get_integration_status` — connected wearables
- `compute_readiness_score` — fresh readiness from sleep
- `get_training_load` — 7-day load trend
- `get_lifestyle_dashboard` — nutrition, habits, QoL metrics
- `get_nutrition_daily` — macro and meal log
- `get_wellbeing_habits` — habit completion + streak
- `log_coaching_insight` — persist a notable pattern for future sessions

## Memory

| Entity | DynamoDB key | Notes |
|--------|--------------|-------|
| Conversation | `ARIA#{threadId}#CONV` | JSON message list; compresses after 40 turns |
| Conclusions | `ARIA#CONCLUSIONS#{ISO_WEEK}` | Encrypted `DataConclusions`; 7-day TTL |
| Insight | `ARIA#INSIGHT#{date}#{id}` | Proactive coaching cards |
| User summary | `ARIA#SUMMARY` | Long-term coaching context (optional) |

Chat gamification (XP, level, streak) syncs through `PUT /me/profile` as `profile.chatGamification` and is included in the coach context ARIA sees.

## Configuration

| Variable | Default | Description |
|----------|---------|-------------|
| `ARIA_BACKEND` | `bedrock` | `bedrock` (IAM role) or `anthropic` (API key) |
| `ARIA_CHAT_MODEL` | Sonnet 4.6 | Real-time chat model |
| `ARIA_ANALYSIS_MODEL` | Opus 4.8 | Deep analysis model |
| `ARIA_BACKUP_MODEL` | Opus 4.8 | Fallback if primary fails |
| `ARIA_MAX_TOOL_ITERATIONS` | `5` | Tool loop safety cap |
| `ANTHROPIC_API_KEY` | — | Required when `ARIA_BACKEND=anthropic` |

Check runtime status:

```bash
python3 backend/tools/aria_cli.py status
curl http://127.0.0.1:3001/health | jq .aria
```

## Local development

```bash
pip install -r backend/requirements.txt
python3 backend/dev/server.py          # port 3001

# Chat (stub agent in tests; real Bedrock when AWS creds present)
python3 backend/tools/aria_cli.py --local chat "How should I train today?"
python3 backend/tools/aria_cli.py analyze "Why is my HRV declining?"
python3 backend/tools/aria_cli.py plan --focus workout
python3 backend/tools/aria_cli.py insights generate
python3 backend/tools/aria_cli.py conversation show

# Run tests (stub agent, no AWS needed)
python3 backend/tools/run_tests.py
```

## Client integration

- **iOS**: `ForgeAPIClient` → `ForgeRepository.sendChatMessage()` reads `message.richCard` and `message.toolCallsMade`.
- **Web**: `clients/web/src/lib/forge-api.ts` exposes `sendARIAChat`, `getARIAConversation`, `getARIAInsights`.
- **Contracts**: TypeScript types in `shared/api-contracts.ts` under `ARIA*`.

## Testing

`backend/tests/test_aria.py` covers all routes with a stub agent (no API keys). Tool implementations are tested in `ARIAToolsTests`. Enrichment and memory have dedicated unit tests.

When adding a new tool:

1. Define schema in `aria_tools.py` → `ARIA_TOOLS`
2. Implement handler and register in `_TOOL_HANDLERS`
3. Add a unit test in `test_aria.py`
4. Update this doc and `aria_cli.py tools` if the tool is user-facing