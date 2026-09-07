import os
import sys
import tempfile
import unittest
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[4]))

from backend.ai.simrunner.aria_simrunner import terraform_config as tfc  # noqa: E402

_VARIABLES_TF = '''\
variable "environment" {
  description = "Deploy target."
  type        = string

  validation {
    condition     = contains(["dev", "prod", "staging"], var.environment)
    error_message = "must be one of dev/prod/staging"
  }
}

variable "aria_bedrock_enabled" {
  description = "Turn on ARIA's live Claude (Bedrock) reasoning path behind POST /ai/chat. When false, the endpoint serves the deterministic engine. The live path also falls back to deterministic on any Bedrock error."
  type        = bool
  default     = false
}

variable "ai_router_model_3_id" {
  description = "Bedrock model id for the AI router's third slot — the one agentic turns call in when a mode fans out to its own specialists and subagents. Empty keeps ai_router.py's own default (global.xai.grok-4.6)."
  type        = string
  default     = ""
}

variable "ai_router_model_3_name" {
  description = "Display name for the third router slot — a name that disagrees with the id is worse than no name, because it makes the transcript claim a model that never # answered."
  type        = string
  default     = ""
}
'''

_MAIN_TF = '''\
resource "aws_lambda_function" "backend" {
  environment {
    variables = {
      ARIA_BEDROCK_ENABLED   = var.aria_bedrock_enabled ? "true" : "false"
      AI_ROUTER_MODEL_3_ID   = var.ai_router_model_3_id != "" ? var.ai_router_model_3_id : "global.xai.grok-4.6"
      AI_ROUTER_MODEL_3_NAME = var.ai_router_model_3_name != "" ? var.ai_router_model_3_name : "Grok"
    }
  }
}
'''

_MAIN_TF_RESHAPED = '''\
locals {
  router3_id = coalesce(var.ai_router_model_3_id, "global.xai.grok-4.6")
}
'''

_TFVARS_EXAMPLE = '''\
aws_region   = "us-east-1"
project_name = "forge"
environment  = "dev"

allowed_origins = [
  "http://localhost:3000",
  "http://localhost:5173",
]

tags = {
  Owner = "Forge"
}

# ai_router_model_3_id   = "global.xai.grok-4.6"
# ai_router_model_3_name = "Grok"
'''


def _write(dirpath: str, name: str, content: str) -> None:
    with open(os.path.join(dirpath, name), "w", encoding="utf-8") as fh:
        fh.write(content)


class DefaultsOnlyTests(unittest.TestCase):
    def test_resolves_declared_defaults_with_no_tfvars(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "main.tf", _MAIN_TF)
            config = tfc.load(infra_dir=d)
        self.assertEqual(config.aria_bedrock_enabled.value, False)
        self.assertEqual(config.aria_bedrock_enabled.source, "declared_default")
        self.assertEqual(config.ai_router_model_3_id.value, "")
        self.assertEqual(config.ai_router_model_3_id.source, "declared_default")
        self.assertFalse(config.bedrock_live_for_chat)
        self.assertTrue(config.variables_tf_found)
        self.assertFalse(config.tfvars_found)

    def test_router3_effective_falls_back_to_main_tf_derived_value(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "main.tf", _MAIN_TF)
            config = tfc.load(infra_dir=d)
        self.assertEqual(config.ai_router_model_3_id_effective, "global.xai.grok-4.6")
        self.assertEqual(config.ai_router_model_3_name_effective, "Grok")
        self.assertTrue(config.main_tf_fallback_pattern_matched)

    def test_description_with_literal_hash_inside_quotes_is_not_truncated(self):
        # ai_router_model_3_name's description above contains a literal '#'
        # inside its quoted string ("... never # answered.") -- if comment
        # stripping weren't string-aware, this would corrupt parsing of
        # nearby lines. It shouldn't affect this variable's own `default`
        # line (which is on a separate line), but prove the file as a whole
        # still parses correctly end-to-end.
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            config = tfc.load(infra_dir=d)
        self.assertEqual(config.ai_router_model_3_name.value, "")
        self.assertEqual(config.ai_router_model_3_name.source, "declared_default")


class TfvarsOverrideTests(unittest.TestCase):
    def test_tfvars_present_but_not_touching_target_keys_still_falls_back_to_defaults(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "terraform.tfvars", _TFVARS_EXAMPLE)  # commented-out overrides only
            config = tfc.load(infra_dir=d)
        self.assertTrue(config.tfvars_found)
        self.assertEqual(config.aria_bedrock_enabled.source, "declared_default")
        self.assertEqual(config.ai_router_model_3_id.source, "declared_default")

    def test_multiline_bracketed_value_does_not_confuse_the_line_scanner(self):
        # allowed_origins = [...] spans 3 lines in _TFVARS_EXAMPLE; a target
        # key appears both before and after it in the file.
        tfvars = _TFVARS_EXAMPLE.replace(
            "# ai_router_model_3_id", 'ai_router_model_3_id  = "test.after.bracket"\n# ai_router_model_3_id'
        )
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "terraform.tfvars", tfvars)
            config = tfc.load(infra_dir=d)
        self.assertEqual(config.ai_router_model_3_id.value, "test.after.bracket")
        self.assertEqual(config.ai_router_model_3_id.source, "tfvars_override")

    def test_tfvars_override_wins_over_declared_default(self):
        tfvars = 'aria_bedrock_enabled = true\n'
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "terraform.tfvars", tfvars)
            config = tfc.load(infra_dir=d)
        self.assertEqual(config.aria_bedrock_enabled.value, True)
        self.assertEqual(config.aria_bedrock_enabled.source, "tfvars_override")
        self.assertTrue(config.bedrock_live_for_chat)

    def test_quoted_string_with_dots_unquotes_correctly(self):
        tfvars = 'ai_router_model_3_id   = "global.xai.grok-4.6"\nai_router_model_3_name = "Grok"\n'
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "terraform.tfvars", tfvars)
            config = tfc.load(infra_dir=d)
        self.assertEqual(config.ai_router_model_3_id.value, "global.xai.grok-4.6")
        self.assertEqual(config.ai_router_model_3_name.value, "Grok")
        self.assertEqual(config.ai_router_model_3_id_effective, "global.xai.grok-4.6")


class EnvVarPrecedenceTests(unittest.TestCase):
    def test_tf_var_env_override_with_no_tfvars_file(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            old = os.environ.get("TF_VAR_aria_bedrock_enabled")
            os.environ["TF_VAR_aria_bedrock_enabled"] = "true"
            try:
                config = tfc.load(infra_dir=d)
            finally:
                if old is None:
                    del os.environ["TF_VAR_aria_bedrock_enabled"]
                else:
                    os.environ["TF_VAR_aria_bedrock_enabled"] = old
        self.assertEqual(config.aria_bedrock_enabled.value, True)
        self.assertEqual(config.aria_bedrock_enabled.source, "tfvar_env_override")

    def test_real_tfvars_file_wins_over_env_var(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "terraform.tfvars", "aria_bedrock_enabled = false\n")
            old = os.environ.get("TF_VAR_aria_bedrock_enabled")
            os.environ["TF_VAR_aria_bedrock_enabled"] = "true"
            try:
                config = tfc.load(infra_dir=d)
            finally:
                if old is None:
                    del os.environ["TF_VAR_aria_bedrock_enabled"]
                else:
                    os.environ["TF_VAR_aria_bedrock_enabled"] = old
        # tfvars explicitly sets it to false; must win over the env override of true.
        self.assertEqual(config.aria_bedrock_enabled.value, False)
        self.assertEqual(config.aria_bedrock_enabled.source, "tfvars_override")


class SafeDegradationTests(unittest.TestCase):
    def test_missing_variables_tf_degrades_to_not_found_without_raising(self):
        with tempfile.TemporaryDirectory() as d:
            config = tfc.load(infra_dir=d)  # empty dir, nothing exists
        self.assertFalse(config.variables_tf_found)
        self.assertEqual(config.aria_bedrock_enabled.source, "not_found")
        self.assertEqual(config.aria_bedrock_enabled.value, False)
        self.assertEqual(config.ai_router_model_3_id_effective, "global.xai.grok-4.6")

    def test_unbalanced_braces_degrades_safely_instead_of_raising(self):
        broken = 'variable "aria_bedrock_enabled" {\n  default = false\n'  # missing closing brace
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", broken)
            config = tfc.load(infra_dir=d)  # must not raise
        self.assertEqual(config.aria_bedrock_enabled.source, "not_found")

    def test_reshaped_main_tf_fallback_ternary_sets_pattern_matched_false(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "main.tf", _MAIN_TF_RESHAPED)
            config = tfc.load(infra_dir=d)
        self.assertFalse(config.main_tf_fallback_pattern_matched)
        # Still a safe, documented fallback -- never a crash or a blank value.
        self.assertEqual(config.ai_router_model_3_id_effective, "global.xai.grok-4.6")

    def test_missing_main_tf_also_degrades_safely(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            config = tfc.load(infra_dir=d)  # no main.tf written at all
        self.assertFalse(config.main_tf_fallback_pattern_matched)
        self.assertEqual(config.ai_router_model_3_id_effective, "global.xai.grok-4.6")


class ToDictTests(unittest.TestCase):
    def test_round_trips_through_json_dumps(self):
        import json
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "main.tf", _MAIN_TF)
            config = tfc.load(infra_dir=d)
        payload = tfc.to_dict(config)
        reloaded = json.loads(json.dumps(payload))
        self.assertEqual(reloaded["aria_bedrock_enabled"]["value"], False)
        self.assertEqual(reloaded["bedrock_live_for_chat"], False)
        self.assertEqual(reloaded["ai_router_model_3_id_effective"], "global.xai.grok-4.6")


class RenderTextTests(unittest.TestCase):
    def test_render_text_flags_bedrock_off_and_missing_files(self):
        with tempfile.TemporaryDirectory() as d:
            config = tfc.load(infra_dir=d)  # nothing on disk
        text = tfc.render_text(config)
        self.assertIn("deterministic engine only", text)
        self.assertIn("variables.tf not found", text)

    def test_render_text_omits_warnings_when_everything_resolves_cleanly(self):
        with tempfile.TemporaryDirectory() as d:
            _write(d, "variables.tf", _VARIABLES_TF)
            _write(d, "main.tf", _MAIN_TF)
            config = tfc.load(infra_dir=d)
        text = tfc.render_text(config)
        self.assertNotIn("not found", text)
        self.assertNotIn("may be stale", text)


if __name__ == "__main__":
    unittest.main()
