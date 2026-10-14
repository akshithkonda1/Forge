"""scripts/update_model_ids.py — keeps ARIA's Bedrock model slots current.

Runs against a temporary copy of the real files with a fixed list of
"available" ids, so no AWS call is made and the repo is never touched.
"""

from __future__ import annotations

import importlib.util
import shutil
import sys
import tempfile
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]
_spec = importlib.util.spec_from_file_location("update_model_ids", REPO / "scripts" / "update_model_ids.py")
umi = importlib.util.module_from_spec(_spec)
sys.modules["update_model_ids"] = umi
_spec.loader.exec_module(umi)


def _copy_repo_subset() -> Path:
    root = Path(tempfile.mkdtemp(prefix="model-ids-"))
    for rel in (*umi.TARGET_FILES, umi.CATALOG_FILE):
        src = REPO / rel
        if src.exists():
            dst = root / rel
            dst.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(src, dst)
    return root


def _current(root: Path) -> dict[str, str]:
    out = {}
    for slot in umi.SLOTS:
        out[slot.name] = slot.anchor.search((root / slot.anchor_file).read_text()).group(1)
    return out


class NewestTests(unittest.TestCase):
    def test_versions_compare_numerically(self):
        opus = umi.FAMILIES["opus"]
        self.assertEqual(opus.version("global.anthropic.claude-opus-5-5"), (5, 5))
        self.assertEqual(opus.version("anthropic.claude-opus-5"), (5,))
        self.assertIsNone(opus.version("anthropic.claude-opus-4-1-20250805-v1:0"))
        self.assertIsNone(opus.version("global.anthropic.claude-sonnet-5-5"))
        self.assertEqual(umi.FAMILIES["grok"].version("global.xai.grok-4.10"), (4, 10))

    def test_picks_newest_in_family_and_keeps_routing_style(self):
        available = {
            "global.anthropic.claude-opus-5-5", "us.anthropic.claude-opus-5-5",
            "global.anthropic.claude-opus-5", "global.anthropic.claude-sonnet-6",
        }
        self.assertEqual(umi.newest(umi.FAMILIES["opus"], "us.anthropic.claude-opus-5", available),
                         "us.anthropic.claude-opus-5-5")
        self.assertEqual(umi.newest(umi.FAMILIES["opus"], "global.anthropic.claude-opus-5", available),
                         "global.anthropic.claude-opus-5-5")

    def test_in_region_id_moves_to_global_when_only_profiles_exist(self):
        available = {"global.anthropic.claude-opus-5-5", "us.anthropic.claude-opus-5-5"}
        self.assertEqual(umi.newest(umi.FAMILIES["opus"], "anthropic.claude-opus-4-8", available),
                         "global.anthropic.claude-opus-5-5")

    def test_never_downgrades(self):
        self.assertEqual(
            umi.newest(umi.FAMILIES["grok"], "global.xai.grok-4.7", {"global.xai.grok-4.6"}),
            "global.xai.grok-4.7",
        )

    def test_replace_is_whole_id_only(self):
        text = '"anthropic.claude-opus-5" and "anthropic.claude-opus-5-5"'
        self.assertEqual(
            umi._replace_id(text, "anthropic.claude-opus-5", "anthropic.claude-opus-6"),
            '"anthropic.claude-opus-6" and "anthropic.claude-opus-5-5"',
        )


class EndToEndTests(unittest.TestCase):
    def setUp(self):
        self.root = _copy_repo_subset()

    def tearDown(self):
        shutil.rmtree(self.root, ignore_errors=True)

    def test_upgrade_rewrites_every_default_and_nothing_when_current(self):
        before = _current(self.root)
        available = {
            "global.anthropic.claude-opus-6", "global.anthropic.claude-sonnet-6",
            "global.xai.grok-5.0", "us.xai.grok-5.0",
        }
        changes = umi.plan(available, self.root)
        self.assertEqual({slot.name for slot, _, _ in changes}, {s.name for s in umi.SLOTS})
        umi.apply(changes, self.root)
        after = _current(self.root)
        self.assertEqual(after["chat primary"], "global.anthropic.claude-opus-6")
        self.assertEqual(after["router slot 2"], "global.anthropic.claude-opus-6")
        self.assertEqual(after["chat fast"], "global.anthropic.claude-sonnet-6")
        self.assertEqual(after["router slot 1"], "global.anthropic.claude-sonnet-6")
        self.assertEqual(after["router slot 3"], "global.xai.grok-5.0")
        # Old defaults are gone from every target file, Terraform included.
        for rel in umi.TARGET_FILES:
            path = self.root / rel
            if not path.exists():
                continue
            text = path.read_text()
            for old in set(before.values()):
                self.assertIsNone(
                    umi.re.search(rf"(?<!{umi._ID_CHARS}){umi.re.escape(old)}(?!{umi._ID_CHARS})", text),
                    f"{old} left in {rel}",
                )
        main_tf = (self.root / "backend/infra/main.tf").read_text()
        self.assertIn('"global.anthropic.claude-opus-6"', main_tf)
        self.assertIn('"Claude Opus 6"', main_tf)
        catalog = (self.root / umi.CATALOG_FILE).read_text()
        self.assertIn('("global.xai.grok-5.0",', catalog)
        # Second run: already current, nothing to do.
        self.assertEqual(umi.plan(available, self.root), [])

    def test_check_mode_reports_without_writing(self):
        ids = self.root / "ids.json"
        ids.write_text('["global.anthropic.claude-opus-9"]')
        before = (self.root / "backend/infra/lambda/ai_router.py").read_text()
        code = umi.main(["--available", str(ids), "--check", "--root", str(self.root)])
        self.assertEqual(code, 1)
        self.assertEqual((self.root / "backend/infra/lambda/ai_router.py").read_text(), before)


if __name__ == "__main__":
    unittest.main()
