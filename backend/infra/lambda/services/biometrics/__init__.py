"""Backward-compat shim package. Real subpackage moved to aria_core/biometrics
(genuinely stdlib-only — body_model.py's only aria_engine use is now a lazy
import inside to_aria_context(), so this whole subpackage no longer needs
the rest of the Lambda package at import time; see aria_core/README.md and
ARIA_INTELLIGENCE_PLAN.md P0-6). Every existing `from services.biometrics
import X`, `from services import biometrics`, and `from
services.biometrics.<submodule> import X` caller keeps working unchanged:
this aliases sys.modules for the package *and* every submodule so each old
path *is* the new module, public and private names alike — a package needs
one alias per submodule, not just the top-level one, because Python's
import machinery resolves `services.biometrics.body_model` by checking
sys.modules for that exact dotted key before it would ever consult this
package's __path__.
"""

import sys

from aria_core import biometrics as _real
from aria_core.biometrics import (
    aging_norms as _aging_norms,
    body_model as _body_model,
    classify as _classify,
    estimators as _estimators,
    inference as _inference,
    statistics as _statistics,
    types as _types,
)

sys.modules[__name__] = _real
sys.modules[f"{__name__}.body_model"] = _body_model
sys.modules[f"{__name__}.classify"] = _classify
sys.modules[f"{__name__}.estimators"] = _estimators
sys.modules[f"{__name__}.inference"] = _inference
sys.modules[f"{__name__}.statistics"] = _statistics
sys.modules[f"{__name__}.types"] = _types
sys.modules[f"{__name__}.aging_norms"] = _aging_norms
