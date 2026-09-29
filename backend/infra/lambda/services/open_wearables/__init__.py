"""Open Wearables → Forge ingest adapter (scaffold).

Maps Momentum's unified webhook / timeseries schema onto Forge's kebab-case
SI-aligned metric vocabulary, then onto the existing ``/health/batch`` and
``/ai/observe`` payloads. Identity is always the Cognito ``sub`` — never the
Open Wearables user id.
"""

from .mapping import AdaptedIngest, adapt_webhook
from .vocabulary import FORGE_METRICS, map_open_wearables_type

__all__ = [
    "AdaptedIngest",
    "FORGE_METRICS",
    "adapt_webhook",
    "map_open_wearables_type",
]
