import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import tempfile
import unittest


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "shell" / "ccp-functions.sh"
ENTRIES = (
  "cc-luna", "cc-free", "ccp-gpt", "ccp-sol", "ccp-gpt-smart", "ccp-gpt-fast",
  "ccp-mix-gpt", "ccp-mix-sol", "ccp-free", "ccp-gemini-pro", "ccp-gemini-flash",
  "ccp-relay", "ccp-bruce", "ccp-deepseek", "ccp-deepseek-flash", "ccp-deepseek-pro",
)
VERSIONS = "GPT_ASTRA=gpt-test-astra\nGPT_SOL=gpt-test-sol\nGPT_LUNA=gpt-test-luna\n"
RELAY = """openai-compatibility:
  - name: cline-low
    priority: 1
    base-url: http://127.0.0.1:3457/v1
    api-key-entries:
      - api-key: CREDENTIAL-CANARY
    models:
      - name: free-ds
        alias: free
  - name: router-high
    priority: 9
    base-url: http://127.0.0.1:8002/v1
    models:
      - name: agentrouter-glm
        alias: free
  - name: disabled-owner
    priority: 99
    disabled: true
    models:
      - name: MUST-NOT-APPEAR
        alias: free
  - name: smart-owner
    priority: 20
    models:
      - name: smart-model
        alias: free-smart
"""


def table_rows(output):
  rows = []
  for line in output.splitlines():
    if "|" not in line:
      continue
    cells = [cell.strip() for cell in line.split("|")[1:-1]]
    if not cells:
      continue
    entry = re.search(r"\b(ccp-[a-z-]+|cc-luna|cc-free)\b", cells[0])
    if entry:
      rows.append((entry.group(1), cells))
  return rows


class ModelMapTest(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.fixture = Path(self.temp.name)
    self.versions = self.fixture / "models.env"
    self.config = self.fixture / "relay.yaml"
    self.versions.write_text(VERSIONS)
    self.config.write_text(RELAY)
    self.agentrouter = self.fixture / "agentrouter.yaml"
    self.agentrouter.write_text("""model_list:
  - model_name: agentrouter-glm
    litellm_params:
      model: openai/deepseek-test-flash
      api_base: https://example.test/v1
""")
    self.litellm = self.fixture / "litellm.yaml"
    self.litellm.write_text("model_list: []\n")
    self.env = {
      key: value for key, value in os.environ.items()
      if not key.startswith(("ANTHROPIC_", "CLAUDE_CODE_", "GPT_", "CCP_MODEL_MAP_"))
      and key not in ("CC_VENDOR", "CC_CLAUDE_BIN", "CLAUDE_CONFIG_DIR")
    }
    self.env.update({
      "CCP_GPT_MODELS_FILE": str(self.versions),
      "CC_LUNA_MODELS_FILE": str(self.versions),
      "CCP_FREE_CONFIG_FILE": str(self.config),
      "CCP_FREE_AGENTROUTER_CONFIG_FILE": str(self.agentrouter),
      "CCP_FREE_LITELLM_CONFIG_FILE": str(self.litellm),
      "CCP_SPLIT_ROOT": str(ROOT.parent / "cc-split-proxy"),
      "COLUMNS": "360",
      "NO_COLOR": "1",
    })

  def run_cli(self, entry=None, *, script=None, env=None):
    command = "ccp-list" + (" " + shlex.quote(entry) if entry else "")
    result = subprocess.run(
      ["zsh", "-f", "-c", f"source {shlex.quote(str(SOURCE))}; {script or command}"],
      env=env or self.env,
      text=True,
      capture_output=True,
      timeout=30,
    )
    return result

  def test_full_table_uses_current_models_and_excludes_direct_entries(self):
    result = self.run_cli()
    self.assertEqual(result.returncode, 0, result.stderr)
    rows = table_rows(result.stdout)
    self.assertEqual([name for name, _ in rows], list(ENTRIES))
    cells = dict(rows)["ccp-sol"]
    self.assertEqual(cells[1:6], ["gpt-test-sol", "gpt-test-sol", "gpt-test-luna(max)", "gpt-test-luna(max)", "gpt-test-luna(max)"])
    self.assertNotIn("ccp-glm", [name for name, _ in rows])
    self.assertNotIn("ccp-mimo", [name for name, _ in rows])
    self.assertNotIn("ccp-gpt-whoami", [name for name, _ in rows])

  def test_query_entry_is_first_and_other_defaults_ignore_outer_environment(self):
    env = self.env | {
      "ANTHROPIC_MODEL": "outer-pollution",
      "ANTHROPIC_DEFAULT_FABLE_MODEL": "outer-pollution",
      "ANTHROPIC_DEFAULT_OPUS_MODEL": "outer-pollution",
      "CLAUDE_CODE_SUBAGENT_MODEL": "outer-pollution",
    }
    result = self.run_cli("ccp-free", env=env)
    self.assertEqual(result.returncode, 0, result.stderr)
    rows = table_rows(result.stdout)
    self.assertTrue(rows, "缺少完整映射表")
    self.assertEqual(rows[0][0], "ccp-free")
    self.assertEqual(result.stdout.count("▶ 查詢入口"), 1)
    self.assertNotIn("▶ 本次啟動", result.stdout)
    self.assertNotIn("outer-pollution", result.stdout)
    self.assertEqual(dict(rows)["ccp-sol"][1], "gpt-test-sol")

  def test_same_shell_reloads_changed_version_table(self):
    newer = self.fixture / "new.env"
    newer.write_text(VERSIONS.replace("gpt-test-sol", "gpt-new-sol"))
    script = f"ccp-list ccp-sol; cp {shlex.quote(str(newer))} {shlex.quote(str(self.versions))}; ccp-list ccp-sol"
    result = self.run_cli(script=script)
    self.assertEqual(result.returncode, 0, result.stderr)
    sol_rows = [cells for name, cells in table_rows(result.stdout) if name == "ccp-sol"]
    self.assertEqual([cells[1] for cells in sol_rows], ["gpt-test-sol", "gpt-new-sol"])

  def test_pool_order_disabled_filter_and_downstream_model_resolution(self):
    result = self.run_cli()
    self.assertEqual(result.returncode, 0, result.stderr)
    free = next((line for line in result.stdout.splitlines() if line.startswith("free(max):")), None)
    self.assertIsNotNone(free, "缺少 free(max) 候選順序")
    self.assertLess(free.index("router-high"), free.index("cline-low"))
    self.assertIn("deepseek-test-flash", result.stdout)
    self.assertNotIn("MUST-NOT-APPEAR", result.stdout)
    self.assertIn("free-smart(max): smart-owner", result.stdout)
    self.config.write_text(RELAY.replace("priority: 9", "priority: 0"))
    changed = self.run_cli()
    free = next(line for line in changed.stdout.splitlines() if line.startswith("free(max):"))
    self.assertLess(free.index("cline-low"), free.index("router-high"))

  def test_virtual_pool_alias_is_not_presented_as_a_resolved_model(self):
    result = self.run_cli()
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertIn("free-ds（終點未解析）", result.stdout)

  def test_empty_and_tied_pool_priorities_are_not_reported_as_available(self):
    self.config.write_text("""openai-compatibility:
  - name: first-owner
    models: [{name: first-model, alias: free}]
  - name: second-owner
    priority: 0
    models: [{name: second-model, alias: free}]
""")
    result = self.run_cli()
    self.assertEqual(result.returncode, 0, result.stderr)
    free = next((line for line in result.stdout.splitlines() if line.startswith("free(max):")), None)
    self.assertIsNotNone(free, "缺少 free(max) 候選順序")
    self.assertLess(free.index("first-owner"), free.index("second-owner"))
    self.assertIn("free-smart(max): 無 active 候選", result.stdout)
    self.assertNotIn("上游可用", next(line for line in result.stdout.splitlines() if line.startswith("free-smart(max):")))

  def test_missing_versions_are_unknown_instead_of_stale_values(self):
    self.versions.unlink()
    env = self.env | {"GPT_SOL": "gpt-stale-sol", "GPT_ASTRA": "gpt-stale-astra", "GPT_LUNA": "gpt-stale-luna"}
    result = self.run_cli(env=env)
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("未知", result.stdout + result.stderr)
    self.assertNotIn("gpt-stale", result.stdout)
    self.assertIn(str(self.versions), result.stderr)

  def test_malformed_or_wrong_shape_config_reports_unknown_without_secret_echo(self):
    for contents in ("openai-compatibility: [CREDENTIAL-CANARY", "openai-compatibility: null\n", "- wrong-root\n"):
      with self.subTest(contents=contents):
        self.config.write_text(contents)
        result = self.run_cli()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("未知", result.stdout + result.stderr)
        self.assertNotIn("Traceback", result.stderr)
        self.assertNotIn("CREDENTIAL-CANARY", result.stdout + result.stderr)

  def test_unknown_endpoint_is_labelled_unresolved(self):
    self.config.write_text('''openai-compatibility:
  - name: mystery-owner
    base-url: https://unknown.example/v1
    models: [{name: mystery-model, alias: free}]
''')
    result = self.run_cli()
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertIn("mystery-model（終點未解析）", result.stdout)

  def test_missing_models_is_unknown_not_an_empty_pool(self):
    self.config.write_text('''openai-compatibility:
  - name: truncated-owner
    priority: 7
''')
    result = self.run_cli()
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("free(max): 未知", result.stdout)
    self.assertNotIn("free(max): 無 active 候選", result.stdout)

  def test_malformed_model_value_reports_version_source_error(self):
    self.versions.write_text("GPT_ASTRA=gpt-new-astra\nGPT_SOL='unterminated\nGPT_LUNA=gpt-new-luna\n")
    result = self.run_cli()
    self.assertNotEqual(result.returncode, 0)
    self.assertIn(str(self.versions), result.stderr)
    self.assertIn("未知", result.stdout + result.stderr)
    self.assertNotIn("(max) |", result.stdout)

  def test_nonboolean_disabled_flag_is_reported_as_unknown(self):
    self.config.write_text('openai-compatibility:\n  - name: uncertain-owner\n    disabled: "true"\n    models: [{name: candidate-model, alias: free}]\n')
    result = self.run_cli()
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("未知", result.stdout + result.stderr)
    self.assertNotIn("free(max): uncertain-owner", result.stdout)

  def test_query_is_read_only_and_never_prints_credentials(self):
    result = self.run_cli()
    self.assertEqual(result.returncode, 0, result.stderr)
    self.assertEqual(self.config.read_text(), RELAY)
    self.assertEqual(self.versions.read_text(), VERSIONS)
    self.assertNotIn("CREDENTIAL-CANARY", result.stdout + result.stderr)

  def test_old_native_launcher_without_preview_is_never_executed(self):
    legacy = self.fixture / "legacy-split"
    (legacy / "bin").mkdir(parents=True)
    marker = self.fixture / "unexpected-launch"
    (legacy / "bin/cc-split-lib.sh").write_text("# legacy launcher without readonly preview\n")
    for entry in ("cc-luna", "cc-free"):
      (legacy / "bin" / entry).write_text(f"#!/bin/bash\nprintf launched > {shlex.quote(str(marker))}\n")
    result = self.run_cli(env=self.env | {"CCP_SPLIT_ROOT": str(legacy)})
    self.assertNotEqual(result.returncode, 0)
    self.assertFalse(marker.exists(), "舊啟動器不得在表格預覽時真的執行")
    self.assertIn("未知", result.stdout + result.stderr)

  def test_unknown_entry_is_not_labelled_as_a_supported_launch(self):
    result = self.run_cli("ccp-not-a-launcher")
    self.assertNotEqual(result.returncode, 0)
    self.assertIn("不支援", result.stderr)
    self.assertNotIn("▶ 本次啟動", result.stdout)


if __name__ == "__main__":
  unittest.main()
