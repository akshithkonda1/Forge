# Dummy backend loadtest

k6 harness against a **locally started** Forge Dummy backend (`backend/dev_server.py` Lambda wrapper). It will not run against AWS.

Hard refuses (exit 2) unless:

- `BASE_URL` is `http://127.0.0.1…` or `http://localhost…`
- `ARIA_BEDROCK_ENABLED=false`
- `ARIA_VOICE_ENABLED=false` (harness flag; live voice is not used)

The Dummy process is started with a sitecustomize/import guard. Bedrock client creation or invoke, and any ElevenLabs HTTP, raises and increments a counter. `GET /__loadtest/guards` must report `total: 0`.

These numbers are a **local Dummy backend ceiling** on a single-process `ThreadingHTTPServer` in this VM. They are **not** Lambda, API Gateway, or production capacity. The TestFlight Dummy build never calls the backend.

## Scenarios

1. **baseline** (smoke): 3 VUs for 1 minute across `/health`, the main read routes, `POST /ai/chat`, and `POST /ai/observe`. Uses the shared `FORGE_TEST_USER_ID=loadtest-user` identity.
2. **stress**: ramping arrival rate (20 → 1000 rps, hard stop at the ceiling) with `preAllocatedVUs=250` / `maxVUs=2000`. Each iteration authenticates as a distinct Dummy user (`loadtest-<vu>-<iter>` unsigned Bearer JWT) so the per-user 60/hour `aria-chat` limiter does not cap throughput. The limiter itself is not disabled or patched. Abort when **non-429** errors reach 1% or p95 exceeds 2s; 429s are counted per route but do not abort. `dropped_iterations` is recorded so a k6 VU shortage cannot look like capacity.

Stress always restarts the Dummy process first. Rate-limit counters live in the in-memory `storage.dynamodb._local_store` when `APP_DATA_TABLE_NAME` is unset, so a fresh process clears that state.

Neither scenario is run by CI on push/PR. The optional workflow is `workflow_dispatch` only. BASE_URL lives in the k6 env/script only — not in `ForgeSwift/**` plists, `generate_client_config`, or any client config (`--check` rejects loopback).

## Run

From the repo root, with k6 on `PATH`:

```bash
export BASE_URL=http://127.0.0.1:3001
export ARIA_BEDROCK_ENABLED=false
export ARIA_VOICE_ENABLED=false
export ENVIRONMENT=local
export FORGE_ALLOW_ANON_TEST_USER=true

# baseline / smoke (shared loadtest-user is fine)
export FORGE_TEST_USER_ID=loadtest-user
bash backend/loadtest/run.sh baseline

# stress (run.sh unsets FORGE_TEST_USER_ID, restarts Dummy, unique JWT per VU/iter)
unset FORGE_TEST_USER_ID
bash backend/loadtest/run.sh stress
```

`run.sh` starts `python3 backend/loadtest/run_server.py` if `/health` is not already up (stress always restarts), runs k6, then writes:

- `backend/loadtest/results/<scenario>.json`
- `backend/loadtest/results/<scenario>.md`
- `backend/loadtest/results/summary.json` / `summary.md` (last scenario)

## Syntax check only

```bash
k6 inspect backend/loadtest/k6/baseline.js
k6 inspect backend/loadtest/k6/stress.js
k6 archive backend/loadtest/k6/baseline.js -O /tmp/forge-loadtest-baseline.tar
```

## Guard

`backend/loadtest/guard.py` is installed before the Lambda handler is imported:

- `boto3.client('bedrock-runtime'|…)` increments `bedrock_client` and raises
- `BedrockGateway._get_bedrock_client` / `.converse` increment and raise
- `urllib.request.urlopen` to `*.elevenlabs.io` increments `elevenlabs_http` and raises
- `services.elevenlabs_voice` mint/tool/design helpers increment `elevenlabs_api` and raises

This is loadtest-only. Production paths are unchanged.

## CI

`.github/workflows/loadtest.yml` is `workflow_dispatch` only (`contents: read`, no secrets). It installs k6 via `grafana/setup-k6-action` (SHA-pinned), starts the Dummy backend on the runner, runs the chosen scenario, and uploads `backend/loadtest/results/`.
