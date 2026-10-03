import json
import os
from pathlib import Path
import re
import shlex
import subprocess
import unittest

import test_launch_model_map as launch_fixture
from test_model_map import ENTRIES, ROOT, SOURCE


NATIVE = ("cc", "ccopus", "ccfable", "claude", "ccp")


class FastLaunchersTest(unittest.TestCase):
  def setUp(self):
    launch_fixture.LaunchModelMapTest.setUp(self)
    self.env.update({"MIMO_SUB_API_KEY": "MIMO-SUB-CANARY", "MIMO_API_KEY": "MIMO-CANARY", "LOCAL_MODEL": "fixture-local"})

  launch = launch_fixture.LaunchModelMapTest.launch
  read_records = launch_fixture.LaunchModelMapTest.read_records

  def command(self, entry, args=(), script=None):
    if entry not in NATIVE:
      return launch_fixture.LaunchModelMapTest.command(self, entry, args, script)
    native = Path(os.environ.get("CC_NATIVE_ZSHRC", str(Path.home() / ".zshrc"))).read_text()
    names = ("_cc_launch", "_cc_dir", "_cc_sync_mcp", "_cc_selected_dir", "_cc_exec", "_cc_native", *NATIVE)
    definitions = []
    for name in names:
      match = re.search(r"^" + re.escape(name) + r"\(\) \{\n.*?^\}", native, re.M | re.S)
      if match:
        definitions.append(match.group())
    fake_traced = self.fixture / "bin/cc-traced"
    fake_traced.write_bytes((self.fixture / "bin/claude").read_bytes())
    fake_traced.chmod(0o700)
    prefix = f"source {shlex.quote(str(self.stubs))}; source {shlex.quote(str(SOURCE))}; "
    prefix += '\n'.join(definitions) + '\n_CC_ACCOUNT_FILE="$HOME/.config/cc-account"\n'
    call = script or entry + " " + " ".join(shlex.quote(arg) for arg in args)
    return ["zsh", "-f", "-c", prefix + call]

  def record(self, entry, args=(), env=None, script=None):
    self.records.unlink(missing_ok=True)
    status, output, errors = self.launch(entry, args, terminal=False, env=env, script=script)
    self.assertEqual(status, 0, output + errors)
    self.assertNotIn("UNEXPECTED-SERVICE-START", errors)
    records = self.read_records()
    self.assertEqual(len(records), 1)
    return records[0]

  def test_fast_flag_across_launchers_preserves_slots_effort_and_remaining_arguments(self):
    for entry in (*ENTRIES, *NATIVE, "ccp-glm", "ccp-mimo", "ccp-mimo-payg", "ccp-local"):
      with self.subTest(entry=entry):
        env = self.env | {"ANTHROPIC_CUSTOM_HEADERS": "X-Existing: yes"}
        args = ["--resume", "fixture-session"]
        standard = self.record(entry, args, env)
        fast = self.record(entry, ["-fast", *args], env)
        self.assertEqual(fast["headers"], "X-Existing: yes\nX-CCP-Fast: 1")
        self.assertEqual(fast["slots"], standard["slots"])
        self.assertEqual(fast["argv"], standard["argv"])

  def test_double_dash_fast_is_consumed_by_split_and_native_launchers(self):
    for entry in ("cc-luna", "cc-free", "ccopus", "ccp-mix-sol"):
      with self.subTest(entry=entry):
        record = self.record(entry, ["--fast", "-p", "fixture"])
        self.assertTrue(record["fast"])
        self.assertEqual(record["argv"][-2:], ["-p", "fixture"])
        self.assertNotIn("--fast", record["argv"])

  def test_fast_does_not_duplicate_existing_header(self):
    headers = "X-Existing: yes\nX-CCP-Fast: 1"
    for entry in ("ccp-gpt", "cc-luna", "ccopus"):
      with self.subTest(entry=entry):
        record = self.record(entry, ["-fast"], self.env | {"ANTHROPIC_CUSTOM_HEADERS": headers})
        self.assertEqual(record["headers"], headers)

  def test_nonleading_flag_text_and_empty_arguments_are_unchanged(self):
    for entry in ("ccp-mix-gpt", "cc-luna", "ccopus"):
      with self.subTest(entry=entry):
        args = ["-p", "-fast", ""]
        record = self.record(entry, args)
        self.assertFalse(record["fast"])
        self.assertEqual(record["argv"][-3:], args)

  def test_fast_header_does_not_leak_to_the_next_launch_in_the_same_shell(self):
    for entry in ("ccp-mix-gpt", "ccopus"):
      with self.subTest(entry=entry):
        self.records.unlink(missing_ok=True)
        status, output, errors = self.launch(entry, terminal=False, script=f"{entry} -fast; {entry}")
        self.assertEqual(status, 0, output + errors)
        first, second = self.read_records()
        self.assertTrue(first["fast"])
        self.assertFalse(second["fast"])

  def test_native_account_flag_still_follows_leading_fast(self):
    record = self.record("ccopus", ["-fast", "-team-p", "--resume", "fixture-session"])
    self.assertTrue(record["fast"])
    self.assertNotIn("-team-p", record["argv"])
    self.assertEqual(record["argv"][-2:], ["--resume", "fixture-session"])
    nonleading = self.record("cc", ["-team-p", "-fast", "-p", "fixture"])
    self.assertFalse(nonleading["fast"])
    self.assertEqual(nonleading["argv"], ["-fast", "-p", "fixture"])

  def test_cc_pick_fast_last_preserves_saved_recipe(self):
    recipe = {"main": "claude-opus-5-5", "fable": "gpt-test-sol", "opus": "gpt-test-astra", "sonnet": "gpt-test-luna(max)", "subagent": ""}
    state = self.fixture / "recipes.json"
    state.write_text(json.dumps([{"recipe": recipe, "at": "fixture"}]))
    external = self.fixture / "python-boundary"
    external.mkdir()
    (external / "sitecustomize.py").write_text('''import io,json,urllib.request
original = urllib.request.urlopen
def urlopen(request, *args, **kwargs):
  url = request.full_url if hasattr(request, "full_url") else request
  if url == "http://127.0.0.1:8317/v1/models":
    return io.BytesIO(json.dumps({"data": [{"id": name} for name in ("gpt-test-sol", "gpt-test-astra", "gpt-test-luna")]}).encode())
  return original(request, *args, **kwargs)
urllib.request.urlopen = urlopen
''')
    env = self.env | {"CC_PICK_STATE": str(state), "PYTHONPATH": str(external)}
    standard = self.record("cc-pick", ["--last", "--resume", "fixture-session"], env)
    for flag in ("-fast", "--fast"):
      with self.subTest(flag=flag):
        fast = self.record("cc-pick", [flag, "--last", "--resume", "fixture-session"], env)
        self.assertTrue(fast["fast"])
        self.assertEqual(fast["slots"], standard["slots"])
        self.assertEqual(fast["argv"], standard["argv"])
        self.assertNotIn("--last", fast["argv"])
        self.assertEqual(json.loads(state.read_text())[0]["recipe"], recipe)
    nonleading = self.record("cc-pick", ["--last", "-fast", "-p", "fixture"], env)
    self.assertFalse(nonleading["fast"])
    self.assertEqual(nonleading["argv"], ["-fast", "-p", "fixture"])


if __name__ == "__main__":
  unittest.main()
