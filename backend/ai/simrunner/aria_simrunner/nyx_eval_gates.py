"""Nyx Dummy hypertune FAIL GATES.

Deterministic predicates for:
1. Retrieval provenance (vault / editable-memory / cited notes)
2. Dummy/offline no-spend (never Bedrock / generate_response_live / InvokeModel)
3. Sleep-stage % dumps, including wake speak
4. Stub vs fused-lambda user-visible parity (delegates to speak_quality)
5. Partner/cycle prefixes on the user-add / vault-note path

Hypertune source of truth is Dummy/offline. Bedrock stays off. These are
keyword/regex/AST gates — not an LLM judge.
"""

from __future__ import annotations

import ast
import re
from pathlib import Path
from typing import Any, Iterable

from . import speak_quality

# Same deny list as ``routes.aria._DENIED_LIFESTYLE`` (Python inbound).
# Rowan contract: user-add / vault notes must run this strip too.
DENIED_LIFESTYLE_PREFIXES = (
    "partner_",
    "support_cycle:",
    "partner_name:",
    "partner_phase:",
    "partner_day:",
    "partner_cycle:",
    "cycle:fertile",
    "cycle:tww",
    "cycle:goal:trying",
    "cycle:bleeding",
    "cycle:condition",
)

_DENIED_LIFESTYLE = re.compile(
    r"(?i)^(?:"
    r"partner_"
    r"|support_cycle:"
    r"|partner_name:"
    r"|partner_phase:"
    r"|partner_day:"
    r"|partner_cycle:"
    r"|cycle:fertile"
    r"|cycle:tww"
    r"|cycle:goal:trying"
    r"|cycle:bleeding"
    r"|cycle:condition"
    r")"
)

_STAGE_PCT_RE = re.compile(
    r"\b(?:deep|rem|light)\s+sleep\s+at\s+\d+(?:\.\d+)?\s*%"
    r"|\brem\s+is\s+light\s+at\s+\d+(?:\.\d+)?\s*%",
    re.I,
)

_MEMORY_CITE_RE = re.compile(
    r"|".join(
        (
            r"\bi remember\b",
            r"\byou told me\b",
            r"\bfrom (?:your )?(?:notes|memory|the vault)\b",
            r"\bstored (?:note|memory)\b",
            r"\bin (?:your|the) vault\b",
            r"\baccording to (?:your|the) notes\b",
        )
    ),
    re.I,
)

_FROM_CITE_RE = re.compile(r"\bFrom [^:]{1,80}:")

_INVOKE_CALL_NAMES = frozenset(
    {
        "generate_response_live",
        "InvokeModel",
        "invoke_model",
        "InvokeModelWithBidirectionalStream",
        "invoke_model_with_bidirectional_stream",
        "SynthesizeSpeech",
        "synthesize_speech",
        "converse",
        "mint_signed_url",
        "run_tool",
        "design_aria",
        "handle_get_ai_voice_bootstrap",
        "handle_post_ai_voice_tool",
    }
)

# Live-voice spend Dummy must never reach (Nova Sonic, Polly, ElevenLabs).
# `/ingest/url` is not a needle: Dummy may call the #369 extract ($0).
_SPEND_NAME_NEEDLES = (
    "InvokeModelWithBidirectionalStream",
    "invoke_model_with_bidirectional_stream",
    "SynthesizeSpeech",
    "synthesize_speech",
    "elevenlabs_voice",
    "/ai/voice/bootstrap",
    "/ai/voice/tool",
)

_INGEST_SPEND_CALL_NAMES = frozenset(
    {
        "generate_response_live",
        "InvokeModel",
        "invoke_model",
        "converse",
        "InvokeModelWithBidirectionalStream",
        "invoke_model_with_bidirectional_stream",
        "SynthesizeSpeech",
        "synthesize_speech",
    }
)

_REPO_ROOT = Path(__file__).resolve().parents[4]


def denied_lifestyle_token(token: str) -> bool:
    """True when a vault / inbound token is a partner or cycle prefix."""
    return bool(_DENIED_LIFESTYLE.search(str(token or "").strip()))


def vault_note_privacy_failures(text: str) -> list[str]:
    """FAIL GATE: partner/cycle prefixes must not land in a vault note."""
    raw = str(text or "")
    fails: list[str] = []
    for token in re.split(r"\s+", raw.strip()):
        if token and denied_lifestyle_token(token):
            fails.append(f"partner/cycle prefix: {token}")
    # Also catch glued notes ("keep partner_phase:luteal").
    low = raw.lower()
    for prefix in DENIED_LIFESTYLE_PREFIXES:
        if prefix in low and not any(prefix in f for f in fails):
            fails.append(f"partner/cycle prefix: {prefix}")
    return fails


def sanitize_vault_note(text: str) -> str:
    """Drop denied lifestyle tokens. Empty means the note was refused."""
    kept: list[str] = []
    for token in re.split(r"\s+", str(text or "").strip()):
        if token and not denied_lifestyle_token(token):
            kept.append(token)
    cleaned = " ".join(kept)
    cleaned = _STAGE_PCT_RE.sub("", cleaned)
    cleaned = re.sub(r"\s{2,}", " ", cleaned).strip(" ,;:—–-")
    return cleaned


def retrieved_fact_provenance_failures(facts: Iterable[dict[str, Any]] | None) -> list[str]:
    """FAIL GATE: every retrieved vault/memory fact needs an id and a source."""
    fails: list[str] = []
    for index, fact in enumerate(facts or []):
        if not isinstance(fact, dict):
            fails.append(f"fact[{index}] is not a mapping")
            continue
        fact_id = str(fact.get("id") or "").strip()
        source = str(
            fact.get("source")
            or fact.get("source_id")
            or fact.get("sourceId")
            or ""
        ).strip()
        label = fact_id or str(fact.get("kind") or index)
        if not fact_id:
            fails.append(f"fact[{label}] missing id")
        if not source or source.lower() in {"unknown", "none", "null"}:
            fails.append(f"fact[{label}] missing source/source_id")
    return fails


def memory_cite_without_note_failures(
    speak: str,
    notes: Iterable[dict[str, Any]] | None,
) -> list[str]:
    """FAIL GATE: speak that cites memory must have a retrievable sourced note."""
    if not _MEMORY_CITE_RE.search(speak or ""):
        return []
    retrievable = []
    for note in notes or []:
        if not isinstance(note, dict):
            continue
        if retrieved_fact_provenance_failures([note]):
            continue
        summary = str(note.get("summary") or note.get("text") or "").strip()
        if summary:
            retrievable.append(note)
    if not retrievable:
        return ["speak cites memory without a retrievable note"]
    return []


def web_cite_provenance_failures(text: str) -> list[str]:
    """A Dummy web/research retrieve must keep a ``From {source}:`` label."""
    raw = str(text or "")
    if not raw.strip():
        return []
    if raw.lower().startswith("from ") and ":" in raw:
        if _FROM_CITE_RE.search(raw):
            return []
        return ["web cite missing From {source}: label"]
    return []


def stage_pct_failures(text: str) -> list[str]:
    """FAIL GATE: deep/REM/light sleep at N% (speak-fail floor, also wake)."""
    found = _STAGE_PCT_RE.findall(text or "")
    return [f"stage %: {item}" for item in found]


def user_visible_parity_failures(row: dict[str, Any] | None) -> list[str]:
    """Same speak-fail floor on every user-visible field (message/prose/card)."""
    return speak_quality.speak_failures(row)


def _call_name(node: ast.AST) -> str:
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        return node.attr
    return ""


def _ast_parents(tree: ast.AST) -> dict[ast.AST, ast.AST]:
    parents: dict[ast.AST, ast.AST] = {}
    for node in ast.walk(tree):
        for child in ast.iter_child_nodes(node):
            parents[child] = node
    return parents


def _mentions_bedrock_enabled_flag(node: ast.AST) -> bool:
    for child in ast.walk(node):
        if isinstance(child, ast.Name) and child.id == "ARIA_BEDROCK_ENABLED":
            return True
        if isinstance(child, ast.Attribute) and child.attr == "ARIA_BEDROCK_ENABLED":
            return True
        if isinstance(child, ast.Constant) and child.value == "ARIA_BEDROCK_ENABLED":
            return True
    return False


def _call_is_flag_guarded(node: ast.AST, parents: dict[ast.AST, ast.AST]) -> bool:
    current = node
    while current in parents:
        current = parents[current]
        if isinstance(current, ast.If) and _mentions_bedrock_enabled_flag(current.test):
            return True
    return False


def ingest_url_no_spend_failures(source: str) -> list[str]:
    """FAIL GATE: /ingest/url extract must stay deterministic $0.

    Unguarded ``generate_response_live`` / ``InvokeModel`` / ``converse`` /
    Nova Sonic / Polly calls fail. A future summarize/classify step is
    allowed only when lexically inside ``if ARIA_BEDROCK_ENABLED``.
    """
    tree = ast.parse(source)
    parents = _ast_parents(tree)
    fails: list[str] = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = _call_name(node.func)
        if name not in _INGEST_SPEND_CALL_NAMES:
            continue
        if _call_is_flag_guarded(node, parents):
            continue
        fails.append(f"unguarded {name} call at line {node.lineno}")
    return fails


def find_ingest_url_modules() -> list[Path]:
    """#369 handler + extract. Empty until that PR lands on tip."""
    found: list[Path] = []
    for rel in (
        ("backend", "infra", "lambda", "routes", "ingest.py"),
        ("backend", "infra", "lambda", "services", "web_ingest.py"),
    ):
        path = repo_file(*rel)
        if path.is_file():
            found.append(path)
    return found


def _docstring_constants(tree: ast.AST) -> set[ast.AST]:
    """First ``Expr`` constant of a module, class, or function body."""
    found: set[ast.AST] = set()

    def take(body: list[ast.stmt]) -> None:
        if body and isinstance(body[0], ast.Expr) and isinstance(body[0].value, ast.Constant):
            found.add(body[0].value)

    take(tree.body)
    for node in ast.walk(tree):
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef, ast.ClassDef)):
            take(node.body)
    return found


def dummy_invoke_call_failures(source: str) -> list[str]:
    """FAIL GATE: Dummy source must not *call* live spend.

    Covers Bedrock ``generate_response_live`` / ``InvokeModel``, Nova Sonic
    ``InvokeModelWithBidirectionalStream``, Polly ``SynthesizeSpeech``, and
    ElevenLabs session/tool helpers. Mentions in comments/docstrings are
    allowed. String literals and real Calls still fail.
    ``generate_response`` (deterministic) is the fused Dummy path.
    ``/ingest/url`` is not spend — Dummy may reach the #369 extract.
    """
    tree = ast.parse(source)
    docstrings = _docstring_constants(tree)
    fails: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if "elevenlabs_voice" in (alias.name or ""):
                    fails.append(f"import {alias.name} at line {node.lineno}")
        elif isinstance(node, ast.ImportFrom):
            module = node.module or ""
            if "elevenlabs_voice" in module:
                fails.append(f"from {module} import at line {node.lineno}")
            for alias in node.names:
                if alias.name == "elevenlabs_voice":
                    fails.append(f"from {module} import elevenlabs_voice at line {node.lineno}")
        elif isinstance(node, ast.Constant) and isinstance(node.value, str):
            if node in docstrings:
                continue
            for needle in _SPEND_NAME_NEEDLES:
                if needle in node.value:
                    fails.append(f"{needle} literal at line {node.lineno}")
        elif isinstance(node, ast.Call):
            name = _call_name(node.func)
            if name in _INVOKE_CALL_NAMES:
                fails.append(f"{name} call at line {node.lineno}")
    return fails


def provider_stub_failures(caps: Any | None) -> list[str]:
    """#302-style stub: Dummy default, kill-switch off, do not invoke.

    When the module is absent (not yet on tip), this returns [] so Dummy
    runtime/source gates still carry the no-spend bar.
    """
    if caps is None:
        return []
    fails: list[str] = []
    if getattr(caps, "DO_NOT_INVOKE", None) is not True:
        fails.append("DO_NOT_INVOKE is not True")
    if getattr(caps, "AWAIT_QUILL_TABLE", None) is not True:
        fails.append("AWAIT_QUILL_TABLE is not True")
    if getattr(caps, "BEDROCK_KILL_SWITCH_DEFAULT", True):
        fails.append("BEDROCK_KILL_SWITCH_DEFAULT is not False")
    invoke = getattr(caps, "invoke_now_allowed", None)
    if callable(invoke) and invoke():
        fails.append("invoke_now_allowed() is True")
    return fails


def try_load_provider_capabilities() -> Any | None:
    try:
        from backend._paths import ensure_lambda_on_path

        ensure_lambda_on_path()
        from services import provider_capabilities as caps

        return caps
    except Exception:
        return None


def repo_file(*parts: str) -> Path:
    return _REPO_ROOT.joinpath(*parts)


def iter_swift_privacy_sources() -> list[Path]:
    root = _REPO_ROOT / "ForgeSwift"
    if not root.is_dir():
        return []
    return [
        path
        for path in root.rglob("*.swift")
        if path.name in {"AriaMemoryControls.swift", "AriaKnowledgeLedger.swift"}
        and " 2.swift" not in path.name
    ]


_SWIFT_STRIP_PREFIXES = ("partner_", "partner_phase:", "cycle:fertile")


def _required_swift_strip_prefixes() -> tuple[str, ...]:
    """Prefixes the Swift strip must cover, intersected with the Python deny list."""
    deny = {item.lower() for item in DENIED_LIFESTYLE_PREFIXES}
    return tuple(item for item in _SWIFT_STRIP_PREFIXES if item.lower() in deny)


def aria_fact_privacy_strip_failures(source: str) -> list[str]:
    """If AriaFactPrivacy exists, user-add must strip partner/cycle prefixes.

    Pass when ``sanitizeSummary`` contains the deny prefixes itself, or when
    it calls ``AriaInboundLifestyleStrip.sanitize`` and that enum's
    ``deniedPrefixes`` includes ``partner_``, ``partner_phase:``, and
    ``cycle:fertile`` (checked against ``DENIED_LIFESTYLE_PREFIXES``).
    """
    if "enum AriaFactPrivacy" not in source and "AriaFactPrivacy" not in source:
        return []
    required = _required_swift_strip_prefixes()
    blob = source
    marker = "func sanitizeSummary"
    if marker in source:
        blob = source.split(marker, 1)[-1]
    low = blob.lower()
    if all(prefix.lower() in low for prefix in required):
        return []
    if "AriaInboundLifestyleStrip.sanitize" in blob:
        enum_low = source.lower()
        missing = [
            prefix
            for prefix in required
            if prefix.lower() not in enum_low
        ]
        if missing:
            return [
                f"AriaInboundLifestyleStrip.deniedPrefixes missing {item}"
                for item in missing
            ]
        if "deniedPrefixes" not in source and "deniedprefixes" not in enum_low:
            return ["AriaInboundLifestyleStrip missing deniedPrefixes"]
        return []
    return [f"AriaFactPrivacy sanitizer missing {item}" for item in required]
