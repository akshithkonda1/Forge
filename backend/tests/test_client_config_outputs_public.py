"""CI uploads ``terraform output -json`` of the client config objects.

Those artifacts are downloadable on this public repo, so the two outputs
must stay non-sensitive and contain only public identifiers. Terraform
itself refuses to plan a non-sensitive output that references a sensitive
value, so keeping ``sensitive`` off is the leak tripwire.
"""

from __future__ import annotations

import re
import unittest
from pathlib import Path


_INFRA = Path(__file__).resolve().parents[1] / "infra"
_OUTPUTS_TF = _INFRA / "outputs.tf"

_CLIENT_OUTPUT = "client_configuration"
_DEV_OUTPUT = "dev_client_configuration"

# Flattened object keys (every ``ident =`` inside the value expression).
_CLIENT_CONFIGURATION_KEYS = frozenset({
    "apiBaseUrl",
    "cognito",
    "region",
    "userPoolId",
    "hostedUiDomain",
    "webClientId",
    "iosClientId",
    "kotlinClientId",
    "identityPoolId",
    "iosRedirectUri",
    "webRedirectUri",
    "kotlinRedirectUri",
    "iosLogoutUri",
    "webLogoutUri",
    "kotlinLogoutUri",
    "storage",
    "uploadsBucket",
    "accessLevel",
    "keyPrefixPattern",
})

_DEV_CLIENT_CONFIGURATION_KEYS = frozenset({
    "webLocalhostClientId",
    "kotlinLocalhostClientId",
})

_SECRET_RE = re.compile(
    r"secret|token|password|private|credential|provider_details|override|api_key|client_secret",
    re.IGNORECASE,
)

_OUTPUT_HEAD = re.compile(r'output\s+"([^"]+)"\s*\{')
_CLIENT_HEAD = re.compile(r'resource\s+"aws_cognito_user_pool_client"\s+"([^"]+)"\s*\{')
_KEY_ASSIGN = re.compile(r"([A-Za-z_][A-Za-z0-9_]*)\s*=")
_ATTR_REF = re.compile(r"\.([A-Za-z_][A-Za-z0-9_]*)")
_SENSITIVE_TRUE = re.compile(r"(?m)^\s*sensitive\s*=\s*true\b")
_GENERATE_SECRET_TRUE = re.compile(r"(?m)^\s*generate_secret\s*=\s*true\b")


def _skip_string(text: str, i: int) -> int:
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


def _matching_brace(text: str, start: int) -> int:
    depth = 0
    i = start
    while i < len(text):
        ch = text[i]
        if ch in ("'", '"'):
            i = _skip_string(text, i)
            continue
        if ch == "{":
            depth += 1
        elif ch == "}":
            depth -= 1
            if depth == 0:
                return i
        i += 1
    raise ValueError("unbalanced {")


def _named_blocks(hcl: str, head: re.Pattern[str]) -> dict[str, str]:
    found: dict[str, str] = {}
    for match in head.finditer(hcl):
        brace = match.end() - 1
        end = _matching_brace(hcl, brace)
        found[match.group(1)] = hcl[brace : end + 1]
    return found


def output_blocks(hcl: str) -> dict[str, str]:
    return _named_blocks(hcl, _OUTPUT_HEAD)


def user_pool_clients(hcl: str) -> dict[str, str]:
    return _named_blocks(hcl, _CLIENT_HEAD)


def value_expression(block: str) -> str:
    match = re.search(r"(?m)^\s*value\s*=\s*", block)
    if not match:
        raise ValueError("output block has no value =")
    return block[match.end() :].rstrip().removesuffix("}").strip()


def object_keys(value_expr: str) -> set[str]:
    keys: set[str] = set()

    def walk(start: int) -> None:
        end = _matching_brace(value_expr, start)
        body = value_expr[start + 1 : end]
        depth = 0
        j = 0
        while j < len(body):
            if body[j] in ("'", '"'):
                j = _skip_string(body, j)
                continue
            if body[j] == "{":
                if depth == 0:
                    walk(start + 1 + j)
                depth += 1
                j += 1
                continue
            if body[j] == "}":
                depth -= 1
                j += 1
                continue
            if depth == 0:
                assign = _KEY_ASSIGN.match(body, j)
                if assign:
                    keys.add(assign.group(1))
                    j = assign.end()
                    continue
            j += 1

    i = 0
    while i < len(value_expr):
        ch = value_expr[i]
        if ch in ("'", '"'):
            i = _skip_string(value_expr, i)
            continue
        if ch == "{":
            walk(i)
            i = _matching_brace(value_expr, i) + 1
            continue
        i += 1
    return keys


def referenced_attributes(value_expr: str) -> set[str]:
    return set(_ATTR_REF.findall(value_expr))


def secret_hits(names: set[str]) -> set[str]:
    return {name for name in names if _SECRET_RE.search(name)}


def check_outputs_public(hcl: str) -> list[str]:
    """Return human-readable violations for the two client-config outputs."""
    violations: list[str] = []
    blocks = output_blocks(hcl)
    allowlists = {
        _CLIENT_OUTPUT: _CLIENT_CONFIGURATION_KEYS,
        _DEV_OUTPUT: _DEV_CLIENT_CONFIGURATION_KEYS,
    }
    for name, allow in allowlists.items():
        if name not in blocks:
            violations.append(f"missing output {name!r}")
            continue
        block = blocks[name]
        if _SENSITIVE_TRUE.search(block):
            violations.append(f"{name}: sensitive = true")
        expr = value_expression(block)
        keys = object_keys(expr)
        if keys != allow:
            violations.append(
                f"{name}: keys {sorted(keys)} != allowlist {sorted(allow)}"
            )
        hits = secret_hits(keys | referenced_attributes(expr))
        if hits:
            violations.append(f"{name}: secret-pattern names {sorted(hits)}")
    return violations


def check_generate_secret_false(hcl: str) -> list[str]:
    violations: list[str] = []
    for name, block in user_pool_clients(hcl).items():
        if _GENERATE_SECRET_TRUE.search(block):
            violations.append(f"aws_cognito_user_pool_client.{name}: generate_secret = true")
    return violations


def _load_infra_tf() -> str:
    chunks = [_OUTPUTS_TF.read_text(encoding="utf-8")]
    for path in sorted(_INFRA.glob("*.tf")):
        if path.name == "outputs.tf":
            continue
        chunks.append(path.read_text(encoding="utf-8"))
    return "\n\n".join(chunks)


class ClientConfigOutputsPublicTests(unittest.TestCase):
    def test_live_outputs_are_public_and_allowlisted(self):
        hcl = _OUTPUTS_TF.read_text(encoding="utf-8")
        self.assertEqual(check_outputs_public(hcl), [])

    def test_live_user_pool_clients_do_not_generate_secrets(self):
        hcl = _load_infra_tf()
        clients = user_pool_clients(hcl)
        self.assertGreaterEqual(len(clients), 5)
        self.assertEqual(check_generate_secret_false(hcl), [])

    def test_synthetic_sensitive_and_client_secret_are_caught(self):
        synthetic = """
output "client_configuration" {
  sensitive = true
  value = {
    client_secret = aws_cognito_user_pool_client.web.client_secret
  }
}

output "dev_client_configuration" {
  value = {
    webLocalhostClientId    = aws_cognito_user_pool_client.web_localhost[0].id
    kotlinLocalhostClientId = aws_cognito_user_pool_client.kotlin_localhost[0].id
  }
}
"""
        violations = check_outputs_public(synthetic)
        joined = "\n".join(violations)
        self.assertTrue(
            any("sensitive = true" in item for item in violations),
            violations,
        )
        self.assertTrue(
            any("client_secret" in item for item in violations),
            violations,
        )
        self.assertIn(_CLIENT_OUTPUT, joined)

    def test_synthetic_generate_secret_true_is_caught(self):
        synthetic = """
resource "aws_cognito_user_pool_client" "leaky" {
  generate_secret = true
}
"""
        self.assertEqual(
            check_generate_secret_false(synthetic),
            ["aws_cognito_user_pool_client.leaky: generate_secret = true"],
        )


if __name__ == "__main__":
    unittest.main()
