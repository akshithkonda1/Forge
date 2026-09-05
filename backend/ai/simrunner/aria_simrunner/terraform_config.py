"""Reads ARIA's real Terraform-declared AI configuration — stdlib only.

Three variables in ``backend/infra/variables.tf`` govern ``/ai/chat``'s real
behavior: ``aria_bedrock_enabled`` (the live-vs-deterministic switch) and the
AI router's third-slot id/name (``ai_router_model_3_id``/``_name`` — used by
``/ai/router`` and ``/coach/*``, not ``/ai/chat``, but resolved here for a
complete picture). This is not a general HCL parser: it understands exactly
the shapes this repo's own ``variables.tf``/``main.tf``/``terraform.tfvars``
actually use (a flat ``variable "x" { ... default = ... }`` block; simple
``key = value`` tfvars lines, including multi-line bracketed values it must
skip over without misreading). It degrades to a documented, clearly-labeled
fallback rather than ever raising or guessing on a shape it doesn't
recognize.

Precedence per variable, matching real Terraform semantics: a real
``terraform.tfvars`` on disk wins, then a ``TF_VAR_<name>`` environment
variable, then the ``variables.tf``-declared default, then a hardcoded
fallback if ``variables.tf`` itself can't be found. Deliberately does not
support ``*.auto.tfvars`` or ``-var``/``-var-file`` — nothing in this repo
uses them.
"""

from __future__ import annotations

import os
import re
from dataclasses import dataclass

_ROUTER3_ID_FALLBACK = "moonshotai.kimi-k2.5"
_ROUTER3_NAME_FALLBACK = "Kimi K2.5"

_ROUTER3_FALLBACK_RE = re.compile(
    r'AI_ROUTER_MODEL_3_ID\s*=\s*var\.ai_router_model_3_id\s*!=\s*""\s*\?\s*'
    r'var\.ai_router_model_3_id\s*:\s*"([^"]+)"'
)
_ROUTER3_NAME_FALLBACK_RE = re.compile(
    r'AI_ROUTER_MODEL_3_NAME\s*=\s*var\.ai_router_model_3_name\s*!=\s*""\s*\?\s*'
    r'var\.ai_router_model_3_name\s*:\s*"([^"]+)"'
)

_TARGET_VARS = ("aria_bedrock_enabled", "ai_router_model_3_id", "ai_router_model_3_name")
_CODE_DEFAULTS = {
    "aria_bedrock_enabled": False,
    "ai_router_model_3_id": "",
    "ai_router_model_3_name": "",
}


@dataclass(frozen=True)
class ResolvedVar:
    value: bool | str
    source: str          # "declared_default" | "tfvar_env_override" | "tfvars_override" | "not_found"
    raw: str | None       # raw RHS text pre-coercion, for debugging/tests


@dataclass(frozen=True)
class AriaTerraformConfig:
    aria_bedrock_enabled: ResolvedVar
    ai_router_model_3_id: ResolvedVar
    ai_router_model_3_name: ResolvedVar
    ai_router_model_3_id_effective: str
    ai_router_model_3_name_effective: str
    variables_tf_found: bool
    tfvars_found: bool
    main_tf_fallback_pattern_matched: bool

    @property
    def bedrock_live_for_chat(self) -> bool:
        """Whether the real POST /ai/chat endpoint calls live Bedrock at all
        in this configuration — false means it serves the deterministic
        engine only, regardless of which models are configured elsewhere."""
        return bool(self.aria_bedrock_enabled.value)


def _find_matching_brace(text: str, open_idx: int) -> int:
    """Index of the ``}`` matching ``text[open_idx] == '{'``, skipping braces
    inside double-quoted strings (with backslash-escape support)."""
    depth = 0
    in_string = False
    i = open_idx
    while i < len(text):
        ch = text[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "{":
                depth += 1
            elif ch == "}":
                depth -= 1
                if depth == 0:
                    return i
        i += 1
    raise ValueError("unbalanced braces")


def _strip_trailing_comment(line: str) -> str:
    """Strip a trailing '#' or '//' comment, but never one that's inside a
    double-quoted string (a description containing a literal '#')."""
    in_string = False
    i = 0
    while i < len(line):
        ch = line[i]
        if in_string:
            if ch == "\\":
                i += 2
                continue
            if ch == '"':
                in_string = False
        else:
            if ch == '"':
                in_string = True
            elif ch == "#" or (ch == "/" and line[i:i + 2] == "//"):
                return line[:i]
        i += 1
    return line


def _coerce(raw: str) -> bool | str:
    stripped = _strip_trailing_comment(raw).strip()
    if stripped in ("true", "false"):
        return stripped == "true"
    if len(stripped) >= 2 and stripped[0] == '"' and stripped[-1] == '"':
        return stripped[1:-1]
    return stripped


def _extract_variable_default(text: str, name: str) -> str | None:
    """Find `variable "name" { ... }` via brace-counting, then a `default =`
    line within just that block. Returns the raw (uncoerced) RHS, or None if
    the variable block or its default line isn't found."""
    m = re.search(r'variable\s+"' + re.escape(name) + r'"\s*\{', text)
    if not m:
        return None
    open_idx = m.end() - 1
    try:
        close_idx = _find_matching_brace(text, open_idx)
    except ValueError:
        return None
    block = text[open_idx + 1:close_idx]
    dm = re.search(r'^\s*default\s*=\s*(.+?)\s*$', block, re.MULTILINE)
    if not dm:
        return None
    return dm.group(1)


def _parse_variables_tf(path: str) -> dict[str, str]:
    """{var_name: raw_default_rhs} for the variables we care about. Missing
    file or missing/unrecognized blocks simply omit that key -- never raises."""
    found: dict[str, str] = {}
    try:
        with open(path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return found
    for name in _TARGET_VARS:
        raw = _extract_variable_default(text, name)
        if raw is not None:
            found[name] = raw
    return found


def _parse_tfvars(path: str) -> dict[str, str]:
    """{key: raw_rhs} from a tfvars file, skipping full-line comments and
    multi-line bracketed values (e.g. `allowed_origins = [...]`) via simple
    bracket-depth counting -- no string-literal awareness needed here since
    none of our target keys are ever bracketed in this repo's real usage."""
    found: dict[str, str] = {}
    try:
        with open(path, encoding="utf-8") as fh:
            lines = fh.readlines()
    except OSError:
        return found

    depth = 0
    for raw_line in lines:
        line = raw_line.strip()
        if depth > 0:
            depth += line.count("[") + line.count("{") - line.count("]") - line.count("}")
            continue
        if not line or line.startswith("#") or line.startswith("//"):
            continue
        m = re.match(r'^([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.+)$', line)
        if not m:
            continue
        key, rhs = m.group(1), m.group(2)
        opens = rhs.count("[") + rhs.count("{")
        closes = rhs.count("]") + rhs.count("}")
        if opens > closes:
            depth += opens - closes
            continue  # a multi-line value starts here; the key itself isn't one of ours
        if key in _TARGET_VARS:
            found[key] = rhs
    return found


def _router3_fallbacks(main_tf_path: str) -> tuple[str, str, bool]:
    """(id_fallback, name_fallback, pattern_matched) derived from main.tf's
    own ternary, so this module doesn't hold a third manually-synced copy of
    a value query_router.py/prompts.py already separately mirror."""
    try:
        with open(main_tf_path, encoding="utf-8") as fh:
            text = fh.read()
    except OSError:
        return _ROUTER3_ID_FALLBACK, _ROUTER3_NAME_FALLBACK, False
    id_match = _ROUTER3_FALLBACK_RE.search(text)
    name_match = _ROUTER3_NAME_FALLBACK_RE.search(text)
    if id_match and name_match:
        return id_match.group(1), name_match.group(1), True
    return _ROUTER3_ID_FALLBACK, _ROUTER3_NAME_FALLBACK, False


def _resolve(name: str, tfvars_raw: dict[str, str], defaults_raw: dict[str, str]) -> ResolvedVar:
    if name in tfvars_raw:
        return ResolvedVar(_coerce(tfvars_raw[name]), "tfvars_override", tfvars_raw[name])
    env_val = os.getenv(f"TF_VAR_{name}")
    if env_val is not None:
        return ResolvedVar(_coerce(env_val), "tfvar_env_override", env_val)
    if name in defaults_raw:
        return ResolvedVar(_coerce(defaults_raw[name]), "declared_default", defaults_raw[name])
    return ResolvedVar(_CODE_DEFAULTS[name], "not_found", None)


def load(infra_dir: str | None = None) -> AriaTerraformConfig:
    if infra_dir is None:
        infra_dir = os.path.normpath(
            os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "..", "..", "infra")
        )
    variables_tf = os.path.join(infra_dir, "variables.tf")
    main_tf = os.path.join(infra_dir, "main.tf")
    tfvars = os.path.join(infra_dir, "terraform.tfvars")

    variables_tf_found = os.path.isfile(variables_tf)
    tfvars_found = os.path.isfile(tfvars)

    defaults_raw = _parse_variables_tf(variables_tf) if variables_tf_found else {}
    tfvars_raw = _parse_tfvars(tfvars) if tfvars_found else {}

    aria_bedrock_enabled = _resolve("aria_bedrock_enabled", tfvars_raw, defaults_raw)
    ai_router_model_3_id = _resolve("ai_router_model_3_id", tfvars_raw, defaults_raw)
    ai_router_model_3_name = _resolve("ai_router_model_3_name", tfvars_raw, defaults_raw)

    id_fallback, name_fallback, pattern_matched = _router3_fallbacks(main_tf)
    id_effective = ai_router_model_3_id.value if ai_router_model_3_id.value else id_fallback
    name_effective = ai_router_model_3_name.value if ai_router_model_3_name.value else name_fallback

    return AriaTerraformConfig(
        aria_bedrock_enabled=aria_bedrock_enabled,
        ai_router_model_3_id=ai_router_model_3_id,
        ai_router_model_3_name=ai_router_model_3_name,
        ai_router_model_3_id_effective=str(id_effective),
        ai_router_model_3_name_effective=str(name_effective),
        variables_tf_found=variables_tf_found,
        tfvars_found=tfvars_found,
        main_tf_fallback_pattern_matched=pattern_matched,
    )


def to_dict(config: AriaTerraformConfig) -> dict:
    def _var(rv: ResolvedVar) -> dict:
        return {"value": rv.value, "source": rv.source, "raw": rv.raw}

    return {
        "aria_bedrock_enabled": _var(config.aria_bedrock_enabled),
        "ai_router_model_3_id": _var(config.ai_router_model_3_id),
        "ai_router_model_3_name": _var(config.ai_router_model_3_name),
        "ai_router_model_3_id_effective": config.ai_router_model_3_id_effective,
        "ai_router_model_3_name_effective": config.ai_router_model_3_name_effective,
        "bedrock_live_for_chat": config.bedrock_live_for_chat,
        "variables_tf_found": config.variables_tf_found,
        "tfvars_found": config.tfvars_found,
        "main_tf_fallback_pattern_matched": config.main_tf_fallback_pattern_matched,
    }


def render_text(config: AriaTerraformConfig) -> str:
    lines = [
        "[REAL AI CONFIGURATION — backend/infra Terraform]",
        f"- aria_bedrock_enabled: {config.aria_bedrock_enabled.value}  "
        f"(source: {config.aria_bedrock_enabled.source})",
        f"  -> POST /ai/chat calls live Bedrock: {config.bedrock_live_for_chat}"
        + ("" if config.bedrock_live_for_chat else
           "  (deterministic engine only in this configuration)"),
        f"- ai_router_model_3: {config.ai_router_model_3_id_effective} "
        f"(\"{config.ai_router_model_3_name_effective}\") "
        f"(source: {config.ai_router_model_3_id.source})",
        "  -> NOT used by /ai/chat -- powers /ai/router and /coach/* only "
        "(a separate 3-slot consensus system SimRunner does not model)",
        "- /ai/chat's actual models are hardcoded in Python, not Terraform-"
        "configurable: anthropic.claude-opus-4-8 / anthropic.claude-sonnet-4-6 "
        "(SimRunner's query_router.ROUTING_MODELS already mirrors these)",
    ]
    if not config.variables_tf_found:
        lines.append("  ! backend/infra/variables.tf not found -- using hardcoded fallbacks")
    if not config.main_tf_fallback_pattern_matched:
        lines.append(
            "  ! could not find the expected router-3 fallback ternary in main.tf -- "
            "this module's assumption about it may be stale"
        )
    return "\n".join(lines)
