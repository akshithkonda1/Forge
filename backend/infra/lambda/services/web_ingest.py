"""SSRF-safe URL fetch + typed extraction for POST /ingest/url.

Stdlib only (html.parser, http.client, ipaddress, json). No scrape APIs.
Tests inject resolver/transport so this module never opens a live socket
under unittest.
"""

from __future__ import annotations

import html as html_lib
import http.client
import ipaddress
import json
import re
import socket
import ssl
from dataclasses import dataclass, field
from html.parser import HTMLParser
from typing import Any, Callable, Iterable
from urllib.parse import urljoin, urlparse

from responses import RouteError


MAX_BODY_BYTES = 512 * 1024
TIMEOUT_SECONDS = 8.0
MAX_REDIRECTS = 3
MAX_READABLE_CHARS = 8_000
ALLOWED_PORTS = {443}
ALLOWED_SCHEMES = {"https"}
ALLOWED_CONTENT_TYPES = frozenset(
    {
        "text/html",
        "application/xhtml+xml",
        "text/plain",
        "application/ld+json",
    }
)
BLOCKED_HOSTS = frozenset(
    {
        "localhost",
        "metadata",
        "metadata.google.internal",
    }
)
USER_AGENT = "ForgeIngest/0.1 (+https://github.com/akshithkonda1/Forge)"
ACCEPT_HEADER = (
    "text/html,application/xhtml+xml,application/ld+json,text/plain;q=0.9"
)

KIND_RECIPE = "recipe"
KIND_EXERCISE_PLAN = "exercise-plan"
KIND_HOWTO = "how-to"
KIND_ARTICLE = "article"
KIND_GENERIC = "generic"

_KIND_PRIORITY = (
    KIND_RECIPE,
    KIND_EXERCISE_PLAN,
    KIND_HOWTO,
    KIND_ARTICLE,
    KIND_GENERIC,
)

_SCHEMA_TO_KIND = {
    "recipe": KIND_RECIPE,
    "exerciseplan": KIND_EXERCISE_PLAN,
    "howto": KIND_HOWTO,
    "article": KIND_ARTICLE,
    "newsarticle": KIND_ARTICLE,
    "blogposting": KIND_ARTICLE,
}

_KIND_TO_DOMAIN = {
    KIND_RECIPE: "nutrition",
    KIND_EXERCISE_PLAN: "training",
    KIND_HOWTO: "lifestyle",
    KIND_ARTICLE: "lifestyle",
    KIND_GENERIC: "lifestyle",
}

_KIND_TO_FOLDER = {
    KIND_RECIPE: "healthHistory",
    KIND_EXERCISE_PLAN: "goals",
    KIND_HOWTO: "lifestyle",
    KIND_ARTICLE: "lifestyle",
    KIND_GENERIC: "lifestyle",
}

_KIND_TO_CATEGORY = {
    KIND_RECIPE: "recipe",
    KIND_EXERCISE_PLAN: "plan",
    KIND_HOWTO: "note",
    KIND_ARTICLE: "note",
    KIND_GENERIC: "note",
}

# Named metadata / link-local / ULA targets called out in the design doc.
# is_blocked_ip also covers them via is_link_local / is_private.
_NAMED_METADATA = frozenset(
    {
        "169.254.169.254",
        "169.254.170.2",
        "fd00:ec2::254",
    }
)

_WS_RE = re.compile(r"\s+")


class IngestError(RouteError):
    """Typed fetch/extract failure. Same JSON envelope as other routes."""


def _fail(code: str, message: str, status: int = 400) -> None:
    raise IngestError(status, message, code=code)


# ---------------------------------------------------------------------------
# URL + IP policy
# ---------------------------------------------------------------------------


def is_blocked_ip(value: str) -> bool:
    """True when ``value`` must not be fetched (private, loopback, metadata, …)."""
    try:
        addr = ipaddress.ip_address(value.strip())
    except ValueError:
        return True
    if isinstance(addr, ipaddress.IPv6Address) and addr.ipv4_mapped is not None:
        return is_blocked_ip(str(addr.ipv4_mapped))
    if str(addr) in _NAMED_METADATA:
        return True
    return bool(
        addr.is_private
        or addr.is_loopback
        or addr.is_link_local
        or addr.is_multicast
        or addr.is_reserved
        or addr.is_unspecified
        or not addr.is_global
    )


def validate_https_url(raw: str) -> str:
    """Return a normalized https URL or raise ``IngestError``."""
    url = (raw or "").strip()
    if not url:
        _fail("invalid_url", "Request body must include a non-empty 'url'.")
    parsed = urlparse(url)
    if parsed.scheme.lower() not in ALLOWED_SCHEMES:
        _fail("invalid_url", "Only https URLs can be ingested.")
    if parsed.username or parsed.password:
        _fail("invalid_url", "URLs must not include credentials.")
    host = (parsed.hostname or "").strip().rstrip(".").lower()
    if not host:
        _fail("invalid_url", "URL is missing a hostname.")
    if host in BLOCKED_HOSTS or host.endswith(".localhost"):
        _fail("blocked_target", "This host cannot be fetched.")
    port = parsed.port or 443
    if port not in ALLOWED_PORTS:
        _fail("invalid_url", "Only https port 443 is allowed.")
    try:
        ipaddress.ip_address(host)
    except ValueError:
        pass
    else:
        if is_blocked_ip(host):
            _fail("blocked_target", "This address cannot be fetched.")
    path = parsed.path or "/"
    query = f"?{parsed.query}" if parsed.query else ""
    return f"https://{host}{path}{query}"


def resolve_public_ips(
    hostname: str,
    *,
    resolver: Callable[[str], list[str]] | None = None,
) -> list[str]:
    """Resolve ``hostname`` and reject the target if any address is blocked."""
    host = (hostname or "").strip().rstrip(".").lower()
    if not host:
        _fail("invalid_url", "URL is missing a hostname.")
    if host in BLOCKED_HOSTS:
        _fail("blocked_target", "This host cannot be fetched.")
    try:
        ipaddress.ip_address(host)
        ips = [host]
    except ValueError:
        lookup = resolver or _default_resolver
        try:
            ips = lookup(host)
        except OSError as exc:
            raise IngestError(502, "Could not resolve that host.", code="fetch_failed") from exc
    if not ips:
        _fail("fetch_failed", "Could not resolve that host.", status=502)
    blocked = [ip for ip in ips if is_blocked_ip(ip)]
    if blocked:
        _fail("blocked_target", "This host resolves to a private or metadata address.")
    # Preserve order, drop duplicates.
    seen: set[str] = set()
    out: list[str] = []
    for ip in ips:
        if ip not in seen:
            seen.add(ip)
            out.append(ip)
    return out


def _default_resolver(hostname: str) -> list[str]:
    infos = socket.getaddrinfo(hostname, 443, type=socket.SOCK_STREAM)
    ips: list[str] = []
    for info in infos:
        sockaddr = info[4]
        if sockaddr:
            ips.append(str(sockaddr[0]))
    return ips


# ---------------------------------------------------------------------------
# Fetch (injectable transport; no cookies; no automatic redirects)
# ---------------------------------------------------------------------------


@dataclass(frozen=True)
class HttpResponse:
    status: int
    headers: dict[str, str]
    body: bytes
    url: str


Transport = Callable[[str, str, float], HttpResponse]


class _PinnedHTTPSConnection(http.client.HTTPSConnection):
    """TLS to a pre-checked IP; SNI and Host stay on the original hostname."""

    def __init__(self, host: str, pinned_ip: str, **kwargs: Any) -> None:
        super().__init__(host, **kwargs)
        self._pinned_ip = pinned_ip

    def connect(self) -> None:
        sock = socket.create_connection((self._pinned_ip, self.port), self.timeout)
        context = self._context or ssl.create_default_context()
        self.sock = context.wrap_socket(sock, server_hostname=self.host)


def default_transport(url: str, pinned_ip: str, timeout: float) -> HttpResponse:
    parsed = urlparse(url)
    host = parsed.hostname or ""
    port = parsed.port or 443
    path = parsed.path or "/"
    if parsed.query:
        path = f"{path}?{parsed.query}"
    context = ssl.create_default_context()
    conn = _PinnedHTTPSConnection(
        host,
        pinned_ip,
        port=port,
        timeout=timeout,
        context=context,
    )
    try:
        conn.request(
            "GET",
            path,
            headers={
                "Host": host,
                "User-Agent": USER_AGENT,
                "Accept": ACCEPT_HEADER,
                "Accept-Language": "en",
            },
        )
        resp = conn.getresponse()
        headers = {k.lower(): v for k, v in resp.getheaders()}
        length = _content_length(headers)
        if length is not None and length > MAX_BODY_BYTES:
            _fail("payload_too_large", "Response is larger than the ingest limit.")
        body = _read_capped(resp, MAX_BODY_BYTES)
        return HttpResponse(status=resp.status, headers=headers, body=body, url=url)
    finally:
        conn.close()


def _content_length(headers: dict[str, str]) -> int | None:
    raw = headers.get("content-length")
    if raw is None:
        return None
    try:
        value = int(str(raw).strip())
    except (TypeError, ValueError):
        return None
    return value if value >= 0 else None


def _read_capped(resp: Any, limit: int) -> bytes:
    chunks: list[bytes] = []
    total = 0
    while True:
        chunk = resp.read(min(16_384, limit - total + 1))
        if not chunk:
            break
        total += len(chunk)
        if total > limit:
            _fail("payload_too_large", "Response is larger than the ingest limit.")
        chunks.append(chunk)
    return b"".join(chunks)


def _media_type(headers: dict[str, str]) -> str:
    raw = (headers.get("content-type") or "").split(";", 1)[0].strip().lower()
    return raw


def fetch_https(
    url: str,
    *,
    resolver: Callable[[str], list[str]] | None = None,
    transport: Transport | None = None,
    timeout: float = TIMEOUT_SECONDS,
    max_redirects: int = MAX_REDIRECTS,
) -> HttpResponse:
    """HTTPS GET with DNS/IP checks on every hop. Does not send cookies."""
    hop = validate_https_url(url)
    send = transport or default_transport
    seen: set[str] = set()
    for _ in range(max_redirects + 1):
        if hop in seen:
            _fail("redirect_limit", "Redirect loop.")
        seen.add(hop)
        parsed = urlparse(hop)
        ips = resolve_public_ips(parsed.hostname or "", resolver=resolver)
        response = send(hop, ips[0], timeout)
        if 300 <= response.status < 400:
            location = (response.headers.get("location") or "").strip()
            if not location:
                _fail("fetch_failed", "Redirect was missing a Location header.", status=502)
            nxt = urljoin(hop, location)
            hop = validate_https_url(nxt)
            continue
        if response.status < 200 or response.status >= 300:
            raise IngestError(
                502,
                "The page could not be fetched.",
                code="fetch_failed",
            )
        media = _media_type(response.headers)
        if media not in ALLOWED_CONTENT_TYPES:
            _fail("unsupported_media", "This content type cannot be ingested.")
        if len(response.body) > MAX_BODY_BYTES:
            _fail("payload_too_large", "Response is larger than the ingest limit.")
        return HttpResponse(
            status=response.status,
            headers=response.headers,
            body=response.body,
            url=hop,
        )
    _fail("redirect_limit", "Too many redirects.")
    raise AssertionError("unreachable")


# ---------------------------------------------------------------------------
# HTML / JSON-LD extraction
# ---------------------------------------------------------------------------


class _PageParser(HTMLParser):
    _SKIP = frozenset({"script", "style", "noscript", "svg", "template"})
    _TEXT_TAGS = frozenset({"p", "li", "h1", "h2", "h3", "article", "title"})

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.title_parts: list[str] = []
        self.text_parts: list[str] = []
        self.json_ld: list[str] = []
        self._skip = 0
        self._in_title = False
        self._in_ld = False
        self._ld_parts: list[str] = []
        self._capture_text = False

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        attrs_d = {k.lower(): (v or "") for k, v in attrs}
        if tag == "script" and "ld+json" in attrs_d.get("type", "").lower():
            self._in_ld = True
            self._ld_parts = []
            return
        if tag in self._SKIP:
            self._skip += 1
            return
        if self._skip:
            return
        if tag == "title":
            self._in_title = True
        if tag in self._TEXT_TAGS:
            self._capture_text = True

    def handle_endtag(self, tag: str) -> None:
        if self._in_ld and tag == "script":
            blob = "".join(self._ld_parts).strip()
            if blob:
                self.json_ld.append(blob)
            self._in_ld = False
            self._ld_parts = []
            return
        if tag in self._SKIP and self._skip:
            self._skip -= 1
            return
        if tag == "title":
            self._in_title = False
        if tag in self._TEXT_TAGS:
            self._capture_text = False

    def handle_data(self, data: str) -> None:
        if self._in_ld:
            self._ld_parts.append(data)
            return
        if self._skip:
            return
        text = data.strip()
        if not text:
            return
        if self._in_title:
            self.title_parts.append(text)
        if self._capture_text:
            self.text_parts.append(text)


def _collapse(text: str, *, limit: int | None = None) -> str:
    cleaned = _WS_RE.sub(" ", html_lib.unescape(text or "")).strip()
    if limit is not None and len(cleaned) > limit:
        return cleaned[:limit].rstrip() + "…"
    return cleaned


def _as_list(value: Any) -> list[Any]:
    if value is None:
        return []
    if isinstance(value, list):
        return value
    return [value]


def _schema_names(value: Any) -> list[str]:
    names: list[str] = []
    for item in _as_list(value):
        if isinstance(item, dict):
            item = item.get("@type") or item.get("type")
        text = str(item or "").strip()
        if not text:
            continue
        # https://schema.org/Recipe → Recipe
        text = text.rsplit("/", 1)[-1]
        names.append(text)
    return names


def _kind_for_types(types: Iterable[str]) -> str | None:
    for raw in types:
        key = re.sub(r"[^a-z0-9]", "", raw.lower())
        kind = _SCHEMA_TO_KIND.get(key)
        if kind:
            return kind
    return None


def _flatten_ld(node: Any) -> list[dict[str, Any]]:
    out: list[dict[str, Any]] = []
    if isinstance(node, list):
        for item in node:
            out.extend(_flatten_ld(item))
        return out
    if not isinstance(node, dict):
        return out
    graph = node.get("@graph")
    if isinstance(graph, list):
        for item in graph:
            out.extend(_flatten_ld(item))
    out.append(node)
    return out


def _parse_json_ld_blobs(blobs: list[str]) -> list[dict[str, Any]]:
    nodes: list[dict[str, Any]] = []
    for blob in blobs:
        try:
            parsed = json.loads(blob)
        except (json.JSONDecodeError, TypeError, ValueError):
            continue
        nodes.extend(_flatten_ld(parsed))
    return nodes


def _text_of(value: Any) -> str:
    if value is None:
        return ""
    if isinstance(value, str):
        return _collapse(value)
    if isinstance(value, (int, float)) and not isinstance(value, bool):
        return str(value)
    if isinstance(value, dict):
        for key in ("name", "text", "headline", "@value"):
            if value.get(key):
                return _text_of(value.get(key))
        return ""
    if isinstance(value, list):
        parts = [_text_of(item) for item in value]
        return _collapse(" ".join(p for p in parts if p))
    return ""


def _string_list(value: Any) -> list[str]:
    out: list[str] = []
    seen: set[str] = set()
    for item in _as_list(value):
        text = _text_of(item)
        if not text:
            continue
        key = text.lower()
        if key in seen:
            continue
        seen.add(key)
        out.append(text)
    return out


def _howto_steps(value: Any) -> list[dict[str, str]]:
    steps: list[dict[str, str]] = []
    for item in _as_list(value):
        if isinstance(item, dict) and item.get("itemListElement"):
            steps.extend(_howto_steps(item.get("itemListElement")))
            continue
        if isinstance(item, dict):
            name = _text_of(item.get("name"))
            text = _text_of(item.get("text") or item.get("description") or item)
            if not text and name:
                text = name
            if not text:
                continue
            entry: dict[str, str] = {"text": text}
            if name and name != text:
                entry["name"] = name
            steps.append(entry)
            continue
        text = _text_of(item)
        if text:
            steps.append({"text": text})
    return steps


def _nutrition_map(value: Any) -> dict[str, str]:
    if not isinstance(value, dict):
        return {}
    out: dict[str, str] = {}
    for key, raw in value.items():
        if str(key).startswith("@"):
            continue
        text = _text_of(raw)
        if text:
            out[str(key)] = text
    return out


def extract_from_html(body: bytes | str, *, source_url: str) -> dict[str, Any]:
    if isinstance(body, bytes):
        text = body.decode("utf-8", errors="replace")
    else:
        text = body
    parser = _PageParser()
    try:
        parser.feed(text)
        parser.close()
    except Exception:
        # Malformed HTML still yields whatever we collected.
        pass
    title = _collapse(" ".join(parser.title_parts), limit=200)
    readable = _collapse(" ".join(parser.text_parts), limit=MAX_READABLE_CHARS)
    nodes = _parse_json_ld_blobs(parser.json_ld)
    schema_types: list[str] = []
    chosen: dict[str, Any] | None = None
    chosen_kind: str | None = None
    for node in nodes:
        types = _schema_names(node.get("@type") or node.get("type"))
        for name in types:
            if name not in schema_types:
                schema_types.append(name)
        kind = _kind_for_types(types)
        if kind is None:
            continue
        if chosen is None or _KIND_PRIORITY.index(kind) < _KIND_PRIORITY.index(chosen_kind or KIND_GENERIC):
            chosen = node
            chosen_kind = kind
    kind = chosen_kind or KIND_GENERIC
    extract = _typed_extract(kind, chosen, title=title, readable=readable)
    if not title:
        title = str(extract.get("name") or extract.get("headline") or extract.get("title") or "")
    if not title:
        title = urlparse(source_url).hostname or "Untitled"
    return {
        "title": title,
        "kind": kind,
        "extract": extract,
        "readableText": readable,
        "schemaTypes": schema_types,
    }


def _typed_extract(
    kind: str,
    node: dict[str, Any] | None,
    *,
    title: str,
    readable: str,
) -> dict[str, Any]:
    node = node or {}
    if kind == KIND_RECIPE:
        instructions = _howto_steps(node.get("recipeInstructions"))
        if not instructions:
            instructions = [{"text": t} for t in _string_list(node.get("recipeInstructions"))]
        return {
            "kind": KIND_RECIPE,
            "name": _text_of(node.get("name")) or title,
            "description": _text_of(node.get("description")) or None,
            "ingredients": _string_list(node.get("recipeIngredient") or node.get("ingredients")),
            "instructions": [s.get("text") or s.get("name") or "" for s in instructions if s],
            "prepTime": _text_of(node.get("prepTime")) or None,
            "cookTime": _text_of(node.get("cookTime")) or None,
            "totalTime": _text_of(node.get("totalTime")) or None,
            "recipeYield": _text_of(node.get("recipeYield") or node.get("yield")) or None,
            "nutrition": _nutrition_map(node.get("nutrition")) or None,
        }
    if kind == KIND_EXERCISE_PLAN:
        return {
            "kind": KIND_EXERCISE_PLAN,
            "name": _text_of(node.get("name")) or title,
            "description": _text_of(node.get("description")) or None,
            "activityDuration": _text_of(node.get("activityDuration")) or None,
            "exerciseType": _text_of(node.get("exerciseType")) or None,
            "intensity": _text_of(node.get("intensity")) or None,
            "workPattern": _text_of(node.get("workPattern")) or None,
            "additionalVariable": _text_of(node.get("additionalVariable")) or None,
        }
    if kind == KIND_HOWTO:
        steps = _howto_steps(node.get("step") or node.get("steps"))
        return {
            "kind": KIND_HOWTO,
            "name": _text_of(node.get("name")) or title,
            "description": _text_of(node.get("description")) or None,
            "steps": steps,
            "totalTime": _text_of(node.get("totalTime")) or None,
            "supply": _string_list(node.get("supply")),
            "tool": _string_list(node.get("tool")),
        }
    if kind == KIND_ARTICLE:
        author = node.get("author")
        return {
            "kind": KIND_ARTICLE,
            "headline": _text_of(node.get("headline") or node.get("name")) or title,
            "description": _text_of(node.get("description")) or None,
            "author": _text_of(author) or None,
            "text": _text_of(node.get("articleBody")) or readable,
        }
    return {
        "kind": KIND_GENERIC,
        "title": _text_of(node.get("name") or node.get("headline")) or title,
        "text": readable,
    }


def build_aria_feed(
    *,
    kind: str,
    extract: dict[str, Any],
    readable_text: str,
    source_url: str,
    sanitize: Callable[[str], str] | None = None,
) -> dict[str, Any]:
    """Sidecar for the next chat turn. Never a biometric or clinical row."""
    clean = sanitize or (lambda s: s)
    domain = _KIND_TO_DOMAIN[kind]
    facts: list[str] = []
    name = clean(
        str(
            extract.get("name")
            or extract.get("headline")
            or extract.get("title")
            or "Shared page"
        )
    )
    if kind == KIND_RECIPE:
        summary = clean(f"Shared recipe: {name}")
        for item in (extract.get("ingredients") or [])[:12]:
            text = clean(str(item))
            if text:
                facts.append(text)
        for item in (extract.get("instructions") or [])[:8]:
            text = clean(str(item))
            if text:
                facts.append(text)
        extra = extract.get("totalTime") or extract.get("recipeYield")
        if extra:
            facts.append(clean(str(extra)))
    elif kind == KIND_EXERCISE_PLAN:
        bits = [p for p in (extract.get("exerciseType"), extract.get("intensity"), extract.get("activityDuration")) if p]
        summary = clean(f"Shared exercise plan: {name}" + (f" ({', '.join(str(b) for b in bits)})" if bits else ""))
        for key in ("activityDuration", "exerciseType", "intensity", "workPattern", "additionalVariable", "description"):
            value = extract.get(key)
            if value:
                facts.append(clean(f"{key}: {value}"))
    elif kind == KIND_HOWTO:
        summary = clean(f"Shared how-to: {name}")
        for step in (extract.get("steps") or [])[:10]:
            text = clean(str(step.get("text") if isinstance(step, dict) else step))
            if text:
                facts.append(text)
    else:
        summary = clean(f"Shared page: {name}")
        excerpt = clean(_collapse(readable_text, limit=400))
        if excerpt:
            facts.append(excerpt)
    facts = [f for f in facts if f][:16]
    return {
        "domain": domain,
        "summary": summary or clean("Shared a web page."),
        "facts": facts,
        "untrusted": True,
        "sourceUrl": source_url,
    }


def memory_folder_for(kind: str) -> str:
    return _KIND_TO_FOLDER.get(kind, "lifestyle")


def memory_category_for(kind: str) -> str:
    return _KIND_TO_CATEGORY.get(kind, "note")


def memory_candidate_text(*, kind: str, extract: dict[str, Any], aria_feed: dict[str, Any]) -> str:
    name = (
        extract.get("name")
        or extract.get("headline")
        or extract.get("title")
        or "web page"
    )
    label = {
        KIND_RECIPE: "Recipe",
        KIND_EXERCISE_PLAN: "Exercise plan",
        KIND_HOWTO: "How-to",
        KIND_ARTICLE: "Article",
        KIND_GENERIC: "Page",
    }[kind]
    facts = aria_feed.get("facts") or []
    preview = "; ".join(str(f) for f in facts[:4])
    text = f"{label}: {name}"
    if preview:
        text = f"{text} — {preview}"
    return _collapse(text, limit=400)


@dataclass
class IngestResult:
    url: str
    final_url: str
    title: str
    kind: str
    extract: dict[str, Any]
    readable_text: str
    schema_types: list[str] = field(default_factory=list)

    def to_response(
        self,
        *,
        aria_feed: dict[str, Any],
        memory_candidate: dict[str, Any],
    ) -> dict[str, Any]:
        return {
            "url": self.url,
            "finalUrl": self.final_url,
            "title": self.title,
            "kind": self.kind,
            "extract": self.extract,
            "readableText": self.readable_text,
            "schemaTypes": self.schema_types,
            "ariaFeed": aria_feed,
            "memoryCandidate": memory_candidate,
        }


def ingest_url(
    url: str,
    *,
    resolver: Callable[[str], list[str]] | None = None,
    transport: Transport | None = None,
) -> IngestResult:
    requested = validate_https_url(url)
    response = fetch_https(requested, resolver=resolver, transport=transport)
    parsed = extract_from_html(response.body, source_url=response.url)
    return IngestResult(
        url=requested,
        final_url=response.url,
        title=parsed["title"],
        kind=parsed["kind"],
        extract=parsed["extract"],
        readable_text=parsed["readableText"],
        schema_types=parsed["schemaTypes"],
    )
