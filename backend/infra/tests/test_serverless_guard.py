"""Cheap guard: the default Terraform stack stays serverless.

Scans ``backend/infra/**/*.tf`` (not ``.terraform``). Fails on provisioned
Lambda concurrency, provisioned DynamoDB, or always-on compute. The only
exception is a forbidden resource whose ``count`` is exactly
``local.scout_count`` (ARIA Scout, ``enable_scout`` default false).
Reserved concurrency is allowed: it is a free cap, default null.
"""

from __future__ import annotations

import re
from pathlib import Path

INFRA_DIR = Path(__file__).resolve().parents[1]

FORBIDDEN_RESOURCE_TYPES = frozenset(
    {
        "aws_lambda_provisioned_concurrency_config",
        "aws_instance",
        "aws_eip",
        "aws_db_instance",
        "aws_rds_cluster",
        "aws_ecs_service",
        "aws_eks_cluster",
        "aws_nat_gateway",
        "aws_autoscaling_group",
        "aws_lb",
        "aws_opensearch_domain",
        "aws_sagemaker_endpoint",
        "aws_vpc_endpoint",
    }
)
FORBIDDEN_RESOURCE_PREFIXES = ("aws_elasticache_",)
SCOUT_COUNT_ALLOWLIST = "local.scout_count"

_RESOURCE_RE = re.compile(r'resource\s+"([^"]+)"\s+"([^"]+)"\s*\{')
_COUNT_RE = re.compile(r"(?m)^\s*count\s*=\s*local\.scout_count\b")
_BILLING_MODE_RE = re.compile(r"billing_mode\s*=\s*(?:\"([^\"]+)\"|([^\s#]+))")
_CAPACITY_RE = re.compile(r"\b(read_capacity|write_capacity)\b")


def _tf_files() -> list[Path]:
    files = []
    for path in INFRA_DIR.rglob("*.tf"):
        if ".terraform" in path.parts:
            continue
        files.append(path)
    return files


def _strip_line_comments(text: str) -> str:
    out: list[str] = []
    for line in text.splitlines(True):
        in_str = False
        buf: list[str] = []
        i = 0
        while i < len(line):
            ch = line[i]
            if ch == '"' and (i == 0 or line[i - 1] != "\\"):
                in_str = not in_str
                buf.append(ch)
            elif not in_str and ch == "#":
                if line.endswith("\n"):
                    buf.append("\n")
                break
            elif not in_str and line.startswith("//", i):
                if line.endswith("\n"):
                    buf.append("\n")
                break
            else:
                buf.append(ch)
            i += 1
        out.append("".join(buf))
    return "".join(out)


def _skip_hcl_string(text: str, i: int) -> int:
    quote = text[i]
    i += 1
    while i < len(text):
        if text[i] == "\\" and i + 1 < len(text):
            i += 2
            continue
        if text[i] == quote:
            return i + 1
        i += 1
    return i


def _resource_body(text: str, open_brace: int) -> str:
    depth = 0
    i = open_brace
    while i < len(text):
        ch = text[i]
        if ch in "\"'":
            i = _skip_hcl_string(text, i)
            continue
        if ch == "{":
            depth += 1
            i += 1
            continue
        if ch == "}":
            depth -= 1
            if depth == 0:
                return text[open_brace + 1 : i]
            i += 1
            continue
        i += 1
    return text[open_brace + 1 :]


def _is_forbidden_type(resource_type: str) -> bool:
    if resource_type in FORBIDDEN_RESOURCE_TYPES:
        return True
    return any(resource_type.startswith(prefix) for prefix in FORBIDDEN_RESOURCE_PREFIXES)


def _iter_resources(text: str):
    for match in _RESOURCE_RE.finditer(text):
        body = _resource_body(text, match.end() - 1)
        yield match.group(1), match.group(2), body


def test_no_forbidden_always_on_resources():
    findings: list[str] = []
    for path in _tf_files():
        text = _strip_line_comments(path.read_text(encoding="utf-8"))
        rel = path.relative_to(INFRA_DIR)
        for resource_type, name, body in _iter_resources(text):
            if not _is_forbidden_type(resource_type):
                continue
            if _COUNT_RE.search(body):
                continue
            findings.append(
                f"{rel}: resource \"{resource_type}\" \"{name}\" is always-on "
                f"(count is not {SCOUT_COUNT_ALLOWLIST})"
            )
    assert findings == [], "always-on / billed-idle resources:\n" + "\n".join(findings)


def test_dynamodb_is_pay_per_request_and_has_no_capacity():
    findings: list[str] = []
    saw_pay_per_request = False
    for path in _tf_files():
        text = _strip_line_comments(path.read_text(encoding="utf-8"))
        rel = path.relative_to(INFRA_DIR)
        for match in _BILLING_MODE_RE.finditer(text):
            mode = (match.group(1) or match.group(2) or "").strip().strip('"')
            if mode == "PAY_PER_REQUEST":
                saw_pay_per_request = True
            else:
                findings.append(f"{rel}: billing_mode = {mode!r} (must be PAY_PER_REQUEST)")
        for match in _CAPACITY_RE.finditer(text):
            findings.append(f"{rel}: found {match.group(1)} (provisioned capacity is forbidden)")
    assert saw_pay_per_request, "no DynamoDB billing_mode = PAY_PER_REQUEST found"
    assert findings == [], "provisioned DynamoDB:\n" + "\n".join(findings)


def test_no_provisioned_concurrency_resource():
    findings: list[str] = []
    for path in _tf_files():
        text = _strip_line_comments(path.read_text(encoding="utf-8"))
        rel = path.relative_to(INFRA_DIR)
        for resource_type, name, _body in _iter_resources(text):
            if resource_type == "aws_lambda_provisioned_concurrency_config":
                findings.append(f"{rel}: resource \"{resource_type}\" \"{name}\"")
    assert findings == [], "provisioned concurrency:\n" + "\n".join(findings)


def test_lambda_reserved_concurrency_rejects_zero():
    variables = (INFRA_DIR / "variables.tf").read_text(encoding="utf-8")
    assert "variable \"lambda_reserved_concurrency\"" in variables
    assert "var.lambda_reserved_concurrency == null" in variables
    assert "var.lambda_reserved_concurrency >= 1" in variables
    assert "default     = null" in variables.split('variable "lambda_reserved_concurrency"')[1][
        :800
    ]


def test_aria_pause_fail_mode_defaults_to_paused():
    variables = (INFRA_DIR / "variables.tf").read_text(encoding="utf-8")
    block = variables.split('variable "aria_pause_fail_mode"')[1][:800]
    assert 'default     = "paused"' in block
    assert 'default     = "open"' not in block


def test_log_retention_defaults_are_7_or_14_days():
    locals_tf = (INFRA_DIR / "locals.tf").read_text(encoding="utf-8")
    assert "is_prod_like ? 14 : 7" in locals_tf
    assert "is_prod_like ? 30 : 14" not in locals_tf


def test_cost_dashboard_is_opt_in():
    variables = (INFRA_DIR / "variables.tf").read_text(encoding="utf-8")
    block = variables.split('variable "enable_cost_dashboard"')[1][:500]
    assert "default     = false" in block
    costs = (INFRA_DIR / "costs.tf").read_text(encoding="utf-8")
    assert "count = var.enable_cost_dashboard ? 1 : 0" in costs


def test_spend_guard_has_forecasted_alert():
    main = (INFRA_DIR / "main.tf").read_text(encoding="utf-8")
    assert 'type = "FORECASTED"' in main
    assert 'type = "ACTUAL"' in main


def test_no_eventbridge_schedulers_or_warmers():
    findings: list[str] = []
    forbidden = (
        "aws_cloudwatch_event_rule",
        "aws_scheduler_schedule",
        "aws_lambda_provisioned_concurrency_config",
    )
    for path in _tf_files():
        text = _strip_line_comments(path.read_text(encoding="utf-8"))
        rel = path.relative_to(INFRA_DIR)
        for resource_type, name, _body in _iter_resources(text):
            if resource_type in forbidden:
                findings.append(f'{rel}: resource "{resource_type}" "{name}"')
    assert findings == [], "schedulers / warmers:\n" + "\n".join(findings)


def test_alarm_count_is_within_free_tier():
    alarms_tf = (INFRA_DIR / "alarms.tf").read_text(encoding="utf-8")
    keys = re.findall(r"^\s{4}([a-z0-9_]+)\s*=\s*\{", alarms_tf, re.M)
    # Keys of local.standard_alarms. Keep this in the 10-alarm free tier.
    assert 1 <= len(keys) <= 10, keys
    assert len(keys) == 7, keys
