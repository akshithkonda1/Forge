# ARIA SimRunner

A fully **offline, deterministic** testing and evaluation harness for ARIA, the
AI coaching layer of Forge. It generates realistic synthetic user data from 20
behavioral archetypes, runs ARIA's prompt → context → response pipeline against
that data, and grades the output across six dimensions.

> **No real API calls. No HealthKit. No tokens consumed.** Same config + same
> model = identical output, every run.

---

## Requirements

- **Python 3.10+**
- **Zero dependencies** — standard library only. Nothing to install.
- Run all commands **from the repository root** (the directory containing `backend/`).

---

## Quick start

```bash
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
```

`--model`, `--tier`, and `--all` are mutually exclusive. With no flag, it runs
Tier 1.

---

## Finding archetypes and `model_id`s

`--model` expects an exact `model_id`. List them all (grouped by tier):

```bash
python -m backend.simrunner --list
```

Unknown ids fail cleanly with a pointer to `--list` (no traceback).

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
- **Critical failures** — any run where *directional correctness* scored 0
  (e.g. recommending high intensity when readiness < 50). Surfaced at the top.
- **Dimension breakdown** — the six scores, each marked pass / needs work / failing.
- **By difficulty tier** — grade and pass rate (≥ 72 = a pass).
- **Top failure patterns** and **What needs to change** — each recommendation is
  tagged with the component it targets: `[SYSTEM PROMPT]`, `[CONTEXT BUILDER]`,
  `[MODEL ROUTING]`, or `[EVALUATOR]`.
- **Determinism rate** (target ≥ 80%), plus **Consumer Stability** and
  **Epistemic Rigor** grades.

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

## Configuration — `sim_config.yaml`

| Key | Default | Meaning |
|-----|---------|---------|
| `seed` | `42` | Master seed; drives all randomness |
| `snapshot_days` | `[7, 14, 21, 29]` | Which days in the 30-day stream are tested |
| `determinism_sample_size` | `5` | Prompts per tier for the determinism check |
| `use_real_api` | `false` | If true, call the real model (costs tokens) |
| `grade_thresholds` | … | Reference thresholds for the grade scale |
| `critical_failure_threshold` | `0` | Directional score that flags a critical failure |
| `report_format` | `both` | `text` \| `json` \| `both` |

Edits to this file are picked up on the next run.

---

## Real-API mode (optional)

The engine is a deterministic **stub** by default — its output shape is
identical to a real model call, so the evaluator can't tell the difference. To
route to a live model instead:

```bash
USE_REAL_API=true python -m backend.simrunner --tier 1
```

> The real-API path is an intentional integration seam and is not implemented in
> this offline harness (it raises `NotImplementedError`). Keep `use_real_api`
> false for token-free evaluation.

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
scoring rule, tier strictness, grade boundaries, config validation, and the CLI.
Run from the repo root:

```bash
python -m unittest discover -s backend/simrunner/tests -p "test_*.py" -v
```

CI (`.github/workflows/simrunner.yml`) runs this suite plus a tier-1 smoke on every
PR that touches `backend/simrunner/`.

---

## Pipeline

1. Load the archetype from `model_registry.py`.
2. Generate a 30-day behavioral stream (`behavior_engine.py`).
3. Build `ARIAContext` snapshots at each configured day (`data_generator.py`).
4. Pull the tier's adversarial queries (`aria_generator.py`).
5. Run each query through the engine (`aria_engine.py`).
6. Score each response (`aria_evaluator.py`).
7. Aggregate (`stability_analyzer.py`) + check determinism (`determinism_checker.py`).
8. Write reports (`report_builder.py`).

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
│   ├── aria_engine.py          # deterministic stub (real-API swappable)
│   ├── aria_evaluator.py       # 6-dimension scoring
│   ├── aria_generator.py       # adversarial query bank
│   ├── query_router.py         # query classification + model routing
│   ├── stability_analyzer.py   # instability index + grading
│   ├── determinism_checker.py  # semantic determinism
│   └── report_builder.py       # narrative + JSON reports
└── reports/                    # generated output (gitignored)
```
