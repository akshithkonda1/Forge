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

## 0. What ARIA is — the product definition

ARIA is the intelligence inside **Forge**, which is two things at once: a
**lifestyle-based workout platform** and a **multi-model AI platform** built for
precision. ARIA itself is **three distinct things** that must not blur together:

### 0.1 A data-ingestion engine
ARIA takes raw signal — HealthKit samples, app data, and the things the user
says day to day — and turns it into a clean, typed, permission-aware user model.
This is the `biometrics/` classify→`BodyModel`→projection pipeline plus the
context builders. It is the sensory layer: everything downstream reasons over
what ingestion produces, so ingestion has to be trustworthy, deduplicated, and
plausibility-checked (it already is — keep and extend it, see §3.2, §6).

### 0.2 A generative intelligence engine — a Grok + Claude-family ensemble on AWS
ARIA's "brain" is a **multi-model generative engine built from exactly two model
families: Grok and the Claude family**, configured through **AWS Bedrock**, to
produce **personalized health insights and information**. This is the core of the
"multi-model AI platform with extreme precision" idea: not one model, but a
**Grok + Claude ensemble** where the models' strengths are blended/reconciled and
Python owns the ground truth the models narrate.

- **There is no third vendor. Kimi K2.5 / Moonshot is removed entirely** — the
  standing ensemble is **Grok + the Claude family** (Claude Opus / Sonnet
  selected by task) and nothing else. Every current Kimi reference is deleted as
  part of this work (exact locations in §5.2).
- Today the router (`ai_router.py`) defaults to Claude Sonnet + Claude Opus +
  Kimi (to be removed); the chat path uses a **single** Claude model, and Grok
  appears only as a verification note. **The product intent is Claude family +
  Grok as the standing ensemble.**
- Implication for the plan: the multi-model consensus machinery (§5.2) is not a
  "hard-questions-only" nicety — it is **ARIA's generative engine**. Claude and
  Grok both answer; the finalizer reconciles; Python validates every number
  (§5.3). Bedrock IAM currently scopes Anthropic ARNs only — add Grok (xAI)
  model access + the `bedrock:*` resource scope in Terraform, and set the router
  slots to Claude + Grok.

### 0.3 A memory + companion engine (CoachContextEngine) — human-like, two-tier
ARIA remembers **like a person**: it has **long-term** and **short-term** memory,
and it must **actively decide what to keep and what to let go**.

- **Long-term memory = what ARIA knows about *you*.** Durable identity: who you
  are, your goals and why they matter, your relationships, preferences,
  constraints, sensitivities, recurring patterns, running jokes. This is the
  substance of the bond and persists.
- **Short-term memory = what you're telling it *right now*.** Time-bound, often
  event-anchored: "I've got a wedding in three weeks." ARIA uses it while it's
  relevant, then **forgets it once the event passes** — it should not clutter
  the long-term model with expired specifics (though a *durable* takeaway can be
  promoted, e.g. "cares about looking good for big events").
- **ARIA evaluates its own memory.** A consolidation step decides what graduates
  from short-term to long-term, what expires (TTL/event-completion), and what
  was never worth keeping. Forgetting is a feature, not a bug.

The **kind** of memory matters as much as the tiering: this is **life insights,
relationships, and daily conversation**, *not* a clinical record. "Your sister's
wedding is in three weeks and you want to feel good in photos" is the memory that
counts — **not** "flu vaccination on 2025-03-01." Clinical facts stay in the
permission-gated `clinical_data` domain and are never the substance of the
relationship. This is what makes ARIA a **lifestyle companion**, not a chart
reviewer (see §3.3, built around this).

### 0.4 The companion mentality — bond first, facts always, and *where* the doctor line sits
Forge is designed for ARIA to **organically develop a bond** with the user —
through **jokes, comments, and general humor**, and through **facts and advice**
— while holding a clear line about clinical territory.

**Where the line sits (refined):** ARIA **suggests, it does not prescribe**, and
it does not act as a doctor for anything serious. But **generic, widely-known
first-aid and safety information is in-bounds** — how to apply a band-aid, basic
first aid you'd give another person, common-knowledge safety steps. That's a
helpful companion, not a physician.

The **hard stop** is anything that requires clinical judgment: diagnosing or
managing serious or internal conditions (e.g. internal bleeding), prescribing
medication or treatment, or anything implying medical authority. There, ARIA
**names the concern and directs to professional or emergency care** — it does not
try to manage it.

So the boundary is concrete: **generic first aid (band-aids, basic first aid to
others) = fine; diagnosing/treating serious or internal medical problems =
hard stop → defer to a professional.** This ethos is already partly encoded
(`ARIA_SYSTEM_PROMPT` L124: "adaptive lifestyle coach… not a wellness chatbot and
not a commander"; L172/204: "Never invent diagnoses… Do not prescribe"). The plan
**strengthens, refines, and enforces** it (see §2a).

### 0.5 SimRunner is CI, not ARIA
**SimRunner is testing infrastructure — a ship/hold gate — and is emphatically
not part of ARIA's runtime.** ARIA is not SimRunner and SimRunner is not ARIA.
Its job is to tell you, in CI, **when ARIA is violating its principles or
functioning improperly**: when it stops being deterministic, when it stops
telling the truth, when it prescribes instead of suggests, when it loses the
tone. It never runs in the request path. The plan's "make SimRunner evaluate the
real engine" item (§7) is precisely so this gate guards *actual* ARIA behavior —
it does **not** make SimRunner part of ARIA (see §5a for the boundary).

What SimRunner is *for*: it exists so ARIA can be trusted **at 100% of its
context** — i.e. that ARIA actually uses everything it's given, correctly, every
time. It does this with **isometric test algorithms**: structure-preserving
checks that hold ARIA's behavior invariant under transformations that must not
change the answer (same context re-ordered or re-expressed → same call; and the
existing isometric-exercise discrimination so an isometric hold isn't mistaken
for high-intensity load). That's how the gate proves ARIA is at full context and
still deterministic and truthful (see §5a).

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

## 1a. What ARIA is — the three pillars (and what SimRunner is *not*)

ARIA is one system with **three distinct responsibilities**. Keeping them
separate in the Python is what makes it both smart and trustworthy.

### Pillar A — Data ingestion engine
**Owns:** turning raw signals (HealthKit samples, app events, and the things you
*tell* ARIA) into a clean, typed, personal model of you.
**Today (real code):** `routes/biometrics.py` → `biometrics/classify.py` →
`BodyModel` → `to_aria_context()`; `routes/health.py` (`/health/batch`) +
`normalization.py`; `storage/` single-table persistence.
**Plan:** §3.2 makes this the *single* canonical user-model builder that every
path consumes, and Pillar A is where §6's forecasting / anomaly / change-point
intelligence lives (behind the inference seam). Ingestion is also *conversational*:
what you say to ARIA day-to-day is ingested into Pillar C, not just numbers.

### Pillar B — Generative intelligence (Grok + Claude on AWS Bedrock)
**Owns:** the language and reasoning layer — a **multi-model** generative engine
that combines **Claude** (Sonnet 4.6 primary, Opus 4.7 verifier) and **Grok**
(`global.xai.grok-4.6`) on **Amazon Bedrock** to produce personalized health
insight and guidance.
**Today (real code):** the model roster already exists — `ai_router.default_models()`
defines slot 1 Claude Sonnet 4.6, slot 2 Claude Opus, and a third slot that
**currently defaults to Kimi K2.5 and must be removed** — the third slot becomes
Grok (`global.xai.grok-4.6`) or is dropped so the ensemble is exactly Grok + the
Claude family (see §5.2 for the exact Kimi references to destroy). The ARIA
*chat* path also still uses a **single** Bedrock model
(`aria_engine._default_converse`), so the Grok+Claude combination is not yet the
generative brain behind `/ai/chat`.
**Plan (first-class, was §5.2):** make ARIA's live path *be* this multi-model
generative layer — Claude and Grok reason in parallel, the existing consensus
finalizer (`ai_router._build_final_answer`) reconciles them, and selection is
**quality-weighted against Python-computed signals** (not first-wins). The
deterministic engine (`generate_response`) is always the floor and the guaranteed
fallback, and everything stays behind `ARIA_BEDROCK_ENABLED`. Combined with
tool-use (§5.1), Python owns the truth and Grok+Claude own the language.

> Why two model families: Claude for grounded, safety-aware coaching prose; Grok
> for a differently-trained second opinion that pressure-tests edge cases. The
> finalizer + signal-validation (§5.3) turns "two opinions" into one trustworthy
> answer instead of a coin flip.

### Pillar C — Companion memory (CoachContextEngine)
**Owns:** ARIA as a **lifestyle companion**, not a medical record. This is memory
of *your life*: goals, constraints, relationships, the recurring themes you talk
to ARIA about, what it advised and how that landed — the continuity that lets it
feel like it actually knows you.
**Today (real code):** `CoachContextEngine` (`aria_context.py`) already stores the
right *shape* — `lifestyle_tags`, `current_goals`, `constraints`,
`recent_patterns`, `last_insights`, `relationship_level` — in DynamoDB
(`ARIA#CONTEXT`). The gap is that it's barely wired into reasoning (§3.3).
**Plan:** treat Pillar C as life/relationship/conversation memory that ARIA reads
*and writes every turn*, and that it uses to *make changes* — proactively adjust
guidance, follow up on what you mentioned, and adapt tone as the relationship
deepens.

> **Explicit boundary — companion memory ≠ clinical record.** "Health data" in
> Pillar C means *life insight* ("training around a stressful stretch at work,"
> "sleep slips when travelling"), **not** clinical facts like a flu shot.
> Clinical facts stay in the permissioned `clinical_data` domain that ARIA may
> *reason over* when allowed (`apply_permissions`), but they are **not** what the
> companion remembers about you. This separation is a privacy and trust
> guarantee, and §3.3 / §6-RAG must honor it.

### SimRunner is CI, not ARIA
**SimRunner is testing infrastructure — a ship/hold gate — and is not part of
ARIA's runtime.** ARIA is not SimRunner and SimRunner is not ARIA; the Lambda
never imports `ai/simrunner/`.

Its job is to answer one question before code ships: **is ARIA still deterministic
and telling the truth?** It exercises ARIA across behavioral archetypes and
**fails the build** when ARIA:
- becomes non-deterministic (same input, different grade/type/direction — the
  `determinism_checker` already targets ≥80% and should be a hard gate),
- violates a safety/honesty rule (directional violations, confidently-wrong —
  the "mission-critical" gate in `diagnostics.py`),
- or regresses on the six evaluation dimensions beyond `gate_max_drop`.

**Plan (was Phase 5 "evaluate the real engine," now the point of SimRunner):**
today SimRunner scores a **stub** on a synthetic context, so it can pass while
production ARIA misbehaves. It must be pointed at the **real**
`aria_engine.generate_response` and wired as a **required CI check** (a true
ship/hold gate), so "ARIA is deterministic and honest" is *enforced*, not
aspirational. SimRunner stays strictly out of the runtime path.

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

## 2a. Companion persona: bond, humor, and the suggest-don't-prescribe line

ARIA's job is to become a **companion the user actually likes talking to** —
building a bond **organically through jokes, comments, and humor**, while always
grounded in **facts and advice**, and **never crossing into prescribing
treatment**. This is a first-class product requirement, not decoration.

**Where:** `ARIA_SYSTEM_PROMPT` (L123), `COACH_AGENTS` roster (L191–243),
`_structured_message` (L1257), SimRunner's `tone_compliance` /
`epistemic_honesty` / `directional_correctness` dimensions.

**What:**
- **Persona with range.** The "What I notice / One next step / Why" structure is
  good for clarity but can read clinical. Give the persona **warmth and humor as
  a controlled dimension**: light callbacks to shared history (from §3.3 memory),
  dry humor when the moment fits, encouragement that isn't cheerleading. Keep it
  a *voice*, not randomness — tone is prompt- and memory-driven, and bounded.
- **Bond via memory.** Real rapport comes from continuity (§3.3): remembering the
  wedding, the bad week, the running joke. Humor without memory is a chatbot;
  humor *with* memory is a companion.
- **The line: suggest, never prescribe — with an urgency carve-out.** Encode a
  **tiered** guardrail (per §0.4), not a blanket ban:
  - **Default (non-urgent):** ARIA offers and explains, but never diagnoses,
    never prescribes medication or treatment, and never implies clinical
    authority. This exists in prose today ("Do not prescribe… Never invent
    diagnoses").
  - **In-bounds:** generic, widely-known **first aid and safety** — how to apply
    a band-aid, basic first aid you'd give another person, and **telling the user
    to call 911 / emergency services** in an emergency. Withholding common-sense
    safety help is the wrong failure mode.
  - **Hard stop:** anything needing clinical judgment — diagnosing or managing
    serious/internal conditions (e.g. internal bleeding), prescribing, or
    implying medical authority. Here ARIA **names the concern and defers to a
    professional / emergency care**, it does not try to manage it.
  - **Rule of thumb encoded in the check:** *no diagnosis unless the situation is
    urgent and the guidance is generic first aid / 911 escalation.*
  Make it a **checked invariant**: a deterministic post-filter classifies output
  as suggest / generic-first-aid / prescribe-or-diagnose, allows the first two,
  rewrites or blocks the third, and SimRunner treats a prescription/serious-
  diagnosis as a **mission-critical violation** while *not* penalizing a valid
  first-aid/911 response (§5a).
- **Facts stay true.** Humor never distorts a number. The output-validation step
  (§5.3) guarantees the numbers are real; the persona only changes *how* they're
  said, never *what* is true.

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

### 3.3 Two-tier, human-like memory wired into the actual reasoning
**Where:** `CoachContextEngine` (`aria_context.py`), `user_model_block`
(aria_engine L644), route `aria.py` (L94–129), the DynamoDB `ttl` attribute
(already defined on the table in `infra/main.tf` L306–309 — reuse it).

Per §0.3, ARIA remembers **like a person**: a durable long-term store and a
transient short-term store, with an explicit consolidation/forgetting step. This
is **companion memory**, not a medical chart.

- **Long-term store (durable "what ARIA knows about you").** Expand the schema
  beyond `last_insights` + `relationship_level` to first-class **life-context**
  fields: stated goals and *why* they matter (events, people), preferences,
  constraints, recurring themes, running jokes/callbacks, sensitivities to avoid.
  Persisted under `ARIA#CONTEXT`, no TTL. Kept clearly separate from
  `clinical_data` (permission-gated, never the substance of rapport).
- **Short-term store (transient "what you're telling it now").** Event-anchored
  items like "wedding in three weeks" live under a separate short-term key (e.g.
  `ARIA#STM#...`) **with a DynamoDB `ttl`** set to the event/expiry horizon, so
  they auto-expire once complete and never clutter the durable model.
- **Consolidation / forgetting (ARIA evaluates its own memory).** On each turn (or
  a periodic pass), decide what **graduates** short-term → long-term (a durable
  takeaway like "cares about looking good for big events"), what **expires** (the
  specific date, once past), and what was never worth keeping. Forgetting is a
  designed step, not neglect.
- **Inject both tiers into reasoning.** Feed deduped long-term life-context +
  active (non-expired) short-term items + `build_rich_context` patterns
  (`low_readiness_streak`, `strong_sleep_recovery`) into `user_model_block` so
  memory enters both the deterministic engine and the Grok + Claude prompt — not
  just the cosmetic `memory_reference` prepend.
- **Write-back every substantive turn** (today `add_insight()` fires only on plan
  feedback) so ARIA can follow up naturally ("how'd the wedding photos go? your
  sleep held up the week before").
- **Extraction/consolidation is deterministic-first:** keyword/entity + simple
  date parsing, with an optional Bedrock structured pass (JSON) when enabled —
  always with the deterministic path as fallback, and always permission-aware.

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

### 5.2 The Grok + Claude ensemble is ARIA's generative engine
**Where:** `ai_router.route()` fan-out/consensus (L345), `default_models`
(L773), `select_model` (L775), Bedrock model access + IAM in
`infra/main.tf` (the `bedrock:*` statement L116–132) and the
`AI_ROUTER_MODEL_*` variables.

Per §0.2, multi-model isn't a hard-questions-only garnish — it **is** the brain.

**What:**
- **Standing ensemble = Grok + the Claude family, and nothing else.** Set the
  router slots to Claude (Opus/Sonnet by task via `select_model`) **and** Grok
  (xAI on Bedrock). Update `default_models`, the `AI_ROUTER_MODEL_*` env, and
  Terraform's Bedrock resource scope + model access to include the xAI model ARNs
  (today the IAM statement is Anthropic-only).
- **Destroy every Kimi / Moonshot reference (P0).** Kimi K2.5 is not part of
  ARIA. The third slot becomes Grok (or is dropped so the ensemble is exactly
  Claude + Grok). Every one of these must go — verified locations:
  - `infra/lambda/ai_router.py` L789–790 — the `"Kimi K2.5"` /
    `"moonshotai.kimi-k2.5"` slot-3 defaults.
  - `infra/main.tf` L453–454 — `AI_ROUTER_MODEL_3_ID/NAME` fallbacks to Kimi.
  - `infra/variables.tf` L95 — Kimi mentioned in the slot-3 description.
  - `infra/terraform.tfvars.example` L31 — "(Kimi K2.5)" comment.
  - `backend/README.md` L93, L96, L161, L163 — Kimi as slot-3 fallback prose.
  - `ai/simrunner/aria_simrunner/terraform_config.py` L29–30
    (`_ROUTER3_ID_FALLBACK` / `_ROUTER3_NAME_FALLBACK`);
    `backend_simulator/bedrock_catalog.py` L108–113;
    `aria_simrunner/model_archetypes.py` L221, L248; `lifetime_suite.py` L14.
  - Tests that assert the Kimi default: `tests/test_ai_router.py` (L94, L127,
    L190, L227, L255, L285, L315, L353) and
    `ai/simrunner/tests/test_terraform_config.py` (L29, L46–47, L55, L102–103,
    L205, L221, L228, L242) — update these to the Grok/Claude slots so the gate
    proves Kimi is gone rather than pinning it in place.
- **Blend, don't first-win.** Today the primary is the *fastest* success
  (L489). Replace with **quality selection / reconciliation**: run the existing
  consensus finalizer, and pick/merge the answer that best agrees with the
  Python-computed signals (§5.3). Claude and Grok disagreeing is *signal* — the
  finalizer reconciles, and low agreement lowers confidence honestly.
- **Tier by task.** Fast single-model (Claude Sonnet) for lookups/voice; full
  Claude + Grok ensemble for insights, deep-dives, and the `plan` type (§4.4).
- **Determinism preserved.** Ensemble runs only when `bedrock_enabled()`; the
  deterministic engine remains the guaranteed fallback (SimRunner enforces that
  the fallback still holds — §5a).

### 5.3 Validate model output against ground truth
**Where:** `_parse_model_envelope` / `_merge_live_envelope` (L1800).

**What:** after the model returns, verify every number in the prose exists in
the Python signal set (regex-extract numerics, cross-check against `card`
values within tolerance). On mismatch, drop to deterministic prose. This is a
cheap guardrail that makes the live path trustworthy.

---

## 5a. SimRunner: the ship/hold gate (CI, not ARIA)

**SimRunner is testing infrastructure, not intelligence.** ARIA is not
SimRunner and SimRunner is not ARIA. It never runs in the request path. Its sole
job is to answer, in CI, one question: **is this build of ARIA safe to ship?**

**What SimRunner must guard (its ship/hold contract):**
- **100% context fidelity via isometric algorithms** — SimRunner's reason to
  exist is proving ARIA uses *all* of its context, correctly, every time. Its
  **isometric (structure-preserving) test algorithms** hold behavior invariant
  under transformations that must not change the answer: re-ordered / re-expressed
  context → identical call, and the existing isometric-**exercise** discrimination
  so an isometric hold is never scored as high-intensity load.
- **Determinism** — the deterministic engine is reproducible; same seed/context →
  same grade + query type + directional call. The `determinism_checker` already
  targets ≥80% agreement across repeat runs; keep it a hard gate.
- **Truthfulness** — no invented numbers, no fabricated baselines, epistemic
  honesty under sparse data (confidence tracks coverage).
- **Suggest-not-prescribe (with the urgency carve-out)** — a serious diagnosis or
  a prescription is a **mission-critical** failure that **holds the ship**; a
  valid generic first-aid / 911-escalation response is **not** penalized (§2a,
  §0.4). Extend the safety rules to encode exactly that distinction.
- **Directional safety** — never push intensity when readiness is low, etc. (the
  rules already scored in `aria_evaluator`).
- **Tone** — companion warmth without cheerleading or evasion (`tone_compliance`).
- **Model-roster hygiene** — assert the ensemble is **Grok + Claude only**; fail
  if any Kimi/Moonshot id reappears (§5.2).

**The one change that makes the gate real:** point SimRunner at the **actual
`aria_engine.generate_response`** instead of its stub (§7), so the six-dimension
scores and regression gates measure *production* ARIA. Today they measure a
parallel stub on a richer context, so a green SimRunner doesn't prove the
shipped engine is safe. After this change:
- **Hold** the build if composite drops past `gate_max_drop`, if any
  mission-critical (prescription / confidently-wrong / directional) violation
  appears, or if determinism falls below target.
- **Ship** otherwise, with the per-archetype baselines updated.

This keeps the boundary clean: SimRunner **watches** ARIA; it is never part of
ARIA's runtime, and improving ARIA and improving SimRunner are separate work
items that meet only at the CI gate.

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
| P0 | **Destroy every Kimi/Moonshot reference** (code, TF, README, simrunner, tests) | 5.2 | low | none |
| P0 | One canonical user model (ingestion → merge 3 context builders) | 0.1, 3.2 | low | none |
| P0 | Personal baselines in interpreters + confidence | 3.1, 4.3 | low | 3.2 |
| P0 | Two-tier **human-like memory** (long-term + short-term, consolidate/forget) wired into reasoning | 0.3, 3.3 | low | none |
| P0 | Suggest-not-prescribe **with urgency/first-aid carve-out** as a checked invariant + tone | 0.4, 2a | low | none |
| P0 | SimRunner evaluates the **real** engine (100%-context/isometric ship/hold gate) | 0.5, 5a, 7 | low | none |
| P1 | Grok + Claude-family ensemble as ARIA's generative engine (no third vendor) | 0.2, 5.2 | med | Bedrock + TF (add xAI model access/IAM) |
| P1 | Evidence-graph fusion + cross-signal patterns | 4.1 | med | 3.1 |
| P1 | Port ACWR / sleep-debt / overtraining rules to prod | 4.2 | med | 3.2 |
| P1 | Missing interpreters (chronotype/progress/QoL) | 3.4 | low | none |
| P1 | Live tool-use (model narrates Python-computed truth) | 5.1 | med | Bedrock |
| P1 | Validate model output vs Python signals | 5.3 | low | none |
| P2 | Better intent classifier + emit `plan` type | 4.4 | med | none |
| P2 | Forecasting / multivariate anomaly / RAG (companion memory) | 6 | med-high | seam/layer |
| P2 | Module decomposition + typed protocols + hypothesis | 7 | low | none |

**Dependency vaccine:** everything P0/P1 is pure-Python and deterministic; only
tool-use, RAG, and multi-model reasoning touch Bedrock, and all keep the
deterministic fallback. Nothing here weakens the kill-switch or the privacy
redaction (`apply_permissions`, `user_model_block` restricted gating).

---

## 9. What "insanely smart" looks like when this lands

- **Ingests** cleanly, **reasons** with a Claude + Grok ensemble on AWS, and
  **remembers** the user's life — three roles, one coherent companion.
- Speaks to **your** baselines ("deep sleep is 22% below *your* 30-day median,
  and it's the third night — same pattern as before your last deload").
- **Reasons over combinations** (HRV↓ + load↑ + sleep-debt → one clear
  under-recovery story), not one metric at a time.
- **Remembers your life, not your chart** — the wedding, the bad week, the
  running joke — and follows up, building a real bond over time.
- **Has a voice** — warmth and humor grounded in shared history — while holding
  the line: it **suggests, it never prescribes or diagnoses**.
- **Never invents a number** — the ensemble narrates Python-computed truth via
  tool-use, validated before it's shown.
- **Knows what it doesn't know** — confidence is derived from coverage and
  model agreement, and it says so.
- Is **guarded by SimRunner as a ship/hold CI gate** (separate from ARIA) that
  holds any build that stops being deterministic, truthful, or starts
  prescribing — so "smarter" is provable, not vibes.

---

## 10. Out of scope

- No code changed for this plan; each item is a proposal to implement and test
  deliberately.
- No AWS/Bedrock enablement change (kill-switch stays off by default).
- No heavy dependency added to the Lambda hot path; ML/embeddings stay behind
  the existing inference seam or a layer.
