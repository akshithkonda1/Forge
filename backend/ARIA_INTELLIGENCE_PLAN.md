# ARIA Intelligence Plan — Making ARIA Insanely Smart with Python

> **Status: planning only. No ARIA/backend code was changed to produce this
> document.** It is a concrete, code-anchored roadmap for upgrading the Python
> that powers ARIA. Companion to [`BACKEND_PLAN.md`](BACKEND_PLAN.md) and
> [`infra/TERRAFORM_PLAN.md`](infra/TERRAFORM_PLAN.md).

Everything below cites the code it changes (file + function/line) so each item
is buildable and testable in isolation. The two hard constraints from the rest
of the repo are preserved throughout:

- **Deterministic-first.** `generate_response()` stays a pure function; every
  smart addition must keep a deterministic path and a guaranteed fallback.
- **Bedrock stays opt-in and gated.** `bedrock_enabled()` / `ARIA_BEDROCK_ENABLED`
  remains the kill-switch; the live path never becomes required.

---

## 1. Where ARIA is smart today, and where it isn't

**Today (verified in `services/aria_engine.py`):** ARIA is a *rule-based
template selector*. `generate_response` (L1506) does
`apply_permissions → classify_request → _gather_signals → type-specific
builder`. Seven signal interpreters (`_INTERPRETERS`, L1154) each apply **fixed
population thresholds** (deep sleep 18%, recovery 55/80, steps 5k/10k, HRV
±8%, protein 1.6×kg). `classify_request` (L824) is keyword + presence gates.
The live path (`generate_response_live`, L1749) overlays a single Bedrock call
onto the deterministic envelope and falls back on any error.

Meanwhile a **much richer intelligence layer already exists but is not wired
into chat**:

- `services/biometrics/` computes robust baselines (median/MAD, modified
  z-score), OLS trends with R², EWMA, Welford online stats, and physiological
  estimators (VO2max, MAP, autonomic stress, fused recovery) — but
  `BodyModel.to_aria_context()` only feeds `/ai/observe`, **not** `/ai/chat`.
- `CoachContextEngine` (`aria_context.py`) stores relationship + `last_insights`
  + `build_rich_context` patterns — but **none of it reaches
  `user_model_block()`** or the reasoning; only a cosmetic `memory_reference`
  string is prepended.
- `ai_router.py` has real multi-model fan-out + consensus finalization — but
  it serves package Q&A, **not coaching**.
- SimRunner scores a **stub** engine on a richer context (ACWR, sleep-debt,
  overtraining, chronotype) that production `aria_engine` doesn't compute — so
  "smart" is measured on a parallel system.

**The theme of this plan: stop leaving intelligence on the table.** Most of the
biggest wins are *connecting and upgrading Python that already exists*, not
green-field ML.

---

## 2. Design principles for "effective Python for AI"

1. **Stdlib-first in the hot path; heavy deps behind a seam.** The Lambda is
   stdlib-only by design (fast cold start, no numpy). Keep signal math in pure
   Python; put anything needing `numpy`/embeddings behind the existing
   `InferenceBackend`/`Estimator` protocol (`biometrics/inference.py`) or a
   Lambda layer, never on the default path.
2. **One user model, computed once.** Collapse the three parallel context
   builders (`ARIAContext.from_payload`, `BodyModel.to_aria_context`,
   `coach_context.gather_user_context`) into a single canonical projection.
3. **Signals as data, reasoning as a function of data.** Replace if/elif prose
   trees with a scored evidence model so new signals compose instead of adding
   branches.
4. **The model calls tools; Python owns the truth.** In the live path, give
   Bedrock *tool-use* over Python-computed signals rather than dumping a text
   blob and hoping. Numbers come from Python; language comes from the model.
5. **Everything is measured.** Every intelligence change lands with a SimRunner
   archetype or a unit invariant, and SimRunner must evaluate the *real* engine.

---

## 3. Phase 1 — Personalize the reasoning (highest ROI, low risk)

### 3.1 Personal baselines instead of population constants
**Where:** the interpreters in `aria_engine.py` (`_interpret_sleep` L876,
`_interpret_readiness` L930, `_interpret_activity` L1004, `_interpret_body`
L1032, `_interpret_nutrition` L1075) and `_calibrate_confidence` (L1183).

**What:** thresholds become `personal baseline ± robust band` when enough
history exists, falling back to the current population constants when it
doesn't. The stats already exist in `biometrics/statistics.py`
(`robust_baseline`, `modified_z_scores`, `ewma`, `linear_trend`).

```python
# sketch: services/aria_signal_baselines.py (new)
from services.biometrics.statistics import robust_baseline, modified_z_scores

def personal_band(series: list[float], pop_low: float, pop_high: float):
    if len(series) < 14:                       # not enough history yet
        return pop_low, pop_high, "population"
    center, mad = robust_baseline(series)
    return center - 2*mad, center + 2*mad, "personal"
```

Each interpreter reports whether it judged against a **personal** or
**population** baseline, and that flows into `confidence_reason` — so ARIA can
say "below *your* usual," not "below average," and be honest when it can't.

### 3.2 One canonical user model (close the biometrics↔chat disconnect)
**Where:** `ARIAContext.from_payload` (aria_engine), `BodyModel.to_aria_context`
(`biometrics/body_model.py` L260), `coach_context.gather_user_context`.

**What:** a single `build_user_model(user_id, payload, stored)` that merges
client payload + stored DynamoDB history + `BodyModel` projection into one
`ARIAContext`, with **one definition** of each derived value (fix the weight-
trend and HRV-"7-day"-trend label mismatches the map found). `/ai/chat`,
`/ai/observe`, and coach routes all consume the same builder.

### 3.3 Wire memory into the actual reasoning
**Where:** `CoachContextEngine` (`aria_context.py`), `user_model_block`
(aria_engine L644), route `aria.py` (L94–129).

**What:**
- Inject `last_insights` (recent, deduped) and `build_rich_context` patterns
  (`low_readiness_streak`, `strong_sleep_recovery`) into `user_model_block` so
  they enter both deterministic reasoning and the Bedrock prompt — not just the
  cosmetic `memory_reference` prepend.
- Call `add_insight()` on **every** substantive turn (today it's only plan
  feedback), so ARIA accumulates what it told you and can avoid repeating or can
  follow up ("last week your deep sleep recovered after you moved dinner earlier").

### 3.4 Fill the missing interpreters
**Where:** `_INTERPRETERS` tuple (L1154). Six of eleven domains have no
interpreter.

**What:** add `_interpret_chronotype` (circadian alignment vs `typical_sleep_onset`),
`_interpret_progress` (trend over 30d), and a real `_interpret_lifestyle`/QoL
(beyond the single `habit:sleep_variance` tag). Each is a small pure function
returning a `Signal` (L865), so they compose into existing gathering/sorting.

**Phase-1 payoff:** ARIA speaks to *your* numbers, remembers, and reasons over
more of the data it already receives — with zero new dependencies and full
determinism.

---

## 4. Phase 2 — Real reasoning, not template selection

### 4.1 Evidence-graph fusion replaces if/elif prose
**Where:** `_recommendation_response` (L1303), `_insight_response`,
`_summary_response`.

**What:** convert the branch trees into a **weighted evidence model**. Each
`Signal` carries a direction, magnitude (z-score from §3.1), and a
per-signal confidence (from the biometrics estimators). Reasoning becomes:

1. Rank signals by `magnitude × confidence × domain_priority`.
2. Detect **cross-signal patterns** (e.g. HRV↓ + RHR↑ + sleep-debt =
   under-recovery; load↑ + HRV↓ = overreaching) via a small rule table over the
   signal set instead of nested ifs.
3. Compose the "What I notice / One next step / Why" sections from the top
   pattern, with the runner-up as the optional "Why."

This makes new signals *additive* and lets ARIA reason about **combinations**,
which population-threshold ifs can't.

### 4.2 Port SimRunner's clinical rules into the production engine
**Where:** production `aria_engine.py`; source rules in
`ai/simrunner/.../aria_evaluator.py` (directional-correctness rules) and the
data generator (ACWR, sleep-debt-7d, `is_overtrained`, isometric handling).

**What:** production ARIA should actually compute **ACWR (acute:chronic workload
ratio)**, 7-day sleep debt, and overtraining flags, and honor the safety rules
SimRunner grades on (e.g. never recommend high intensity when readiness < 50).
This **closes the eval↔production gap** — the #1 reason SimRunner improvements
don't reach `/ai/chat`.

### 4.3 Principled confidence
**Where:** `_calibrate_confidence` (L1183).

**What:** replace hand-tuned offsets with a combination of (a) data-completeness
coverage, (b) mean per-signal estimator confidence, and (c) signal agreement
(variance of directions). Same 0–0.92 range, but derived — and explainable in
`confidence_reason`.

### 4.4 Better intent classification, and emit the `plan` type
**Where:** `classify_request` (L824), `_focus_domain` (L816). The `plan`
response type is defined (L180, L1601) but **never emitted**.

**What (tiered, deterministic fallback preserved):**
- **Fast/default:** a feature-based classifier over message tokens + context
  presence (small logistic model or a compact keyword+TF-IDF scorer) — still
  pure Python, but far less brittle than substring matching.
- **Optional live:** when Bedrock is on, a cheap structured classification call
  (JSON: `{type, focus_domain}`) with the deterministic classifier as fallback.
- Emit `plan` for multi-day/programming requests and route it to a dedicated
  plan builder (which can use the multi-model path in §5.2).

---

## 5. Phase 3 — Use the model well (live path rigor + tool-use)

### 5.1 Tool-use: the model asks Python for numbers
**Where:** `generate_response_live` (L1749), `live_system_prompt` (L1667),
`BedrockGateway.converse` (`ai_router.py` L207) — Converse API supports
`toolConfig`.

**What:** instead of stuffing a `[USER MODEL]` text block and hoping the model
uses it faithfully, expose **tools** the model can call: `get_signal(domain)`,
`get_trend(metric, horizon)`, `get_personal_baseline(metric)`. Python returns
authoritative numbers; the model composes language. This eliminates the
prose↔card number divergence the map flagged (`_merge_live_envelope` L1828) and
makes hallucinated metrics structurally impossible.

### 5.2 Multi-model reasoning for hard questions only
**Where:** reuse `ai_router.route()` fan-out/consensus (L345) for the new `plan`
type and complex recommendations; keep single fast model
(`select_model` L775) for lookups/voice.

**What:** for a weekly plan or a "why am I not recovering" deep-dive, fan out to
2–3 models and run the existing consensus finalizer, but **quality-selected**
(today primary = fastest, L489). Add a lightweight scorer (agreement with
Python-computed signals) to pick the primary rather than first-wins.

### 5.3 Validate model output against ground truth
**Where:** `_parse_model_envelope` / `_merge_live_envelope` (L1800).

**What:** after the model returns, verify every number in the prose exists in
the Python signal set (regex-extract numerics, cross-check against `card`
values within tolerance). On mismatch, drop to deterministic prose. This is a
cheap guardrail that makes the live path trustworthy.

---

## 6. Phase 4 — Statistical & ML intelligence (behind the seam)

Keep these **off the default hot path**; expose via the existing
`Estimator`/`InferenceBackend` protocol (`biometrics/inference.py`) or a Lambda
layer, gated by env (mirroring `BIOMETRICS_MODEL_ENDPOINT`).

- **Short-horizon forecasting:** extend `linear_trend` (`statistics.py` L117)
  to project next 1–3 days with prediction intervals, so ARIA can say "on this
  trajectory your load peaks Thursday." Pure Python (OLS + residual SE).
- **Multivariate anomaly detection:** today anomalies are per-metric
  (modified z). Add cross-signal anomaly (e.g. Mahalanobis over
  {HRV, RHR, sleep}) to catch "each metric is borderline but together they're
  off." Optional numpy behind the seam.
- **Circadian normalization:** normalize metrics by time-of-day before trending
  (the map notes none exists).
- **Change-point detection:** flag regime shifts (new baseline after illness /
  travel) instead of slowly dragging the median.
- **Retrieval over history (RAG):** embed past insights/turns with Bedrock Titan
  embeddings, cache vectors in DynamoDB (`ARIA#EMBED#...`), and retrieve the
  most relevant prior context per turn. Gives true long-term continuity;
  deterministic keyword-recency fallback when embeddings are off.

---

## 7. Phase 5 — Python engineering to sustain it

- **Decompose the 1,920-LOC `aria_engine.py`** into `aria/` (context, signals,
  interpreters, responses, live, prompts). Smaller modules = lazy imports = the
  cold-start win from `BACKEND_PLAN.md` §4.8, and far easier testing.
- **Typed protocols** for `Signal`, `Interpreter`, `Estimator` so new
  intelligence plugs in without touching the core (mypy in CI).
- **Caching:** `functools.lru_cache` on pure signal computations per request;
  DynamoDB-cached embeddings/baselines across requests.
- **Concurrency:** the interpreters are independent — gather them concurrently
  (thread pool) when the set grows; multi-model already uses threads.
- **Property-based tests** (`hypothesis`, dev-only) for invariants that must
  never break: never recommend intensity when readiness < 50; confidence never
  exceeds coverage; redacted domains never surface. These become SimRunner
  mission-critical gates too.
- **Make SimRunner evaluate the real engine** (`ai/simrunner/`): point the
  harness at `aria_engine.generate_response` instead of the stub so the six-
  dimension scores and regression gates measure production intelligence.

---

## 8. Prioritized backlog

| Priority | Item | Section | Risk | Dep |
|---|---|---|---|---|
| P0 | One canonical user model (merge 3 context builders) | 3.2 | low | none |
| P0 | Personal baselines in interpreters + confidence | 3.1, 4.3 | low | 3.2 |
| P0 | Wire memory (`last_insights`, patterns) into reasoning | 3.3 | low | none |
| P0 | SimRunner evaluates the real engine | 7 | low | none |
| P1 | Evidence-graph fusion + cross-signal patterns | 4.1 | med | 3.1 |
| P1 | Port ACWR / sleep-debt / overtraining rules to prod | 4.2 | med | 3.2 |
| P1 | Missing interpreters (chronotype/progress/QoL) | 3.4 | low | none |
| P1 | Live tool-use (model asks Python for numbers) | 5.1 | med | Bedrock |
| P1 | Validate model output vs Python signals | 5.3 | low | none |
| P2 | Better intent classifier + emit `plan` type | 4.4 | med | none |
| P2 | Multi-model reasoning for `plan`/deep-dives | 5.2 | med | 4.4 |
| P2 | Forecasting / multivariate anomaly / RAG | 6 | med-high | seam/layer |
| P2 | Module decomposition + typed protocols + hypothesis | 7 | low | none |

**Dependency vaccine:** everything P0/P1 is pure-Python and deterministic; only
tool-use, RAG, and multi-model reasoning touch Bedrock, and all keep the
deterministic fallback. Nothing here weakens the kill-switch or the privacy
redaction (`apply_permissions`, `user_model_block` restricted gating).

---

## 9. What "insanely smart" looks like when this lands

- Speaks to **your** baselines ("deep sleep is 22% below *your* 30-day median,
  and it's the third night — same pattern as before your last deload").
- **Reasons over combinations** (HRV↓ + load↑ + sleep-debt → one clear
  under-recovery story), not one metric at a time.
- **Remembers** what it told you and follows up.
- **Never invents a number** — the model narrates Python-computed truth via
  tool-use, validated before it's shown.
- **Knows what it doesn't know** — confidence is derived from coverage and
  agreement, and it says so.
- Is **measured on the real engine** by SimRunner, so "smarter" is provable, not
  vibes.

---

## 10. Out of scope

- No code changed for this plan; each item is a proposal to implement and test
  deliberately.
- No AWS/Bedrock enablement change (kill-switch stays off by default).
- No heavy dependency added to the Lambda hot path; ML/embeddings stay behind
  the existing inference seam or a layer.
