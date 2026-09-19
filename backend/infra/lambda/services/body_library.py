"""Backward-compat shim. Real module moved to aria_core (genuinely
stdlib-only, so SimRunner can import it without reaching into the rest of
this Lambda package — see aria_core/README or ARIA_INTELLIGENCE_PLAN.md P0-6).
Every existing `from services import body_library` /
`from services.body_library import X` caller keeps working unchanged: this
aliases sys.modules so the old path *is* the new module, public and
private names alike."""

import sys

from aria_core import body_library as _real

sys.modules[__name__] = _real
