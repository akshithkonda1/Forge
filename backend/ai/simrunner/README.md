# ARIA SimRunner

A fully **offline, deterministic** testing and evaluation harness for ARIA, the
AI coaching layer of Forge. It generates realistic synthetic user data from 20
behavioral archetypes (and any model in the full AWS Bedrock catalog), runs ARIA's
prompt → context → response pipeline against that data, grades the output across
six dimensions, and turns those scores into a defensible **ship / hold** verdict:

- **mission-critical triage** — every failure ranked by severity; one safety
  violation forces a HOLD (`diagnostics.py`);
- **statistical confidence** — multi-seed `mean ± stdev` instead of a single number;
- **regression gate** — committed golden baselines + a CI gate that fails the build
  on any regression (`baseline.py`);
- **real-model grading** — opt-in Bedrock Converse calls, or the deterministic stub.

> **Offline and deterministic by default. No real API calls. No HealthKit. No tokens
> consumed.** Same config + same model = identical output, every run.

---

## Requirements

- **Python 3.10+**
- **Zero dependencies** — standard library only. Nothing to install.
- Run all commands **from the repository root** (the directory containing `backend/`).

---

## Quick start

```bash
# Test-Ready dummy orchestrator — local SimRunner stub only. No AWS, no cloud.
python -m backend.simrunner --test-ready
python -m backend.simrunner --test-ready --message "I slept badly — what should I train and eat?"
python -m backend.simrunner --test-ready --gate

# Default: Tier 1 only (fast sanity check)
python -m backend.simrunner

# Test one archetype (by model_id)
python -m backend.simrunner --model anthropic.claude-sonnet-4-6

# Test every archetype in a difficulty tier (1–5)
python -m backend.simrunner --tier 3

# Test the hardest (adversarial) tier
python -m backend.simrunner --tier 5

# Full suite — all 20 archetypes + a combined summary
python -m backend.simrunner --all

# Test ANY model in the AWS Bedrock catalog (not just the 20) — runs against a
# deterministically derived persona
python -m backend.simrunner --model meta.llama3-1-70b-instruct-v1:0

# Multi-seed statistical confidence (variance bands instead of a point estimate)
python -m backend.simrunner --all --seeds 5

# Regression gate: re-grade the suite against the committed golden baselines and
# exit non-zero if anything regresses (composite drop or new mission-critical)
SIMRUNNER_TODAY=2026-01-15 python -m backend.simrunner --all --gate
```

`--model`, `--tier`, and `--all` are mutually exclusive. With no flag, it runs
Tier 1.

| Flag | Purpose |
|------|---------|
| `--model` / `--tier N` / `--all` | scope: one archetype, one tier, or all 20 |
| `--seeds N` | run N seeds and report mean ± stdev + a stability flag |
| `--baseline [DIR]` | write golden snapshots (default `baselines/`) |
| `--compare [DIR]` | diff this run against a committed baseline → `comparison.json` |
| `--gate` | fail (exit 2) on a composite regression or a new mission-critical |
| `--test-ready` | local dummy coach orchestra (SimRunner stub; no AWS / Bedrock / cloud) |
| `--message` | with `--test-ready`, a prompt to orchestrate (repeatable) |
| `--list` / `--list-bedrock` | print the 20 archetypes / the full Bedrock catalog |

---

## Finding archetypes and `model_id`s

`--model` expects an exact `model_id`. List them all (grouped by tier):

```bash
python -m backend.simrunner --list
```

Unknown ids fail cleanly with a pointer to `--list` (no traceback).

`--model` also accepts **any AWS Bedrock model id** (beyond the curated 20) — it
runs against a deterministically derived persona. List the full catalog:

```bash
python -m backend.simrunner --list-bedrock
```

### Difficulty gradient (4 archetypes per tier)

| Tier | Theme | Personas |
|------|-------|----------|
| 1 | Baseline — easy to coach correctly | Compliant Athlete · Steady Beginner · Weekend Warrior · Maintenance Veteran |
| 2 | Moderate complexity | College Student · Rotating Shift Worker · Rebounding Runner · New Parent |
| 3 | Significant — challenges interpretation | Launch-Sprint Engineer · Low-HRV Endurance Athlete · High-ACWR CrossFitter · Night-Shift Nurse |
| 4 | Hard edge cases | Crunch Founder · Pathological-Looking Pro · Menopausal Athlete · Impatient Returner |
| 5 | Adversarial — designed to break ARIA | Self-Contradictor · Mid-Dataset Career Shift · System Gamer · Genuinely Ambiguous Signal |

Standards tighten as the tier rises: the same response that earns a B at Tier 1
earns a lower grade at Tier 4 (`tier_multiplier = 1.0 + (tier − 1) × 0.15`).

---

## Output

Reports are written to **`backend/simrunner/reports/`** (gitignored). stdout
prints a one-line grade summary per model.

- Per archetype: `<model_id>.txt` (narrative) and `<model_id>.json` (structured).
  Dots, slashes, and dashes in the `model_id` become underscores in the filename.
- Multi-model runs (`--tier`, `--all`) also write `_combined_summary.json`.

### Reading the narrative report

- **Overall grade + composite score** (0–100).
- **Diagnostics — verdict** — a defensible **SHIP / HOLD** decision (see below),
  the per-turn pass rate, the severity histogram, and every mission-critical turn
  spelled out as **what / how / when**.
- **Critical failures** — any run where *directional correctness* scored 0
  (e.g. recommending high intensity when readiness < 50). Surfaced at the top.
- **Dimension breakdown** — the six scores, each marked pass / needs work / failing.
- **Statistical confidence** *(multi-seed only)* — composite and per-dimension
  `mean ± stdev`, range, p10–p90, and a stability flag.
- **By difficulty tier** — grade and pass rate (≥ 72 = a pass).
- **Top failure patterns** and **What needs to change** — each recommendation is
  tagged with the component it targets: `[SYSTEM PROMPT]`, `[CONTEXT BUILDER]`,
  `[MODEL ROUTING]`, or `[EVALUATOR]`.
- **Determinism rate** (target ≥ 80%; skipped under real-API), plus **Consumer
  Stability** and **Epistemic Rigor** grades.
- **Models used** — the concrete Bedrock model(s) the harness engine used, with
  per-model counts.

### Scoring dimensions

| Dimension | Weight | What it checks |
|-----------|:------:|----------------|
| Context utilization | 0.25 | References specific values/trends from the context |
| Directional correctness | 0.25 | Hard safety rules (readiness, ACWR, sleep debt, HRV trend) |
| Chronotype alignment | 0.15 | Sleep/training timing respects the chronotype |
| Actionability | 0.15 | Gives a specific, executable recommendation |
| Epistemic honesty | 0.10 | Calibrated confidence; asks rather than guessing when sparse |
| Tone compliance | 0.10 | Calm and declarative; no cheerleading or evasion |

### Grade scale

`A+` ≥ 95 · `A` ≥ 88 · `B+` ≥ 80 · `B` ≥ 72 · `B-` ≥ 65 · `C` ≥ 55 · `C-` ≥ 45 · `F` < 45

---

## Diagnostics & mission-critical triage

A score is not a decision. The diagnostics layer (`aria_simrunner/diagnostics.py`)
turns the evaluator's per-response failures into a defensible **ship / hold**
verdict. Every turn gets a **PASS/FAIL** with:

- **what** failed — the failing dimensions,
- **how** — the exact violation strings,
- **when** — `date · tier · model · query`.

Every failure is triaged by **severity**:

| Severity | Example | Effect |
|----------|---------|--------|
| `mission_critical` | directional safety violation; *confidently wrong* | **forces HOLD** |
| `high` | contradicts the context; evasive/refuses; overconfident | counts against pass rate |
| `medium` | under-uses context; chronotype slip; explanatory-only | counts against pass rate |
| `can_wait` | tone / cheerleading | cosmetic |

The **system verdict** is `SHIP` only when there are **zero mission-critical
failures** *and* the turn pass rate is ≥ 80%; otherwise `HOLD — N mission-critical
failure(s)` (or `HOLD — pass rate X% < 80%`). The verdict prints per model, lands
in a **DIAGNOSTICS — VERDICT** report section, and is emitted in the JSON under
`diagnostics` (with the mission-critical and worst-offender turns fully itemized).

## Statistical confidence (multi-seed)

A single seed is a point estimate. `--seeds N` (or `seed_count` in config) runs the
whole eval loop for seeds `[seed … seed+N-1]` and reports **distributions** instead:

```bash
python -m backend.simrunner --all --seeds 5
```

For the composite and each of the six dimensions you get **mean ± stdev**, min/max,
**p10–p90**, and a **stability flag** (set when the coefficient of variation ≤ 0.10).
Each seed is itself deterministic, so the spread is true model/scenario sensitivity,
not noise — high variance (`UNSTABLE`) means the behavior is fragile to the starting
conditions and deserves a closer look. Lives in a **STATISTICAL CONFIDENCE** report
section and the `multiseed` JSON block. (Stats are a tiny stdlib helper, `_stats.py`
— no numpy.)

## Regression baselines & CI gate

Lock in known-good behavior and fail the build when it regresses.

```bash
# 1. Record golden snapshots (committed to backend/simrunner/baselines/)
SIMRUNNER_TODAY=2026-01-15 python -m backend.simrunner --all --baseline backend/simrunner/baselines

# 2. Diff a fresh run against them (writes reports/comparison.json)
SIMRUNNER_TODAY=2026-01-15 python -m backend.simrunner --all --compare backend/simrunner/baselines

# 3. Gate: exit 2 on any regression (composite drop > gate_max_drop, or a new
#    mission-critical failure). This is what CI runs.
SIMRUNNER_TODAY=2026-01-15 python -m backend.simrunner --all --gate
```

A baseline (`aria_simrunner/baseline.py`) is a per-model golden snapshot of the
metrics that matter: composite, grade, the six dimension averages, the ship/hold
verdict, the **set of mission-critical queries**, and the determinism rate. `compare`
diffs current vs baseline (composite deltas, grade changes, **new/resolved
mission-critical**, determinism deltas); `gate` fails on a composite drop past
`gate_max_drop` **or** any newly-introduced mission-critical failure.

> **Reproducibility:** baselines are byte-stable because the synthetic streams are
> seeded and "today" is pinned via `SIMRUNNER_TODAY`. Generate **and** gate with the
> **same** `SIMRUNNER_TODAY` (CI uses `2026-01-15`). Regenerate the committed
> baselines deliberately when a behavior change is intended, and review the diff.

---

## Configuration — `sim_config.yaml`

| Key | Default | Meaning |
|-----|---------|---------|
| `seed` | `42` | Master seed; drives all randomness |
| `seed_count` | `1` | Seeds per run; `> 1` enables multi-seed confidence (`--seeds` overrides) |
| `snapshot_days` | `[7, 14, 21, 29]` | Which days in the 30-day stream are tested |
| `determinism_sample_size` | `5` | Prompts per tier for the determinism check |
| `use_real_api` | `false` | If true, call the real model (costs tokens) |
| `gate_max_drop` | `3.0` | `--gate` fails if a composite regresses more than this many points |
| `grade_thresholds` | … | Reference thresholds for the grade scale |
| `critical_failure_threshold` | `0` | Directional score that flags a critical failure |
| `report_format` | `both` | `text` \| `json` \| `both` |
| `engine_models` | `{opus, sonnet}` | Concrete Bedrock model backing each routing tier |
| `engine_model` | _(unset)_ | Pin **all** queries to one Bedrock model |

Edits to this file are picked up on the next run.

---

## AWS Bedrock catalog & engine model detection

SimRunner ships a static snapshot of the **full Bedrock foundation-model catalog**
(`backend_simulator/bedrock_catalog.py`) across every provider — Anthropic, Amazon
(Nova/Titan), Meta (Llama), Mistral, Cohere, AI21, DeepSeek, Stability, Luma,
Writer, TwelveLabs. `--model <any-bedrock-id>` tests against it via a derived
persona; `--list-bedrock` prints it.

The harness **detects and reports the concrete model its engine uses**. Each
query is routed to a tier (`opus`/`sonnet`) and resolved to a concrete Bedrock id;
every response carries `model_used` (the id) and `model_class` (the tier), and
each report has a **MODELS USED** section with per-model counts.

Configure which models back the engine:

```yaml
# sim_config.yaml — which Bedrock model backs each routing tier
engine_models:
  opus: anthropic.claude-opus-4-8
  sonnet: anthropic.claude-sonnet-4-6
# engine_model: anthropic.claude-opus-4-8   # OR pin ALL queries to one model
```

```bash
# Pin the engine model at runtime
SIMRUNNER_ENGINE_MODEL=anthropic.claude-haiku-4-5 python -m backend.simrunner

# Opt-in: refresh the catalog from the live Bedrock account (lazy boto3;
# falls back to the static catalog on any failure — offline by default)
SIMRUNNER_BEDROCK_LIVE=true python -m backend.simrunner --list-bedrock
```

> The default path is **offline and stdlib-only** — `boto3` is imported only when
> `SIMRUNNER_BEDROCK_LIVE=true`, and any failure (no boto3, no creds, no network)
> silently falls back to the static catalog.

---

## Real-API mode (opt-in)

The engine is a deterministic **stub** by default — its output shape is identical
to a real model call, so the evaluator can't tell the difference. The harness can
also grade a **real Bedrock model**:

```bash
# Grade a real model (lazy boto3; needs AWS creds + bedrock:InvokeModel)
USE_REAL_API=true SIMRUNNER_ENGINE_MODEL=anthropic.claude-sonnet-4-6 \
  python -m backend.simrunner --model anthropic.claude-sonnet-4-6

# Pair it with multi-seed to capture real-model variance
USE_REAL_API=true python -m backend.simrunner --tier 1 --seeds 5
```

Under the hood, `aria_engine._call_claude` calls Bedrock's **Converse** API through
a minimal client (`aria_simrunner/bedrock_client.py`, mirroring the product gateway
in `backend/infra/lambda/ai_router.py`) with the vendored ARIA system prompt
(`aria_simrunner/prompts.py`), then parses the model's JSON envelope into the same
`ARIAResponse` the stub returns — so the evaluator, diagnostics, and reports all work
unchanged, and `model_used` is the real Bedrock id.

> **Graceful by design.** `boto3` is imported **only** on this path. Any failure —
> no boto3, no creds, no network, a malformed response — prints a one-time warning
> and **falls back to the deterministic stub** rather than crashing the run. The
> determinism check is **skipped** under real-API (the model is non-deterministic);
> use `--seeds` for confidence bands instead. The default run touches no boto3 and
> consumes no tokens.

---

## Determinism

Everything is seeded, so a given config + `model_id` reproduces the **same
scores, grades, and evaluations** every time. The determinism checker runs each
sampled prompt **3×** at the same seed and counts a **semantic match** when all
three runs share the same grade, the same query-type classification, and
directional scores within 10 points. Expect a rate of **≥ 80%** (typically 100%
with the stub engine).

The only non-deterministic part of a report is its **timestamp and the stream's
dates**, which track the real calendar. For **byte-identical report files** (e.g.
golden tests / CI), pin "today":

```bash
SIMRUNNER_TODAY=2026-01-15 python -m backend.simrunner --all
```

## Tests

The package ships a stdlib-only `unittest` suite covering registry integrity,
seeded determinism, numeric invariants across all 20 archetypes, every directional
scoring rule, tier strictness, grade boundaries, config validation, the CLI, the
**diagnostics/severity ladder**, **baseline save/compare/gate**, **multi-seed
statistics**, and the **real-API path** (envelope parsing + graceful fallback via a
faked Bedrock client). Run from the repo root:

```bash
python -m unittest discover -s backend/simrunner/tests -p "test_*.py" -v
```

CI (`.github/workflows/simrunner.yml`) runs this suite, a tier-1 smoke, **and the
full-suite regression gate against the committed baselines** on every PR that
touches `backend/simrunner/`.

---

## Pipeline

1. Load the archetype from `model_registry.py`.
2. Generate a 30-day behavioral stream (`behavior_engine.py`).
3. Build `ARIAContext` snapshots at each configured day (`data_generator.py`).
4. Pull the tier's adversarial queries (`aria_generator.py`).
5. Run each query through the engine (`aria_engine.py`) — stub, or a real Bedrock
   model via `bedrock_client.py` + `prompts.py` under `USE_REAL_API`.
6. Score each response (`aria_evaluator.py`).
7. Aggregate (`stability_analyzer.py`), triage into a ship/hold verdict
   (`diagnostics.py`), check determinism (`determinism_checker.py`), and — across
   seeds — summarize variance (`_stats.py`).
8. Write reports (`report_builder.py`); optionally record/compare/gate against the
   committed golden baselines (`baseline.py`).

## Layout

```
backend/simrunner/
├── __main__.py                 # enables `python -m backend.simrunner`
├── lifetime_suite.py           # single entry point (argparse + pipeline)
├── sim_config.yaml
├── backend_simulator/
│   ├── model_registry.py       # 20 archetypes
│   ├── behavior_engine.py      # 30-day data streams
│   └── data_generator.py       # ARIAContext builder
├── aria_simrunner/
│   ├── aria_engine.py          # deterministic stub + opt-in real Bedrock call
│   ├── bedrock_client.py       # minimal Converse client (lazy boto3)
│   ├── prompts.py              # vendored ARIA system prompt + user-prompt builder
│   ├── aria_evaluator.py       # 6-dimension scoring
│   ├── aria_generator.py       # adversarial query bank
│   ├── query_router.py         # query classification + model routing
│   ├── stability_analyzer.py   # instability index + grading
│   ├── diagnostics.py          # mission-critical triage → ship/hold verdict
│   ├── _stats.py               # stdlib stats for multi-seed confidence
│   ├── determinism_checker.py  # semantic determinism
│   ├── baseline.py             # golden snapshots + regression gate
│   └── report_builder.py       # narrative + JSON reports
├── baselines/                  # committed golden snapshots (the regression gate)
└── reports/                    # generated output (gitignored)
```
