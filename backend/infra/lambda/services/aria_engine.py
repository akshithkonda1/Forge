"""Backward-compat shim. Real module moved to aria_core (genuinely
stdlib-only, so SimRunner can import it without reaching into the rest of
this Lambda package — see aria_core/README.md and
ARIA_INTELLIGENCE_PLAN.md P0-6). Every existing `from services import
aria_engine` / `from services.aria_engine import X` caller keeps working
unchanged: this aliases sys.modules so the old path *is* the new module,
public and private names alike.

This was the last and largest piece of the P0-6 decomposition: every
lazy import inside aria_engine.py that used to read `from services import
X` for an already-moved sibling (guidance, aria_evidence,
contextual_learner, fusion, body_library, biometrics.estimators) now
reads `from . import X` / `from .biometrics import X` instead, so the
module is genuinely self-contained within aria_core and never reaches
back into `services` at all."""

import sys

from aria_core import aria_engine as _real

sys.modules[__name__] = _real
