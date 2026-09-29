# Dummy loadtest — baseline

- generated_at: 2026-09-29T03:41:28.502285+00:00
- requests: 888
- requests_per_second: 14.795326156467171
- p50_ms: 1.152332
- p95_ms: 6.473762399999999
- p99_ms: 8.488508309999999
- error_rate_overall: 0.037162162162162164
- duration_seconds: 60.018954
- vm_cpu_count: 4
- vm_ram_gib: 15.64
- backend_workers: 1 (single process, thread-per-request (no gunicorn/uvicorn workers))

## Per route

| route | requests | rps | error_rate | status_codes | p50_ms | p95_ms | p99_ms |
| --- | ---: | ---: | ---: | --- | ---: | ---: | ---: |
| GET /chat/threads/current | 79 | 1.316250863019039 | 0.0 | 200:79 | 0.965159 | 2.9666614999999976 | 7.088045119999999 |
| GET /dashboard/today | 76 | 1.266266653030974 | 0.0 | 200:76 | 1.4894500000000002 | 2.6941345 | 4.91196725 |
| GET /devices/catalog | 71 | 1.1829596363841997 | 0.0 | 200:71 | 1.005448 | 2.6395075 | 5.674329599999998 |
| GET /health | 72 | 1.1996210397135545 | 0.0 | 200:72 | 0.9187085 | 2.864385050000002 | 6.920861540000002 |
| GET /me | 82 | 1.3662350730071038 | 0.0 | 200:82 | 0.991374 | 3.4784272500000024 | 6.740334619999994 |
| GET /progress/summary | 91 | 1.516187702971298 | 0.0 | 200:91 | 0.974838 | 2.9414145 | 3.892495399999991 |
| GET /sleep | 89 | 1.482864896312588 | 0.0 | 200:89 | 0.93827 | 2.9225911999999985 | 5.046464040000004 |
| GET /workouts/history | 79 | 1.316250863019039 | 0.0 | 200:79 | 1.086959 | 4.176826499999988 | 7.324791339999999 |
| GET /workouts/today | 68 | 1.1329754263961347 | 0.0 | 200:68 | 0.9551645 | 2.3987372999999996 | 3.678780669999999 |
| POST /ai/chat | 92 | 1.5328491063006529 | 0.358695652173913 | 200:59, 429:33 | 6.143247499999999 | 8.5315431 | 11.99034931 |
| POST /ai/observe | 89 | 1.482864896312588 | 0.0 | 200:89 | 1.863195 | 3.0244853999999997 | 9.550168480000005 |

## Breaking point

_baseline has no breaking point_

## Peak 1s request rate (from k6 json)

{
  "peak_1s_http_reqs": 15,
  "samples": 62,
  "min_1s_http_reqs": 1,
  "median_1s_http_reqs": 15
}

## Zero-Bedrock / Zero-ElevenLabs guard

- bedrock_client: 0
- bedrock_invoke: 0
- elevenlabs_http: 0
- elevenlabs_api: 0
- total: 0
- ok: True

