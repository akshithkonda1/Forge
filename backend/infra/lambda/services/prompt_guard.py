"""Backward-compat shim. Real module is aria_core.prompt_guard."""

import sys

from aria_core import prompt_guard as _real

sys.modules[__name__] = _real
