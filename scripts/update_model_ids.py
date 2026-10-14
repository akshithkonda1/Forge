#!/usr/bin/env python3
"""Keep ARIA's Bedrock model ids on the newest model in each family.

Five slots carry a model id, each in one family:

    /ai/chat primary   (aria_engine MODEL_PRIMARY)   Claude Opus
    /ai/chat fast      (aria_engine MODEL_FAST)      Claude Sonnet
    router slot 1      (AI_ROUTER_MODEL_1_ID)        Claude Sonnet
    router slot 2      (AI_ROUTER_MODEL_2_ID)        Claude Opus
    router slot 3      (AI_ROUTER_MODEL_3_ID)        Grok

The current id of each slot is read from the code default (the anchor). The
ids Bedrock actually offers come from ``ListFoundationModels`` +
``ListInferenceProfiles`` (or ``--available`` for offline runs and tests).
For each slot the newest id in the same family wins, keeping the slot's
routing style (``global.`` / ``us.`` / in-Region) when that style exists and
otherwise preferring ``global.`` then ``us.`` — Claude 5.x and Grok on
bedrock-runtime are served only through cross-region profiles.

An upgrade rewrites the old id everywhere it is the default: Lambda code,
Terraform fallbacks and docs, the SimRunner mirrors, and the tests that pin
the default. Quoted display names ("Claude Opus 5.5") follow the id; prose
that describes a model is left for a human. Dated or
versioned ids (``-20250514-v1:0``) are ignored; this tree uses canonical ids.

Scout's model (``scout_model_id``) is out of scope.

Usage:

    scripts/update_model_ids.py --dry-run          # show what would change
    scripts/update_model_ids.py                    # rewrite files
    scripts/update_model_ids.py --available ids.json --summary out.md
    scripts/update_model_ids.py --check            # exit 1 if an upgrade exists

Needs ``bedrock:ListFoundationModels`` and ``bedrock:ListInferenceProfiles``
(read-only) unless ``--available`` is given.
"""

from __future__ import annotations

import argparse
import json
import re
import sys
from dataclasses import dataclass
from pathlib import Path

REPO = Path(__file__).resolve().parents[1]

# Files where a slot's default id lives. Only exact, whole-id matches change.
TARGET_FILES = (
    "backend/infra/lambda/ai_router.py",
    "backend/infra/lambda/aria_core/aria_engine.py",
    "backend/ai/app/routes/archetype.py",
    "backend/infra/main.tf",
    "backend/infra/variables.tf",
    "backend/infra/terraform.tfvars.example",
    "backend/README.md",
    "backend/ai/simrunner/aria_simrunner/terraform_config.py",
    "backend/ai/simrunner/aria_simrunner/query_router.py",
    "backend/ai/simrunner/sim_config.yaml",
    "backend/ai/simrunner/tests/test_terraform_config.py",
    "backend/ai/simrunner/tests/test_evaluator_and_router.py",
    "backend/tests/test_ai_router.py",
    "backend/tests/test_aria_engine.py",
    "backend/tests/test_backend_handler.py",
    "backend/tests/test_bedrock_request_shape.py",
    "ForgeSwift/ForgeSwift/Services/LocalTestingOrchestrator.swift",
)
# Model registries keep every id they list; a new id is added beside the old.
CATALOG_FILE = "backend/ai/simrunner/backend_simulator/bedrock_catalog.py"

_ID_CHARS = r"[A-Za-z0-9.\-:]"


@dataclass(frozen=True)
class Family:
    key: str
    # Canonical id body after the optional routing prefix; groups = version.
    pattern: re.Pattern[str]
    display: str

    def version(self, model_id: str) -> tuple[int, ...] | None:
        match = self.pattern.fullmatch(_strip_prefix(model_id))
        if not match:
            return None
        return tuple(int(g) for g in match.groups() if g is not None)


FAMILIES = {
    "opus": Family("opus", re.compile(r"anthropic\.claude-opus-(\d+)(?:-(\d+))?"), "Claude Opus"),
    "sonnet": Family("sonnet", re.compile(r"anthropic\.claude-sonnet-(\d+)(?:-(\d+))?"), "Claude Sonnet"),
    "grok": Family("grok", re.compile(r"xai\.grok-(\d+)(?:\.(\d+))?"), "Grok"),
}


@dataclass(frozen=True)
class Slot:
    name: str
    family: str
    anchor_file: str
    anchor: re.Pattern[str]


SLOTS = (
    Slot("chat primary", "opus", "backend/infra/lambda/aria_core/aria_engine.py",
         re.compile(r'MODEL_PRIMARY:[^\n]*?"((?:global\.|us\.)?anthropic\.[^"]+)"')),
    Slot("chat fast", "sonnet", "backend/infra/lambda/aria_core/aria_engine.py",
         re.compile(r'MODEL_FAST:[^\n]*?"((?:global\.|us\.)?anthropic\.[^"]+)"')),
    Slot("router slot 1", "sonnet", "backend/infra/lambda/ai_router.py",
         re.compile(r'"AI_ROUTER_MODEL_1_ID",\s*"([^"]+)"')),
    Slot("router slot 2", "opus", "backend/infra/lambda/ai_router.py",
         re.compile(r'"AI_ROUTER_MODEL_2_ID",\s*"([^"]+)"')),
    Slot("router slot 3", "grok", "backend/infra/lambda/ai_router.py",
         re.compile(r'"AI_ROUTER_MODEL_3_ID",\s*"([^"]+)"')),
)


def _prefix(model_id: str) -> str:
    for p in ("global.", "us.", "eu.", "apac."):
        if model_id.startswith(p):
            return p
    return ""


def _strip_prefix(model_id: str) -> str:
    return model_id[len(_prefix(model_id)):]


def display_name(family: Family, model_id: str) -> str:
    version = family.version(model_id) or ()
    return f"{family.display} {'.'.join(str(v) for v in version)}".strip()


def newest(family: Family, current: str, available: set[str]) -> str:
    """Newest id in ``family``; ties keep the current routing style."""
    cur_version = family.version(current) or ()
    order = [_prefix(current), "global.", "us.", ""]
    best, best_key = current, (cur_version, -order.index(_prefix(current)))
    for model_id in available:
        version = family.version(model_id)
        if version is None or _prefix(model_id) not in order:
            continue
        key = (version, -order.index(_prefix(model_id)))
        if key > best_key:
            best, best_key = model_id, key
    return best


def discover_bedrock(region: str) -> set[str]:
    import boto3  # lazy: only the live path needs it

    client = boto3.client("bedrock", region_name=region)
    ids: set[str] = set()
    for model in client.list_foundation_models().get("modelSummaries", []):
        # A foundation id is only usable on its own when it supports on-demand
        # invocation; profile-only models (Claude 5.x, Grok) come in below.
        if model.get("modelId") and "ON_DEMAND" in (model.get("inferenceTypesSupported") or []):
            ids.add(model["modelId"])
    token = None
    while True:
        kwargs = {"maxResults": 100}
        if token:
            kwargs["nextToken"] = token
        page = client.list_inference_profiles(**kwargs)
        for profile in page.get("inferenceProfileSummaries", []):
            if profile.get("inferenceProfileId"):
                ids.add(profile["inferenceProfileId"])
        token = page.get("nextToken")
        if not token:
            return ids


def _replace_id(text: str, old: str, new: str) -> str:
    return re.sub(rf"(?<!{_ID_CHARS}){re.escape(old)}(?!{_ID_CHARS})", new, text)


def plan(available: set[str], root: Path = REPO) -> list[tuple[Slot, str, str]]:
    changes = []
    for slot in SLOTS:
        source = (root / slot.anchor_file).read_text()
        match = slot.anchor.search(source)
        if not match:
            raise SystemExit(f"anchor for {slot.name} not found in {slot.anchor_file}")
        current = match.group(1)
        upgrade = newest(FAMILIES[slot.family], current, available)
        if upgrade != current:
            changes.append((slot, current, upgrade))
    return changes


def apply(changes: list[tuple[Slot, str, str]], root: Path = REPO) -> list[str]:
    touched: list[str] = []
    renames: dict[str, str] = {}
    for slot, old, new in changes:
        renames[old] = new
    for rel in TARGET_FILES:
        path = root / rel
        if not path.exists():
            continue
        text = original = path.read_text()
        for old, new in renames.items():
            text = _replace_id(text, old, new)
            for family in FAMILIES.values():
                if family.version(old) is not None:
                    old_name, new_name = display_name(family, old), display_name(family, new)
                    # Only quoted names (code / Terraform defaults). Prose that
                    # names a model is a claim about that model; leave it.
                    if old_name != new_name and old_name != family.display:
                        text = text.replace(f'"{old_name}"', f'"{new_name}"')
        if text != original:
            path.write_text(text)
            touched.append(rel)
    catalog = root / CATALOG_FILE
    if catalog.exists():
        text = original = catalog.read_text()
        for old, new in renames.items():
            if f'("{new}",' in text:
                continue
            line = re.search(rf'^(\s*)\("{re.escape(old)}",([^\n]*)$', text, re.M)
            if line:
                text = text.replace(line.group(0), f'{line.group(1)}("{new}",{line.group(2)}\n{line.group(0)}', 1)
        if text != original:
            catalog.write_text(text)
            touched.append(CATALOG_FILE)
    return touched


def summary(changes: list[tuple[Slot, str, str]], touched: list[str]) -> str:
    if not changes:
        return "All ARIA model slots are on the newest Bedrock model in their family."
    lines = ["| Slot | From | To |", "|---|---|---|"]
    lines += [f"| {slot.name} | `{old}` | `{new}` |" for slot, old, new in changes]
    lines += ["", "Files updated:", *[f"- `{rel}`" for rel in touched]]
    return "\n".join(lines)


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    parser.add_argument("--available", type=Path, help="JSON list of Bedrock ids (skips AWS)")
    parser.add_argument("--region", default="us-east-1")
    parser.add_argument("--dry-run", action="store_true", help="print the plan, change nothing")
    parser.add_argument("--check", action="store_true", help="exit 1 when an upgrade exists")
    parser.add_argument("--summary", type=Path, help="write a markdown summary here")
    parser.add_argument("--root", type=Path, default=REPO, help=argparse.SUPPRESS)
    args = parser.parse_args(argv)

    if args.available:
        available = set(json.loads(args.available.read_text()))
    else:
        available = discover_bedrock(args.region)

    changes = plan(available, args.root)
    touched = [] if (args.dry_run or args.check) else apply(changes, args.root)
    report = summary(changes, touched)
    print(report)
    if args.summary:
        args.summary.write_text(report + "\n")
    if args.check and changes:
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
