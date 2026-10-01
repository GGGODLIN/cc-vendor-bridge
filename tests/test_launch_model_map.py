import errno
import fcntl
import json
import os
from pathlib import Path
import pty
import shlex
import struct
import subprocess
import termios
import unittest

import test_model_map
from test_model_map import ENTRIES, ROOT, SOURCE, VERSIONS, table_rows


class LaunchModelMapTest(unittest.TestCase):
  def setUp(self):
    test_model_map.ModelMapTest.setUp(self)
    self.home = self.fixture / "home"
    auth = self.home / ".cli-proxy-api"
    auth.mkdir(parents=True)
    (auth / "keys.env").write_text("CLIPROXY_BASE_URL=http://127.0.0.1:8317\nCLIPROXY_KEY_CC=AUTH-CREDENTIAL-CANARY\nCLIPROXY_MGMT_KEY=MGMT-CREDENTIAL-CANARY\n")
    (auth / "antigravity-test.json").write_text('{"email":"fixture@example.test","disabled":false,"expired":"fixture"}')
    (auth / "codex-test.json").write_text('{"email":"fixture@example.test","priority":1}')
    (auth / "xai-test.json").write_text('{"email":"fixture@example.test","disabled":false}')
    self.records = self.fixture / "cc-records.jsonl"
    binary = self.fixture / "bin"
    binary.mkdir()
    fake_cc = binary / "claude"
    fake_cc.write_text("""#!/usr/bin/env python3
import json,os,sys
keys=['ANTHROPIC_MODEL','ANTHROPIC_DEFAULT_FABLE_MODEL','ANTHROPIC_DEFAULT_OPUS_MODEL','ANTHROPIC_DEFAULT_SONNET_MODEL','ANTHROPIC_DEFAULT_HAIKU_MODEL','CLAUDE_CODE_SUBAGENT_MODEL']
record={'slots':[os.environ.get(k,'') for k in keys],'argv':sys.argv[1:],'fast':'X-CCP-Fast: 1' in os.environ.get('ANTHROPIC_CUSTOM_HEADERS',''),'headers':os.environ.get('ANTHROPIC_CUSTOM_HEADERS','')}
with open(os.environ['CC_RECORDS'],'a') as f:f.write(json.dumps(record)+'\\n')
print('CC-STDOUT-UNCHANGED')
""")
    fake_cc.chmod(0o700)
    fake_curl = binary / "curl"
    fake_curl.write_text("""#!/usr/bin/env python3
import json,sys
if any('__cc_split_health' in a for a in sys.argv):print('cc-split-proxy')
else:print(json.dumps({'files':[{'provider':'codex','email':'fixture@example.test','priority':1,'id_token':{'plan_type':'fixture'},'recent_requests':[{'success':1,'failed':0}]}],'data':[]}))
""")
    fake_curl.chmod(0o700)
    self.stubs = self.fixture / "external-stubs.sh"
    self.stubs.write_text(f"""function /usr/bin/nc {{ return 0; }}
function curl {{ {shlex.quote(str(fake_curl))} "$@"; }}
function /usr/bin/curl {{ {shlex.quote(str(fake_curl))} "$@"; }}
function launchctl {{ printf 'UNEXPECTED-SERVICE-START\\n' >&2; return 42; }}
""")
    accounts = self.fixture / "accounts.json"
    requests = self.fixture / "requests.json"
    accounts.write_text('{"accounts":[]}')
    requests.write_text('[]')
    self.env.update({
      "HOME": str(self.home),
      "PATH": str(binary) + os.pathsep + self.env["PATH"],
      "BASH_ENV": str(self.stubs),
      "CC_CLAUDE_BIN": str(fake_cc),
      "CC_SPLIT_CLAUDE_BIN": str(fake_cc),
      "CCP_FREE_CLAUDE_BIN": str(fake_cc),
      "CC_RECORDS": str(self.records),
      "CCP_FREE_KEYS_FILE": str(auth / "keys.env"),
      "CCP_FREE_ACCOUNTS_FILE": str(accounts),
      "CCP_FREE_REQUEST_LOG_FILE": str(requests),
      "CCP_FREE_NC_BIN": "/usr/bin/nc",
      "CCP_FREE_CURL_BIN": "/usr/bin/curl",
      "DEEPSEEK_API_KEY": "DS-CREDENTIAL-CANARY",
      "BRUCE_API_KEY": "BRUCE-CREDENTIAL-CANARY",
      "ZAI_API_KEY": "ZAI-CREDENTIAL-CANARY",
    })

  def command(self, entry, args=(), script=None):
    prefix = f"source {shlex.quote(str(self.stubs))}; source {shlex.quote(str(SOURCE))}; "
    if script:
      return ["zsh", "-f", "-c", prefix + script]
    if entry.startswith("ccp-"):
      return ["zsh", "-f", "-c", prefix + entry + " " + " ".join(shlex.quote(arg) for arg in args)]
    return ["bash", str(ROOT.parent / "cc-split-proxy/bin" / entry), *args]

  def launch(self, entry, args=(), *, terminal=True, env=None, script=None):
    command = self.command(entry, args, script)
    if not terminal:
      result = subprocess.run(command, stdin=subprocess.DEVNULL, capture_output=True, text=True, env=env or self.env, timeout=30)
      return result.returncode, result.stdout, result.stderr
    master, slave = pty.openpty()
    fcntl.ioctl(slave, termios.TIOCSWINSZ, struct.pack("HHHH", 30, 360, 0, 0))
    process = subprocess.Popen(command, stdin=slave, stdout=slave, stderr=slave, env=env or self.env)
    os.close(slave)
    chunks = []
    try:
      while True:
        try:
          data = os.read(master, 65536)
        except OSError as error:
          if error.errno == errno.EIO:
            break
          raise
        if not data:
          break
        chunks.append(data)
    finally:
      os.close(master)
    status = process.wait(timeout=30)
    return status, b"".join(chunks).decode().replace("\r\n", "\n"), ""

  def read_records(self):
    return [json.loads(line) for line in self.records.read_text().splitlines()]

  def test_each_interactive_entry_shows_full_table_once_with_current_entry_first(self):
    for entry in ENTRIES:
      with self.subTest(entry=entry):
        self.records.unlink(missing_ok=True)
        status, output, _ = self.launch(entry)
        self.assertEqual(status, 0, output)
        rows = table_rows(output)
        self.assertTrue(rows, "互動啟動沒有顯示完整映射表")
        self.assertEqual(rows[0][0], entry)
        self.assertEqual(len(rows), len(ENTRIES))
        self.assertEqual(output.count("▶ 本次啟動"), 1)
        self.assertNotIn("▶ 查詢入口", output)
        self.assertEqual(len(self.read_records()), 1, "顯示全表不得額外啟動 CC")
        self.assertIn("CC-STDOUT-UNCHANGED", output)
        self.assertNotIn("CREDENTIAL-CANARY", output)
        self.assertNotIn("UNEXPECTED-SERVICE-START", output)

  def test_explicit_model_and_environment_overrides_only_affect_active_row(self):
    env = self.env | {"ANTHROPIC_MODEL": "env-model", "ANTHROPIC_DEFAULT_FABLE_MODEL": "env-fable", "ANTHROPIC_DEFAULT_OPUS_MODEL": "env-opus"}
    status, output, _ = self.launch("ccp-gpt", ["--model", "flag-model", "--resume", "fixture-session"], env=env)
    self.assertEqual(status, 0, output)
    rows = dict(table_rows(output))
    self.assertIn("ccp-gpt", rows, "缺少本次啟動列")
    self.assertEqual(rows["ccp-gpt"][1:4], ["flag-model", "env-fable", "env-opus"])
    self.assertEqual(rows["ccp-sol"][1], "gpt-test-sol")
    record = self.read_records()[0]
    self.assertEqual(record["slots"][:3], ["env-model", "env-fable", "env-opus"])
    self.assertEqual(record["argv"][-4:], ["--model", "flag-model", "--resume", "fixture-session"])

  def test_model_alias_resolves_through_the_active_slots(self):
    status, output, _ = self.launch("ccp-sol", ["--model", "sonnet"])
    self.assertEqual(status, 0, output)
    rows = dict(table_rows(output))
    self.assertIn("ccp-sol", rows, "缺少本次啟動列")
    self.assertEqual(rows["ccp-sol"][1], "gpt-test-luna(max)")
    record = self.read_records()[0]
    self.assertEqual(record["slots"][3], "gpt-test-luna(max)")
    self.assertEqual(record["argv"][-2:], ["--model", "sonnet"])

  def test_print_machine_output_and_service_modes_do_not_insert_a_table(self):
    for args in (["-p", "fixture"], ["--print", "fixture"], ["--output-format", "json"], ["mcp", "list"]):
      with self.subTest(args=args):
        status, output, _ = self.launch("ccp-sol", args)
        self.assertEqual(status, 0, output)
        self.assertNotIn("CC 模型映射", output)
        self.assertNotIn("▶ 本次啟動", output)
        self.assertIn("CC-STDOUT-UNCHANGED", output)

  def test_noninteractive_stdout_is_unchanged(self):
    status, output, errors = self.launch("ccp-sol", terminal=False)
    self.assertEqual(status, 0, errors)
    self.assertEqual(output, "CC-STDOUT-UNCHANGED\n")
    self.assertNotIn("CC 模型映射", errors)

  def test_same_shell_launch_reloads_models_for_table_and_cc_together(self):
    newer = self.fixture / "new.env"
    newer.write_text(VERSIONS.replace("gpt-test-sol", "gpt-new-sol").replace("gpt-test-luna", "gpt-new-luna"))
    script = f"ccp-sol; cp {shlex.quote(str(newer))} {shlex.quote(str(self.versions))}; ccp-sol"
    status, output, _ = self.launch("ccp-sol", script=script)
    self.assertEqual(status, 0, output)
    rows = [cells for name, cells in table_rows(output) if name == "ccp-sol"]
    self.assertEqual([row[1] for row in rows], ["gpt-test-sol", "gpt-new-sol"])
    self.assertEqual([row["slots"][0] for row in self.read_records()], ["gpt-test-sol", "gpt-new-sol"])
    self.assertEqual(self.read_records()[1]["slots"][3], "gpt-new-luna(max)")

  def test_partial_version_update_keeps_existing_launch_atomic_and_marks_unknown(self):
    partial = self.fixture / "partial.env"
    partial.write_text("GPT_ASTRA=gpt-new-astra\nGPT_LUNA=gpt-new-luna\n")
    script = f"ccp-sol; cp {shlex.quote(str(partial))} {shlex.quote(str(self.versions))}; ccp-sol"
    status, output, _ = self.launch("ccp-sol", script=script)
    self.assertEqual(status, 0, output)
    records = self.read_records()
    self.assertEqual(records[1]["slots"][0], "gpt-test-sol")
    self.assertEqual(records[1]["slots"][3], "gpt-test-luna(max)")
    rows = [cells for name, cells in table_rows(output) if name == "ccp-sol"]
    self.assertEqual(rows[-1][1], "未知")
    self.assertIn("版本表", output)

  def test_render_failure_does_not_block_cc_or_modify_stdout(self):
    env = self.env | {"CCP_MODEL_MAP_BIN": str(self.fixture / "missing-renderer")}
    status, output, _ = self.launch("ccp-sol", env=env)
    self.assertEqual(status, 0, output)
    self.assertEqual(len(self.read_records()), 1)
    self.assertIn("CC-STDOUT-UNCHANGED", output)
    self.assertIn("映射表", output)
    self.assertNotIn("CREDENTIAL-CANARY", output)

  def test_fast_routing_and_direct_entries_keep_existing_behaviour(self):
    status, output, _ = self.launch("ccp-gpt-fast", ["--resume", "fixture-session"])
    self.assertEqual(status, 0, output)
    record = self.read_records()[0]
    self.assertTrue(record["fast"])
    self.assertEqual(record["slots"][:3], ["gpt-test-astra", "gpt-test-astra", "gpt-test-sol"])
    self.assertEqual(record["argv"][-2:], ["--resume", "fixture-session"])
    self.assertNotIn("--fast", record["argv"])
    status, output, _ = self.launch("ccp-glm")
    self.assertEqual(status, 0, output)
    self.assertNotIn("CC 模型映射", output)

  def test_fast_flag_is_consumed_and_adds_priority_header(self):
    for entry, flag, main in (("ccp-sol", "--fast", "gpt-test-sol"), ("ccp-gpt", "-fast", "gpt-test-astra")):
      with self.subTest(entry=entry, flag=flag):
        self.records.unlink(missing_ok=True)
        env = self.env | {"ANTHROPIC_CUSTOM_HEADERS": "X-Existing: yes"}
        status, output, _ = self.launch(entry, [flag, "--resume", "fixture-session"], env=env)
        self.assertEqual(status, 0, output)
        record = self.read_records()[0]
        self.assertEqual(record["headers"], "X-Existing: yes\nX-CCP-Fast: 1")
        self.assertEqual(record["slots"][:3], [main, main, "gpt-test-sol"])
        self.assertEqual(record["argv"][-2:], ["--resume", "fixture-session"])
        self.assertNotIn(flag, record["argv"])

  def test_opus_maps_to_sol_without_fast_by_default(self):
    for entry in ("ccp-gpt", "ccp-sol"):
      with self.subTest(entry=entry):
        self.records.unlink(missing_ok=True)
        status, output, _ = self.launch(entry)
        self.assertEqual(status, 0, output)
        record = self.read_records()[0]
        self.assertFalse(record["fast"])
        self.assertEqual(record["slots"][2:5], ["gpt-test-sol", "gpt-test-luna(max)", "gpt-test-luna(max)"])

  def test_narrow_terminal_preserves_complete_launcher_names(self):
    env = self.env | {"COLUMNS": "80"}
    status, output, _ = self.launch("ccp-sol", env=env)
    self.assertEqual(status, 0, output)
    self.assertIn("CC 模型映射", output)
    for entry in ENTRIES:
      self.assertIn(entry, output)


if __name__ == "__main__":
  unittest.main()
