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

`contextual_learner.py`, `self_trainer.py`, and `context_plan.py` moved in
one commit because they reference each other via relative imports
(`from . import self_trainer`, `from .contextual_learner import ...`) —
splitting the move across commits would have left a broken import in
between.

`contextual_learner.load()`/`.save()` are the one exception to "no
storage coupling": they lazy-import `storage.dynamodb`/`storage.keys`
inside the function body, same convention as the rest of this Lambda
package. `adapt()` itself — the pure entry point SimRunner calls — never
reaches them.

## What's still pending

Not yet moved (dependency graph mapped, see `ARIA_INTELLIGENCE_PLAN.md`
P0-6): the `services/biometrics/` subpackage (`body_model.py` currently
imports `from services import aria_engine` at module level — circular
with `aria_engine.py`, needs untangling first), `fusion.py` (module-level
clean; its storage-touching functions are separately lazy-guarded), and
`aria_engine.py` itself. Once those move, SimRunner's stub
`aria_engine.py` gets replaced with real calls into `aria_core`, and a CI
script (matching `scripts/check-aria-web-research.py`) should enforce
that SimRunner never re-acquires a `services`/`storage` import.
