# Dummy loadtest — stress

- generated_at: 2026-09-29T03:41:28.649039+00:00
- requests: 10
- requests_per_second: 1.6677721216212813
- p50_ms: 0.878513
- p95_ms: 1.4471304999999992
- p99_ms: 1.6742149
- error_rate_overall: 0.1
- duration_seconds: 5.996023
- vm_cpu_count: 4
- vm_ram_gib: 15.64
- backend_workers: 1 (single process, thread-per-request (no gunicorn/uvicorn workers))

## Per route

| route | requests | rps | error_rate | status_codes | p50_ms | p95_ms | p99_ms |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| GET /devices/catalog | 2 | 0.33355442432425625 | 0.0 | 200:2 | 0.8680405 | 0.96774835 | 0.9766112699999999 |
| GET /progress/summary | 3 | 0.5003316364863843 | 0.0 | 200:3 | 1.02026 | 1.6599134 | 1.71677148 |
| GET /sleep | 1 | 0.16677721216212812 | 0.0 | 200:1 | 0.779247 | 0.779247 | 0.779247 |
| GET /workouts/history | 2 | 0.33355442432425625 | 0.0 | 200:2 | 1.0389875 | 1.0940751499999999 | 1.09897183 |
| GET /workouts/today | 1 | 0.16677721216212812 | 0.0 | 200:1 | 0.572016 | 0.572016 | 0.572016 |
| POST /ai/chat | 1 | 0.16677721216212812 | 1.0 | 429:1 | 0.738172 | 0.738172 | 0.738172 |

## Breaking point

{
  "aborted": true,
  "reason": [
    "error_rate 0.1000 >= 0.01"
  ],
  "error_status_codes": [
    "POST /ai/chat 429\u00d71"
  ],
  "p95_ms_at_stop": 1.4471304999999992,
  "interpolated_arrival_rps_at_stop": 2.5989394666666668,
  "failed_at_target_rps": 5.0,
  "held_through_target_rps": 1.0,
  "peak_1s_http_reqs_before_stop": 3,
  "duration_seconds": 5.996023,
  "note": "aborted at 6.00s of 75s planned: error_rate 0.1000 >= 0.01 (POST /ai/chat 429\u00d71)"
}

## Peak 1s request rate (from k6 json)

{
  "peak_1s_http_reqs": 3,
  "samples": 6,
  "min_1s_http_reqs": 1,
  "median_1s_http_reqs": 2
}

## Zero-Bedrock / Zero-ElevenLabs guard

- bedrock_client: 0
- bedrock_invoke: 0
- elevenlabs_http: 0
- elevenlabs_api: 0
- total: 0
- ok: True

