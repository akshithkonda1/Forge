"""Curated, keyless web reference lookup for the dummy ARIA orchestrator.

Mirrors ``AriaWebResearch.swift`` (``ForgeSwift/ForgeSwift/Services/``) on
purpose, same tradeoff and same reasoning: the user wants the dummy/local
orchestrator, when it runs on a real machine (a laptop, CI runner — "the
machine running the sim"), to reach the genuine web so an answer like "how
do I lose fat and gain muscle while keeping my frame" pulls in real outside
information instead of only reflecting synthetic sample data back — while
never touching Forge's own cloud/AWS resources, and never shipping or
requiring a provider API key. A real search API needs a key; this is the
keyless-safe alternative: a small, hand-picked set of stable, reputable
reference pages, fetched directly and read from — no search index, no
secret, nothing that can leak.

Deliberately isolated in its own module, exactly like the Swift original is
its own file. ``dummy_orchestrator.py``'s own doc comment claims "no
network" for everything else it does (no Bedrock, no live ``ARIAEngine``
call) — that claim needs to stay true for the rest of that module. The one
intentional exception to "no network calls anywhere in the dummy path"
lives entirely here, under its own name, so that invariant stays real
rather than just asserted in a comment the code no longer matches.
``test_web_research.py``'s
``test_only_referenced_from_dummy_orchestrator_and_its_own_tests`` enforces
the isolation, the same invariant ``scripts/check-aria-web-research.py``
checks for the Swift side — a standalone script on the Python side would be
a new pattern with no other precedent under ``scripts/`` (every existing
check there is Swift-specific); a test is how this package already enforces
everything else about itself.

Stdlib only, same constraint the rest of this package is built under
(``dummy_orchestrator.py``: "SimRunner stays stdlib-only and must not
import the Lambda package") — ``urllib.request`` for the fetch, ``re`` +
``html.unescape`` for extraction. No ``requests``, no ``boto3``, no cloud
SDK of any kind.
"""

from __future__ import annotations

import os
import re
from html import unescape
from urllib.error import HTTPError, URLError
from urllib.request import Request, urlopen

# Duplicated from ``dummy_orchestrator.py`` on purpose, same reasoning as
# that module's own duplicated ``_NEEDLES``: this check is structurally
# redundant today (``dummy_orchestrator.respond`` already calls
# ``refuse_if_cloud()`` before anything in this module runs), but it stays
# here anyway as a hard, local gate — the same defense-in-depth
# ``AriaWebResearch.lookUp`` keeps on the Swift side by re-checking
# ``AriaOperatingMode.current.isLocalTesting`` even though its only caller
# is already gated. A future call site added to this module without going
# through ``dummy_orchestrator`` first must not silently turn a keyless
# reference fetch into a network-egress surface running somewhere it
# shouldn't.
_PROD_LIKE = frozenset({"prod", "production", "staging", "stage"})
_CLOUD_RUNTIME_ENV = (
    "AWS_LAMBDA_FUNCTION_NAME",
    "AWS_EXECUTION_ENV",
    "AWS_LAMBDA_RUNTIME_API",
    "K_SERVICE",
    "FUNCTION_TARGET",
    "WEBSITE_INSTANCE_ID",
)


def _running_on_cloud_or_prod() -> bool:
    if (os.getenv("ENVIRONMENT") or "").strip().lower() in _PROD_LIKE:
        return True
    return any(os.getenv(key) for key in _CLOUD_RUNTIME_ENV)

# Six seconds, same bound as the Swift version. A slow or wedged fetch
# degrading to a missed lookup is fine; that fetch stalling the whole turn
# is exactly the "ARIA feels broken" regression this module exists to avoid
# reintroducing on the Python side.
_TIMEOUT_SECONDS = 6.0

_MAX_SNIPPET_CHARS = 2000

# Research-flavored phrasing only — not every message that happens to touch
# training, food, or progress. Kept identical to
# ``AriaWebResearch.researchPhrases`` on purpose: one list, ported not
# reinvented, so the two platforms trigger on the same turns.
_RESEARCH_PHRASES = (
    "how do i", "how to", "best way to", "is it true", "what does the science say",
    "what does research say", "research shows", "studies show", "recomp",
    "lose fat and gain muscle", "gain muscle and lose fat", "how much protein should",
    "is it possible to", "how long does it take to", "evidence for", "evidence on",
)

# Same three domains and the same three sources ``AriaWebResearch.swift``
# already vetted for stability (long-standing government health references,
# not pages likely to move or go JS-only) — reused rather than re-chosen, so
# a spot-check done for one platform covers both. Keyed by the dummy
# orchestrator's coach-agent kinds, not the Swift side's ``AriaLocalDomain``
# names: workout↔training, lifestyle↔nutrition (fuel folded into lifestyle
# on both platforms), progress↔progress.
#
# Could not be live-verified from this development environment either — its
# outbound HTTPS goes through a proxy that returned "Tunnel connection
# failed: 403 Forbidden" for medlineplus.gov, the same shape of finding the
# Swift file's own comment documents (EGRESS_BLOCKED there). ``look_up``
# caught it correctly and returned ``None``, exactly as designed — but this
# table, like the Swift one, should be spot-checked from an unsandboxed
# machine the first time this feature is exercised for real.
_SOURCES: dict[str, tuple[str, str]] = {
    "workout": (
        "MedlinePlus: Exercise and Physical Fitness",
        "https://medlineplus.gov/exerciseandphysicalfitness.html",
    ),
    "lifestyle": (
        "NIH Office of Dietary Supplements: Protein",
        "https://ods.od.nih.gov/factsheets/Protein-Consumer/",
    ),
    "progress": (
        "CDC: Physical Activity Guidelines for Adults",
        "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html",
    ),
}

_TAG_BLOCK_RE = re.compile(r"(?is)<(script|style)[^>]*>.*?</\1>")
_TAG_RE = re.compile(r"<[^>]+>")
_WHITESPACE_RE = re.compile(r"\s+")


def is_research_worthy(message: str, kind: str) -> bool:
    """Same gating as the Swift side: a curated domain, and phrasing that
    actually asks for outside information rather than just mentioning the
    topic."""
    if kind not in _SOURCES:
        return False
    lower = message.lower()
    return any(phrase in lower for phrase in _RESEARCH_PHRASES)


def _extract_text(html: str) -> str | None:
    """Plain regex tag-stripping, matching the Swift implementation's own
    reasoning: a curated handful of static reference pages doesn't need
    full HTML rendering, just readable body text — and stdlib has no HTML
    parser that isn't either a bigger dependency than this warrants or,
    like ``html.parser``, still needs the same tag-stripping approach
    underneath. ``html.unescape`` (stdlib) decodes every standard named and
    numeric entity, a genuine improvement on the Swift side's hand-rolled
    four-entity table."""
    stripped = _TAG_BLOCK_RE.sub(" ", html)
    stripped = _TAG_RE.sub(" ", stripped)
    stripped = unescape(stripped)
    collapsed = _WHITESPACE_RE.sub(" ", stripped).strip()
    if not collapsed:
        return None
    return collapsed[:_MAX_SNIPPET_CHARS]


def look_up(kind: str) -> str | None:
    """Returns a short, cited snippet, or ``None`` on anything short of
    success — timeout, bad status, empty extracted text, or a kind with no
    curated source. Callers fall back to their existing local generation,
    the same contract every other lazy-note function in this codebase uses:
    nil means "show the local read," never a fake citation.

    A raw ``urlopen`` GET to a public reference URL — no AWS SDK, no
    credentials, no Forge backend involved at any point — gated here
    independently of ``dummy_orchestrator.py``'s own ``refuse_if_cloud()``
    call, as defense in depth rather than because either check alone is
    thought to be insufficient.
    """
    if _running_on_cloud_or_prod():
        return None
    source = _SOURCES.get(kind)
    if source is None:
        return None
    title, url = source

    request = Request(url, headers={"User-Agent": "Forge-SimRunner/1.0"})
    try:
        with urlopen(request, timeout=_TIMEOUT_SECONDS) as response:
            if response.status != 200:
                return None
            raw = response.read()
    except (HTTPError, URLError, TimeoutError, OSError, ValueError):
        return None

    try:
        html = raw.decode("utf-8")
    except UnicodeDecodeError:
        html = raw.decode("iso-8859-1", errors="replace")

    text = _extract_text(html)
    if not text:
        return None
    return f"From {title}: {text}"
