# Dummy loadtest — stress-limiter

- generated_at: 2026-09-29T03:57:39.460762+00:00
- requests: 73406
- requests_per_second: 406.9105479893718
- p50_ms: 0.4573735
- p95_ms: 1.2108552499999998
- p99_ms: 2.9585130499999805
- error_rate_overall: 0.0912731929270087
- error_rate_5xx: 0.0
- error_rate_429: 0.0912731929270087
- error_rate_other: 0.0
- error_rate_non_429: 0.0
- errors_5xx: 0
- errors_429: 6700
- errors_other: 0
- dropped_iterations: 0
- duration_seconds: 180.398371
- vm_cpu_count: 4
- vm_ram_gib: 15.64
- backend_workers: 1 (single process, thread-per-request (no gunicorn/uvicorn workers))
- backend_is_not: Lambda or API Gateway
- numbers_mean: local Dummy backend ceiling on this VM, not production capacity

## Identity and rate limiter

- identity: unsigned Dummy Bearer JWT, sub=loadtest-limiter (single shared user)
- rate_limit_store: in-memory storage.dynamodb._local_store (APP_DATA_TABLE_NAME unset)
- rate_limit_patched: False
- backend_restarted_before_run: True

## Chat limiter admission (60/hour aria-chat)

- finding: exact: 1 user(s) allowed exactly 60 chat 200s
- keeps_exactly_60: True
- tagged_users: 1
- verdicts: {"exact": 1}

| user | chat_200 | chat_429 | chat_5xx | chat_other | verdict |
| --- | ---: | ---: | ---: | ---: | --- |
| loadtest-limiter | 60 | 6700 | 0 | 0 | exact |

## Latency 200 vs 429 (POST /ai/chat)

{
  "chat_200": {
    "count": 60,
    "p50": 5.8934999999999995,
    "p95": 9.14221935,
    "p99": 25.767893989999866
  },
  "chat_429": {
    "count": 6700,
    "p50": 0.413887,
    "p95": 0.9595214999999999,
    "p99": 2.7223443400000016
  }
}

## Per route

| route | requests | rps | p50_ms | p95_ms | p99_ms | 5xx | 429 | other | err_5xx | err_429 | err_other |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| GET /chat/threads/current | 6590 | 36.53026334700107 | 0.4188045 | 0.9299191499999988 | 2.4695527499999828 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| GET /dashboard/today | 6669 | 36.96818304418059 | 0.711536 | 1.2870679999999997 | 2.791642079999999 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| GET /devices/catalog | 6565 | 36.391681164349315 | 0.417275 | 1.0630591999999996 | 3.3703739599999967 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| GET /health | 6788 | 37.62783423360292 | 0.388752 | 0.9284160499999999 | 2.844025060000012 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| GET /me | 6700 | 37.14002495066876 | 0.416472 | 0.9772931499999996 | 3.00523257 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| GET /progress/summary | 6861 | 38.032494206946026 | 0.439901 | 0.967798 | 2.584640999999995 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| GET /sleep | 6684 | 37.05133235377164 | 0.436203 | 0.9944242499999997 | 2.7931246700000005 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| GET /workouts/history | 6606 | 36.618955943898186 | 0.4376645 | 0.970268 | 2.5999245999999903 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| GET /workouts/today | 6559 | 36.3584214405129 | 0.412634 | 0.9570579999999997 | 2.5173960200000005 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |
| POST /ai/chat | 6760 | 37.47262218903296 | 0.4149445 | 1.052095949999999 | 5.3790289799999975 | 0 | 6700 | 0 | 0.0 | 0.9911242603550295 | 0.0 |
| POST /ai/observe | 6624 | 36.71873511540745 | 0.9825975 | 1.6176322499999995 | 2.949107529999994 | 0 | 0 | 0 | 0.0 | 0.0 | 0.0 |

## Breaking point

{
  "aborted": false,
  "never_broke_by_ceiling": true,
  "ceiling_rps": 1000.0,
  "reason": [],
  "error_status_codes": [
    "POST /ai/chat 429\u00d76700"
  ],
  "p95_ms_at_stop": 1.2108552499999998,
  "non_429_error_rate_at_stop": 0.0,
  "interpolated_arrival_rps_at_stop": 1000.0,
  "arrival_rps_at_first_break": 1000.0,
  "rps_at_first_break": null,
  "failed_at_target_rps": null,
  "held_through_target_rps": 1000.0,
  "peak_1s_http_reqs_before_stop": 1015,
  "peak_sustained_5s_rps_before_break": 1003.0,
  "duration_seconds": 180.398371,
  "first_break": null,
  "note": "never broke by the ceiling of 1000 rps"
}

## Peak 1s request rate (from k6 json)

{
  "peak_1s_http_reqs": 1015,
  "samples": 181,
  "min_1s_http_reqs": 1,
  "median_1s_http_reqs": 298
}

## CPU samples

{
  "samples": 181,
  "interval_seconds": 1.0,
  "backend_pid": 45432,
  "host_cpu_pct": {
    "avg": 12.00210223850415,
    "max": 31.094527363184078,
    "min": 0.25062656641604564
  },
  "backend_cpu_pct": {
    "avg": 21.876054246217265,
    "max": 51.985238452196946,
    "min": 0.0,
    "note": "percent of one CPU (100 = one core fully used)"
  }
}

## Zero-Bedrock / Zero-ElevenLabs guard

- bedrock_client: 0
- bedrock_invoke: 0
- elevenlabs_http: 0
- elevenlabs_api: 0
- total: 0
- ok: True

