# Dummy loadtest results

Measured on this VM against `http://127.0.0.1:3001` only. These numbers cover the backend only; the TestFlight Dummy build never calls the backend.

- [baseline.json](baseline.json) / [baseline.md](baseline.md) — 3 VUs, 60s
- [stress.json](stress.json) / [stress.md](stress.md) — ramping arrival rate, aborted when errors exceeded 1%

Guard counters at the end of both runs: bedrock_client=0, bedrock_invoke=0, elevenlabs_http=0, elevenlabs_api=0, total=0.
