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

_AGING_PHRASES = (
    "training age", "biological age", "fitness age", "calendar age",
    "vascular age", "inner age", "metabolic age", "phenotypic age",
    "vo2 max", "vo2max", "cardiorespiratory", "cardio fitness",
    "how old am i", "age comparison",
)

# Same sources ``AriaWebResearch.swift`` / ``AriaReferenceCatalog`` already
# vetted. Aging is the one domain allowed to fetch in a live session on iOS;
# here it is available to the dummy whenever the question is about training age.
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
    "aging": (
        "MedlinePlus: Exercise Stress Test / VO2",
        "https://medlineplus.gov/ency/article/003394.htm",
    ),
}

_TAG_BLOCK_RE = re.compile(r"(?is)<(script|style)[^>]*>.*?</\1>")
_TAG_RE = re.compile(r"<[^>]+>")
_WHITESPACE_RE = re.compile(r"\s+")


def suggests_aging(message: str) -> bool:
    lower = message.lower()
    return any(phrase in lower for phrase in _AGING_PHRASES)


def is_research_worthy(message: str, kind: str) -> bool:
    """Same gating as the Swift side: a curated domain, and phrasing that
    actually asks for outside information rather than just mentioning the
    topic. Aging questions always fetch — training age is more accurate
    with a live public cardio-fitness page.
    """
    if suggests_aging(message) or kind == "aging":
        return True
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


# ---------------------------------------------------------------------------
# Expanded outside context — opt-in for SimRunner (``FORGE_DUMMY_WEB=1``).
#
# SimRunner is offline and deterministic by default and CI grades it against
# committed baselines, so everything below stays dark unless a person asks
# for it. The iOS Dummy (``AriaWebResearch.swift``) runs the same sources by
# default. Order of preference for a research need:
#
#   1. ARIA Scout (``FORGE_SCOUT_URL``) — the agentic research computer:
#      SearXNG over Google/Bing/DDG/Brave + Grok on Bedrock, cited brief.
#   2. Keyless public health search — MedlinePlus, PubMed, openFDA.
#   3. The curated catalog below.
#
# Only a scrubbed keyword query ever leaves the machine (``perception``
# already ran it through ``backend.scout.privacy.scrub_query``). Weather and
# air use coordinates rounded to one decimal (~11 km).
# ---------------------------------------------------------------------------

import json  # noqa: E402
import xml.etree.ElementTree as ET  # noqa: E402
from dataclasses import dataclass, field  # noqa: E402
from urllib.parse import quote, urlencode, urlparse  # noqa: E402

from .perception import EnvironmentRead, ResearchNeed  # noqa: E402

_WEB_FLAGS = frozenset({"1", "true", "yes", "on"})
_MAX_EVIDENCE_CHARS = 420

# Wider curated shelf for research needs. Kept apart from ``_SOURCES`` so
# ``look_up`` / ``is_research_worthy`` behave exactly as before.
_TOPIC_SOURCES: dict[str, tuple[str, str]] = {
    "training": ("CDC: Adult Physical Activity Guidelines", "https://www.cdc.gov/physical-activity-basics/guidelines/adults.html"),
    "nutrition": ("NIH ODS: Protein", "https://ods.od.nih.gov/factsheets/Protein-Consumer/"),
    "sleep": ("CDC: Sleep and Health", "https://www.cdc.gov/sleep/about/index.html"),
    "readiness": ("MedlinePlus: Exercise and Physical Fitness", "https://medlineplus.gov/exerciseandphysicalfitness.html"),
    "cycle": ("MedlinePlus: Menstruation", "https://medlineplus.gov/menstruation.html"),
    "fever": ("MedlinePlus: Fever", "https://medlineplus.gov/fever.html"),
    "heat": ("MedlinePlus: Heat Illness", "https://medlineplus.gov/heatillness.html"),
    "lifestyle": ("MedlinePlus: Healthy Living", "https://medlineplus.gov/healthy-living.html"),
}


@dataclass
class Evidence:
    """Outside knowledge for one turn. Untrusted data — never user facts."""

    text: str
    sources: list[dict] = field(default_factory=list)
    via: str = "catalog"  # scout | medlineplus | pubmed | openfda | catalog
    confidence: float = 0.5

    def as_dict(self) -> dict:
        return {"text": self.text, "sources": list(self.sources), "via": self.via, "confidence": self.confidence, "untrusted": True}

    def cite(self) -> str:
        host = ""
        if self.sources:
            host = urlparse(str(self.sources[0].get("url") or "")).hostname or ""
        label = host.removeprefix("www.") if host else self.via
        return f"From {label}: {self.text}"


def web_enabled() -> bool:
    if _running_on_cloud_or_prod():
        return False
    return (os.getenv("FORGE_DUMMY_WEB") or "").strip().lower() in _WEB_FLAGS


def _get(url: str, *, accept: str = "application/json", timeout: float = _TIMEOUT_SECONDS) -> bytes | None:
    request = Request(url, headers={"User-Agent": "Forge-SimRunner/1.0", "Accept": accept})
    try:
        with urlopen(request, timeout=timeout) as response:
            if response.status != 200:
                return None
            return response.read(1024 * 1024)
    except (HTTPError, URLError, TimeoutError, OSError, ValueError):
        return None


def _clip(text: str, limit: int = _MAX_EVIDENCE_CHARS) -> str:
    text = _WHITESPACE_RE.sub(" ", unescape(_TAG_RE.sub(" ", str(text or "")))).strip()
    if len(text) <= limit:
        return text
    cut = text[:limit]
    return (cut[: cut.rfind(".") + 1] if "." in cut else cut.rstrip() + "…")


# --- parsers (pure; unit-tested with fixtures) -------------------------------


def parse_medlineplus(body: bytes) -> list[dict]:
    """MedlinePlus health-topic search XML → [{title, url, summary}]."""
    try:
        root = ET.fromstring(body)
    except ET.ParseError:
        return []
    rows: list[dict] = []
    for doc in root.iter("document"):
        fields = {c.get("name"): "".join(c.itertext()) for c in doc.findall("content")}
        title = _clip(fields.get("title") or "", 160)
        summary = _clip(fields.get("FullSummary") or fields.get("snippet") or "")
        url = doc.get("url") or ""
        if title and summary and url.startswith("https://"):
            rows.append({"title": title, "url": url, "summary": summary})
    return rows


def parse_pubmed_ids(body: bytes) -> list[str]:
    try:
        ids = json.loads(body)["esearchresult"]["idlist"]
    except (ValueError, KeyError, TypeError):
        return []
    return [str(i) for i in ids if str(i).isdigit()][:3]


def parse_pubmed_summaries(body: bytes) -> list[dict]:
    try:
        result = json.loads(body)["result"]
        uids = result["uids"]
    except (ValueError, KeyError, TypeError):
        return []
    rows = []
    for uid in uids:
        row = result.get(uid) or {}
        title = _clip(row.get("title") or "", 240)
        if title:
            rows.append({
                "title": title,
                "journal": str(row.get("source") or ""),
                "year": str(row.get("pubdate") or "")[:4],
                "url": f"https://pubmed.ncbi.nlm.nih.gov/{uid}/",
            })
    return rows


def parse_openfda_label(body: bytes) -> dict | None:
    try:
        row = json.loads(body)["results"][0]
    except (ValueError, KeyError, IndexError, TypeError):
        return None
    def first(key: str) -> str:
        value = row.get(key) or []
        return _clip(value[0] if isinstance(value, list) and value else str(value or ""), 300)
    names = (row.get("openfda") or {}).get("generic_name") or (row.get("openfda") or {}).get("brand_name") or []
    use = first("indications_and_usage") or first("purpose")
    warn = first("warnings") or first("boxed_warning")
    if not (use or warn):
        return None
    return {"name": str(names[0]) if names else "", "use": use, "warnings": warn}


def parse_environment(forecast: bytes | None, air: bytes | None) -> EnvironmentRead | None:
    """Open-Meteo forecast + air-quality JSON → ``EnvironmentRead``."""
    current: dict = {}
    aq: dict = {}
    try:
        current = json.loads(forecast)["current"] if forecast else {}
    except (ValueError, KeyError, TypeError):
        current = {}
    try:
        aq = json.loads(air)["current"] if air else {}
    except (ValueError, KeyError, TypeError):
        aq = {}
    if not current and not aq:
        return None

    def num(src: dict, key: str):
        value = src.get(key)
        return float(value) if isinstance(value, (int, float)) else None

    aqi = num(aq, "us_aqi")
    is_day = current.get("is_day")
    return EnvironmentRead(
        apparent_temp_c=num(current, "apparent_temperature") if num(current, "apparent_temperature") is not None else num(current, "temperature_2m"),
        uv_index=num(current, "uv_index"),
        us_aqi=int(aqi) if aqi is not None else None,
        precipitation_mm=num(current, "precipitation"),
        is_day=bool(is_day) if is_day in (0, 1) else None,
        source="open-meteo",
    )


# --- fetchers (gated) --------------------------------------------------------


def environment(lat: float, lon: float) -> EnvironmentRead | None:
    """Weather + air for a coarse location. ``None`` when web is off or down."""
    if not web_enabled():
        return None
    lat, lon = round(float(lat), 1), round(float(lon), 1)
    forecast = _get(
        "https://api.open-meteo.com/v1/forecast?"
        + urlencode({
            "latitude": lat, "longitude": lon, "timezone": "auto", "forecast_days": 1,
            "current": "temperature_2m,apparent_temperature,precipitation,uv_index,is_day",
        })
    )
    air = _get(
        "https://air-quality-api.open-meteo.com/v1/air-quality?"
        + urlencode({"latitude": lat, "longitude": lon, "current": "us_aqi,pm2_5"})
    )
    return parse_environment(forecast, air)


def _scout(need: ResearchNeed) -> Evidence | None:
    url = (os.getenv("FORGE_SCOUT_URL") or "").strip()
    if not url.startswith("https://"):
        return None
    headers = {"Content-Type": "application/json", "User-Agent": "Forge-SimRunner/1.0"}
    token = (os.getenv("FORGE_SCOUT_TOKEN") or "").strip()
    key = (os.getenv("FORGE_SCOUT_KEY") or "").strip()
    if token:
        headers["Authorization"] = f"Bearer {token}"
    if key:
        headers["x-scout-key"] = key
    body = json.dumps({"query": need.query, "topic": need.topic}).encode()
    try:
        with urlopen(Request(url, data=body, headers=headers, method="POST"), timeout=28) as response:
            if response.status != 200:
                return None
            brief = json.loads(response.read(512 * 1024))
    except (HTTPError, URLError, TimeoutError, OSError, ValueError):
        return None
    return evidence_from_brief(brief)


def evidence_from_brief(brief: dict) -> Evidence | None:
    """Scout brief JSON → ``Evidence``. Rejects briefs whose points cite nothing."""
    if not isinstance(brief, dict) or not brief.get("answer"):
        return None
    sources = [s for s in brief.get("sources") or [] if isinstance(s, dict) and str(s.get("url", "")).startswith("https://")]
    if not sources:
        return None
    try:
        confidence = float(brief.get("confidence") or 0.5)
    except (TypeError, ValueError):
        confidence = 0.5
    return Evidence(
        text=_clip(brief["answer"]),
        sources=[{"title": str(s.get("title") or ""), "url": s["url"]} for s in sources[:4]],
        via="scout",
        confidence=confidence,
    )


def _health_search(need: ResearchNeed) -> Evidence | None:
    term = quote(need.query)
    medline = _get(f"https://wsearch.nlm.nih.gov/ws/query?db=healthTopics&retmax=2&term={term}", accept="application/xml")
    rows = parse_medlineplus(medline) if medline else []
    if rows:
        top = rows[0]
        return Evidence(text=top["summary"], sources=[{"title": top["title"], "url": top["url"]}], via="medlineplus", confidence=0.7)
    if need.topic == "nutrition" or any(w in need.query for w in ("dose", "dosage", "side", "drug", "medication", "pill")):
        label = _get(f"https://api.fda.gov/drug/label.json?limit=1&search={quote('openfda.generic_name:' + chr(34) + need.query.split(' ')[0] + chr(34))}")
        parsed = parse_openfda_label(label) if label else None
        if parsed:
            text = parsed["warnings"] or parsed["use"]
            return Evidence(text=text, sources=[{"title": f"FDA label: {parsed['name']}", "url": "https://open.fda.gov/apis/drug/label/"}], via="openfda", confidence=0.6)
    ids_body = _get(
        "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esearch.fcgi?"
        + urlencode({"db": "pubmed", "term": need.query, "retmax": 3, "retmode": "json", "sort": "relevance"})
    )
    ids = parse_pubmed_ids(ids_body) if ids_body else []
    if ids:
        summary = _get(
            "https://eutils.ncbi.nlm.nih.gov/entrez/eutils/esummary.fcgi?"
            + urlencode({"db": "pubmed", "id": ",".join(ids), "retmode": "json"})
        )
        papers = parse_pubmed_summaries(summary) if summary else []
        if papers:
            lead = papers[0]
            text = f"Recent research includes \"{lead['title']}\" ({lead['journal']}, {lead['year']})."
            return Evidence(text=text, sources=[{"title": p["title"], "url": p["url"]} for p in papers], via="pubmed", confidence=0.55)
    return None


def _catalog(need: ResearchNeed) -> Evidence | None:
    title, url = _TOPIC_SOURCES.get(need.topic, _TOPIC_SOURCES["lifestyle"])
    raw = _get(url, accept="text/html")
    if not raw:
        return None
    text = _extract_text(raw.decode("utf-8", errors="replace"))
    if not text:
        return None
    return Evidence(text=_clip(text), sources=[{"title": title, "url": url}], via="catalog", confidence=0.45)


def research(need: ResearchNeed) -> Evidence | None:
    """Best outside evidence for one need: Scout → health APIs → catalog."""
    if not web_enabled() or not need.query:
        return None
    for source in (_scout, _health_search, _catalog):
        evidence = source(need)
        if evidence is not None and evidence.text:
            return evidence
    return None
