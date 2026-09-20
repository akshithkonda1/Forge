# aria_core

Genuinely stdlib-only ARIA reasoning logic. No `boto3`, no `storage`, no
`services` (the rest of the Lambda package), at module level or in any lazy
import reachable from a pure call path.

## Why this package exists

`backend/ai/simrunner/` grades ARIA's coaching policy on a laptop, with no
AWS credentials. Its own rule (stated in `dummy_orchestrator.py`,
`web_research.py`, `prompts.py`, `data_generator.py`): SimRunner must not
import the Lambda package. Before this package existed, the only way to
satisfy that rule was for SimRunner to run against its own stub
`aria_engine.py` — not the real production reasoning. `aria_core` is the
real logic, factored out so SimRunner can import *it* directly and grade
the actual policy instead of a stand-in. See `ARIA_INTELLIGENCE_PLAN.md`
P0-6 for the full background.

## Why it lives inside `backend/infra/lambda/`

`backend/infra/main.tf`'s `archive_file.backend_lambda` zips
`source_dir = "${path.module}/lambda"` for the real Lambda deployment —
only that directory tree. A module needed at runtime that lived outside
it would fail with `ImportError` in production, silently, since no local
test tooling enforces that boundary (tests bootstrap their own `sys.path`
separately). Keeping `aria_core` at `backend/infra/lambda/aria_core/`
means it ships inside the existing zip with zero Terraform changes.

## The shim pattern

Every module moved here leaves a backward-compat shim at its old
`services/<name>.py` path:

```python
import sys
from aria_core import <name> as _real
sys.modules[__name__] = _real
```

This makes `services.<name>` *be* `aria_core.<name>` — not a copy, not a
`from X import *` (which would drop private/underscore-prefixed names).
Every existing `from services import <name>` and
`from services.<name> import X` caller across the Lambda package and its
tests keeps working unchanged. New code should import from `aria_core`
directly; the `services` shim exists for callers that predate the move.

## What's here

Moved so far (each with a `services/` shim):

- `guidance.py` — 4-band medical-safety guidance system
- `aria_evidence.py` — evidence/load derivation
- `body_library.py` — body-composition reference tables
- `contextual_parsing.py` — free-text parsing helpers
- `contextual_learner.py` — ARIA's online learner (Dirichlet posteriors,
  TD(0) Q-table, priority ranker, `adapt()`/`apply_chat_turn()`)
- `self_trainer.py` — self-training critic (predicted-vs-actual judgment,
  `td_alpha` meta-optimization); only ever called from `contextual_learner`
- `context_plan.py` — raw-signal supervision plan (aging pace as a
  wear/repair read, stress algorithm, plan choice); cross-references
  `contextual_learner` by relative import, so the two must move and stay
  together
- `biometrics/` — `body_model.py` (HealthKit-observation projection into
  `ARIAContext`) plus `aging_norms.py`/`classify.py`/`estimators.py`/
  `inference.py`/`statistics.py`/`types.py`; `body_model.py`'s only
  `aria_engine` use is now a lazy import inside `to_aria_context()`, so the
  subpackage needed nothing from the rest of the Lambda package at import
  time
- `fusion.py` — turn fusion (`fuse_turn`), directional-safety stance gate
  (`stance_for_plan`); moved together with `aria_engine.py` since fusion
  imports it at module level and `aria_engine.generate_response()` lazily
  imports fusion back
- `aria_engine.py` — the real production reasoning engine
  (`ARIAContext`/`generate_response`/interpreters); every lazy import
  inside it that used to read `from services import X` for an
  already-moved sibling now reads `from . import X` / `from .biometrics
  import X` instead, so it never reaches back into `services` at all.
  This was the last and largest piece of the P0-6 decomposition:
  `DummyARIAEngine.respond()` (SimRunner's `--test-ready --gate` engine)
  now calls real `fuse_turn()` + real `generate_response()` through
  `dummy_orchestrator.respond(engine="lambda")`, not a scripted stub —
  see the "Update 2026-09-20" note in `ARIA_INTELLIGENCE_PLAN.md` P0-6
- `quality_of_life.py` — holistic multi-pillar life score, ported from
  ForgeCore's `QualityOfLifeCalculator.swift`; pure scoring only (see the
  module's own docstring for what was and wasn't ported). Not yet wired
  into `aria_engine`'s context/interpreters — `aria_evidence.detect_pattern`
  still treats Lifestyle QoL as client-authored only; that integration is
  a deliberately deferred product decision, not an oversight
- `circadian_rhythm.py` — the two-process model of alertness (Borbély,
  1982), ported in full from ForgeCore's `CircadianRhythm.swift`: sleep
  need/debt estimation, circular-mean phase estimation from raw nights,
  the energy curve (process S + process C + the empirical afternoon dip),
  and the named-window schedule (grogginess/morning peak/afternoon dip/
  evening peak/melatonin window/winding down/sleep). Ported in full, not
  partially -- the Swift file is self-contained pure date/hour arithmetic
  with no other-file dependency. Also not yet wired into `aria_engine`
- `sleep_depth_scorer.py` — sleep score versus this person's own nights,
  blended with population chronotype targets until the personal baseline
  is thick enough to trust (cold start → blended → fully personal as
  observed nights accumulate); ported from ForgeCore's
  `SleepDepthScorer.swift`. Depends on `biometrics/statistics.py`'s
  `OnlineStat` — porting this surfaced and fixed a real divergence from
  `OnlineStat.swift`'s own stated contract ("share one definition of
  'unusual for you'"): `OnlineStat.zscore()` returned a flat 0.0 against a
  dead-flat baseline instead of Swift's large-magnitude signed fallback,
  silently hiding a genuine outlier. Not ported: `SleepDepthBaselineStore`
  (UserDefaults persistence, iOS-only, same reasoning as
  `QualityOfLifeLivingStore`)

`contextual_learner.py`, `self_trainer.py`, and `context_plan.py` moved in
one commit because they reference each other via relative imports
(`from . import self_trainer`, `from .contextual_learner import ...`) —
splitting the move across commits would have left a broken import in
between. `biometrics/`, `fusion.py`, and `aria_engine.py` moved together
for the same reason (see each shim's own docstring in `services/` for the
exact coupling that forced the joint move).

`contextual_learner.load()`/`.save()` are the one exception to "no
storage coupling": they lazy-import `storage.dynamodb`/`storage.keys`
inside the function body, same convention as the rest of this Lambda
package. `adapt()` itself — the pure entry point SimRunner calls — never
reaches them.

## What's still pending

Everything mapped in `ARIA_INTELLIGENCE_PLAN.md` P0-6 has moved.
`quality_of_life.py` (above) is a new port, not a move — it has no
`services/` shim because nothing under `services/` ever called it; new
code should import it from `aria_core` directly, same as any other module
here. A CI script (matching `scripts/check-aria-web-research.py`) that
enforces SimRunner never re-acquiring a `services`/`storage` import is
still not written.
