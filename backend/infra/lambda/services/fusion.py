"""Backward-compat shim. Real module moved to aria_core (genuinely
stdlib-only, so SimRunner can import it without reaching into the rest of
this Lambda package — see aria_core/README.md and
ARIA_INTELLIGENCE_PLAN.md P0-6). Every existing `from services import
fusion` / `from services.fusion import X` caller keeps working unchanged:
this aliases sys.modules so the old path *is* the new module, public and
private names alike.

fusion.py and aria_engine.py moved together in the same commit: fusion
imports aria_engine at module level (BodyModel projection needs
ARIAContext), and aria_engine lazily imports fusion inside
generate_response() (stance_for_plan drives the persona stance on
generate_response()'s main path) — the same "move tightly-coupled
files together or the relative imports break in between" reasoning as
the earlier contextual_learner/self_trainer/context_plan batch."""

import sys

from aria_core import fusion as _real

sys.modules[__name__] = _real
