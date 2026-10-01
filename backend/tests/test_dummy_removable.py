"""Production survives the Dummy orchestrator being deleted.

The Lambda zip is ``backend/infra/lambda`` and nothing else (Terraform
``archive_file.backend_lambda``). The Dummy lives in ``backend/ai``:
SimRunner's ``dummy_orchestrator``, the ``aria_chat`` Dummy chat, and their
harnesses. These tests hold that line three ways:

1. Static: no production module imports the Dummy, lazily or otherwise.
2. Packaging: Terraform zips the Lambda directory only.
3. Deletion: a copy of the Lambda package, with the repo (and so every Dummy
   file) absent from ``sys.path``, imports every module and serves real
   ``/ai/chat`` turns — coaching, triage, and escalation — through the handler.
"""

from __future__ import annotations

import ast
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path

import _bootstrap  # noqa: F401

BACKEND = Path(__file__).resolve().parents[1]
LAMBDA_ROOT = BACKEND / "infra" / "lambda"
MAIN_TF = BACKEND / "infra" / "main.tf"

# Anything Dummy-owned. Production may never name these in an import.
FORBIDDEN_MODULE_PREFIXES = (
    "backend.ai.simrunner",
    "backend.ai.aria_chat",
    "backend.ai.aria_cli",
    "backend.simrunner",
    "aria_simrunner",
    "aria_chat",
    "simrunner",
)
FORBIDDEN_MODULE_PARTS = ("dummy_orchestrator",)


def _production_files() -> list[Path]:
    return sorted(
        path
        for path in LAMBDA_ROOT.rglob("*.py")
        if "__pycache__" not in path.parts
    )


def _imported_names(tree: ast.AST) -> list[str]:
    names: list[str] = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            names.extend(alias.name for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.level == 0 and node.module:
            names.append(node.module)
            names.extend(f"{node.module}.{alias.name}" for alias in node.names)
        elif isinstance(node, ast.Call):
            func = node.func
            called = getattr(func, "attr", None) or getattr(func, "id", None)
            if called in {"import_module", "__import__"} and node.args:
                first = node.args[0]
                if isinstance(first, ast.Constant) and isinstance(first.value, str):
                    names.append(first.value)
    return names


def _is_forbidden(name: str) -> bool:
    if name.startswith(FORBIDDEN_MODULE_PREFIXES):
        return True
    return any(part in name for part in FORBIDDEN_MODULE_PARTS)


class StaticImportGuardTests(unittest.TestCase):
    def test_no_production_module_imports_the_dummy(self):
        files = _production_files()
        self.assertGreater(len(files), 100)
        hits: list[str] = []
        for path in files:
            tree = ast.parse(path.read_text(encoding="utf-8"), filename=str(path))
            for name in _imported_names(tree):
                if _is_forbidden(name):
                    hits.append(f"{path.relative_to(BACKEND)} imports {name}")
        self.assertEqual(hits, [], "\n".join(hits))

    def test_guard_catches_lazy_and_importlib_imports(self):
        sample = ast.parse(
            "def f():\n"
            "    from backend.ai.simrunner.aria_simrunner import dummy_orchestrator\n"
            "    import importlib\n"
            "    importlib.import_module('backend.ai.aria_chat.session')\n"
        )
        found = [name for name in _imported_names(sample) if _is_forbidden(name)]
        self.assertIn("backend.ai.simrunner.aria_simrunner", found)
        self.assertIn("backend.ai.aria_chat.session", found)

    def test_no_dummy_files_inside_the_lambda_package(self):
        bad = [
            str(path.relative_to(BACKEND))
            for path in LAMBDA_ROOT.rglob("*")
            if "dummy_orchestrator" in path.name
            or path.name in {"aria_chat", "simrunner", "aria_simrunner"}
        ]
        self.assertEqual(bad, [])


class PackagingGuardTests(unittest.TestCase):
    def test_terraform_zips_only_the_lambda_directory(self):
        text = MAIN_TF.read_text(encoding="utf-8")
        block = re.search(
            r'data\s+"archive_file"\s+"backend_lambda"\s*\{(.*?)\n\}', text, re.S
        )
        self.assertIsNotNone(block, "archive_file.backend_lambda not found")
        self.assertRegex(block.group(1), r'source_dir\s*=\s*"\$\{path\.module\}/lambda"')


class DeletedDummyRunsTests(unittest.TestCase):
    """Copy exactly what ships, hide the repo, and serve real turns."""

    SCRIPT = r"""
import importlib, importlib.util, json, pkgutil, sys
# The repo's ``backend`` package (and every Dummy file in it) must be unreachable.
out = {"repo_on_path": importlib.util.find_spec("backend") is not None}
failed = []
for mod in pkgutil.walk_packages(["."]):
    try:
        importlib.import_module(mod.name)
    except Exception as exc:
        failed.append(f"{mod.name}: {exc!r}"[:200])
out["failed_imports"] = failed
out["modules"] = len(sys.modules)
from handler import handler

def event(body):
    return {
        "requestContext": {
            "http": {"method": "POST", "path": "/ai/chat"},
            "authorizer": {"jwt": {"claims": {"sub": "no-dummy-user"}}},
        },
        "headers": {},
        "body": json.dumps(body),
    }

turns = []
for body in (
    {"message": "should I train hard today?"},
    {"message": "I have chest pain"},
    {"message": "yes, it's spreading to my arm", "triage_topic": "chest_pain.self"},
    {"message": "I don't want to live anymore"},
):
    resp = handler(event(body))
    payload = json.loads(resp["body"])
    turns.append({
        "status": resp["statusCode"],
        "band": payload.get("guidance_band"),
        "phase": (payload.get("safety") or {}).get("phase"),
    })
out["turns"] = turns
out["dummy_modules"] = sorted(
    m for m in sys.modules
    if m.startswith(("backend", "aria_simrunner", "aria_chat", "simrunner"))
    or "dummy_orchestrator" in m
)
print(json.dumps(out))
"""

    def test_production_lambda_runs_with_the_dummy_deleted(self):
        with tempfile.TemporaryDirectory() as tmp:
            shipped = Path(tmp) / "lambda"
            shutil.copytree(
                LAMBDA_ROOT,
                shipped,
                ignore=shutil.ignore_patterns("__pycache__", "*.pyc", "*.pyo"),
            )
            env = {
                key: value
                for key, value in os.environ.items()
                if key not in {"PYTHONPATH", "APP_DATA_TABLE_NAME", "ARIA_BEDROCK_ENABLED"}
            }
            env["ENVIRONMENT"] = "test"
            result = subprocess.run(
                [sys.executable, "-E", "-s", "-c", self.SCRIPT],
                cwd=shipped,
                env=env,
                capture_output=True,
                text=True,
                timeout=300,
            )
        self.assertEqual(result.returncode, 0, result.stderr[-4000:])
        out = json.loads(result.stdout.strip().splitlines()[-1])
        self.assertFalse(out["repo_on_path"])
        self.assertEqual(out["failed_imports"], [])
        self.assertEqual(out["dummy_modules"], [])
        self.assertEqual([t["status"] for t in out["turns"]], [200, 200, 200, 200])
        self.assertEqual(
            [(t["band"], t["phase"]) for t in out["turns"]],
            [
                (None, None),
                ("triage", "triage"),
                ("emergency", "escalate"),
                ("emergency", "escalate"),
            ],
        )


if __name__ == "__main__":
    unittest.main()
