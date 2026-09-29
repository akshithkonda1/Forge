# Dummy loadtest — stress

- generated_at: 2026-09-29T03:50:27.883699+00:00
- requests: 31206
- requests_per_second: 205.29220894752336
- p50_ms: 9.199121
- p95_ms: 226.25241575
- p99_ms: 2101.0356072500012
- error_rate_overall: 0.010895340639620586
- error_rate_5xx: 0.0021470230083958214
- error_rate_429: 0.0
- error_rate_other: 0.008748317631224764
- error_rate_non_429: 0.010895340639620586
- errors_5xx: 67
- errors_429: 0
- errors_other: 273
- dropped_iterations: 12470
- duration_seconds: 152.007717
- vm_cpu_count: 4
- vm_ram_gib: 15.64
- backend_workers: 1 (single process, thread-per-request (no gunicorn/uvicorn workers))
- backend_is_not: Lambda or API Gateway
- numbers_mean: local Dummy backend ceiling on this VM, not production capacity

## Identity and rate limiter

- identity: unsigned Dummy Bearer JWT, sub=loadtest-<vu>-<iter>
- rate_limit_store: in-memory storage.dynamodb._local_store (APP_DATA_TABLE_NAME unset)
- rate_limit_patched: False
- backend_restarted_before_run: True

## Per route

| route | requests | rps | p50_ms | p95_ms | p99_ms | 5xx | 429 | other | err_5xx | err_429 | err_other |
| --- | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: | ---: |
| GET /chat/threads/current | 2729 | 17.95303589751302 | 8.29988 | 229.9286962 | 2478.6355759199987 | 0 | 0 | 22 | 0.0 | 0.0 | 0.008061561011359472 |
| GET /dashboard/today | 2854 | 18.775362569256927 | 13.7961345 | 237.57247215 | 2429.9550598699548 | 36 | 0 | 30 | 0.012613875262789068 | 0.0 | 0.01051156271899089 |
| GET /devices/catalog | 2874 | 18.906934836735953 | 9.9687965 | 228.65228159999998 | 2087.912014279999 | 0 | 0 | 29 | 0.0 | 0.0 | 0.010090466249130133 |
| GET /health | 2797 | 18.400381606941703 | 7.176031 | 222.3893338 | 2712.1599399599963 | 0 | 0 | 19 | 0.0 | 0.0 | 0.006792992491955667 |
| GET /me | 2858 | 18.80167702275273 | 8.1810495 | 225.12730290000002 | 2127.0831926899873 | 0 | 0 | 22 | 0.0 | 0.0 | 0.007697690692792162 |
| GET /progress/summary | 2874 | 18.906934836735953 | 9.79323 | 226.7416725999999 | 1687.8193155999998 | 0 | 0 | 26 | 0.0 | 0.0 | 0.009046624913013222 |
| GET /sleep | 2853 | 18.768783955882974 | 7.918417 | 224.83365120000002 | 2226.8984582800003 | 0 | 0 | 28 | 0.0 | 0.0 | 0.00981423063441991 |
| GET /workouts/history | 2876 | 18.920092063483853 | 8.222166000000001 | 217.4131925 | 1877.41190275 | 0 | 0 | 32 | 0.0 | 0.0 | 0.011126564673157162 |
| GET /workouts/today | 2758 | 18.143815685357605 | 7.5802865 | 224.06921375000002 | 1707.076956349999 | 0 | 0 | 28 | 0.0 | 0.0 | 0.01015228426395939 |
| POST /ai/chat | 2880 | 18.94640651697966 | 15.168448 | 231.21649539999999 | 2880.7753182300016 | 31 | 0 | 17 | 0.010763888888888889 | 0.0 | 0.005902777777777778 |
| POST /ai/observe | 2853 | 18.768783955882974 | 8.742946 | 223.6475522 | 1813.77558352 | 0 | 0 | 20 | 0.0 | 0.0 | 0.0070101647388713636 |

## Breaking point

{
  "aborted": true,
  "never_broke_by_ceiling": false,
  "ceiling_rps": 1000.0,
  "reason": [
    "non_429_error_rate 0.0109 >= 0.01"
  ],
  "error_status_codes": [
    "GET /dashboard/today 0\u00d730",
    "GET /dashboard/today 500\u00d736",
    "GET /health 0\u00d719",
    "GET /sleep 0\u00d728",
    "GET /me 0\u00d722",
    "GET /workouts/history 0\u00d732",
    "GET /workouts/today 0\u00d728",
    "POST /ai/chat 0\u00d717",
    "POST /ai/chat 500\u00d731",
    "POST /ai/observe 0\u00d720",
    "GET /devices/catalog 0\u00d729",
    "GET /chat/threads/current 0\u00d722",
    "GET /progress/summary 0\u00d726"
  ],
  "p95_ms_at_stop": 226.25241575,
  "non_429_error_rate_at_stop": 0.010895340639620586,
  "interpolated_arrival_rps_at_stop": 920.0771700000001,
  "arrival_rps_at_first_break": 920.0,
  "rps_at_first_break": 277,
  "failed_at_target_rps": 1000.0,
  "held_through_target_rps": 800.0,
  "peak_1s_http_reqs_before_stop": 482,
  "peak_sustained_5s_rps_before_break": 461.0,
  "duration_seconds": 152.007717,
  "first_break": {
    "elapsed_seconds": 152,
    "reason": [
      "non_429_error_rate 0.0109 >= 0.01"
    ],
    "p95_ms": 468.0221079999992,
    "non_429_error_rate_cumulative": 0.010895340639620586,
    "requests_that_second": 277,
    "stage_target_rps": 1000.0,
    "stage_start_rps": 800.0,
    "interpolated_arrival_rps": 920.0,
    "last_completed_target_rps": 800.0
  },
  "note": "first break at 152.00s: non_429_error_rate 0.0109 >= 0.01 (arrival ~920.00 rps, that-second 277 req/s)"
}

## Peak 1s request rate (from k6 json)

{
  "peak_1s_http_reqs": 482,
  "samples": 152,
  "min_1s_http_reqs": 1,
  "median_1s_http_reqs": 185
}

## CPU samples

{
  "samples": 153,
  "interval_seconds": 1.0,
  "backend_pid": 13665,
  "host_cpu_pct": {
    "avg": 15.824168424322057,
    "max": 41.56171284634761,
    "min": 0.5000000000000004
  },
  "backend_cpu_pct": {
    "avg": 43.952404111910326,
    "max": 101.97075299838613,
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

