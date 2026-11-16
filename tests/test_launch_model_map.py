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
record['limits']=[os.environ.get(k,'') for k in ('CLAUDE_CODE_MAX_OUTPUT_TOKENS','CLAUDE_CODE_MAX_CONTEXT_TOKENS')]
record['base_url']=os.environ.get('ANTHROPIC_BASE_URL','')
record['split_auth']='ANTHROPIC_AUTH_TOKEN' not in os.environ and 'ANTHROPIC_API_KEY' not in os.environ
record['relay_auth']=os.environ.get('ANTHROPIC_AUTH_TOKEN')=='AUTH-CREDENTIAL-CANARY' and 'ANTHROPIC_API_KEY' not in os.environ
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
function launchctl {{ printf 'attempted\\n' >> {shlex.quote(str(self.fixture / 'service-starts'))}; printf 'UNEXPECTED-SERVICE-START\\n' >&2; return 42; }}
function /usr/bin/launchctl {{ launchctl "$@"; }}
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

  def test_ds_free_launch_pins_models_limits_auth_and_preserves_fast_arguments(self):
    slots = ("ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_FABLE_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL",
             "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL")
    env = self.env | dict.fromkeys(slots, "gpt-outer(max)") | {
      "ANTHROPIC_API_KEY": "OUTER-CREDENTIAL-CANARY",
      "ANTHROPIC_AUTH_TOKEN": "OUTER-AUTH-CANARY",
      "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "128000",
      "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "900000",
      "ANTHROPIC_CUSTOM_HEADERS": "X-Existing: yes",
    }
    args = ["--resume", "session with spaces", "-p", "-fast", ""]
    for flag in ("-fast", "--fast"):
      with self.subTest(flag=flag):
        self.records.unlink(missing_ok=True)
        status, output, errors = self.launch("ccp-ds-free", [flag, *args], terminal=False, env=env | {"CCP_CLAUDE_OAUTH_PRESENT": "1"})
        self.assertEqual(status, 0, output + errors)
        record, = self.read_records()
        self.assertEqual(record["slots"], ["group/ds-free:max"] * 6)
        self.assertEqual(record["limits"], ["32000", "1000000"])
        self.assertEqual(record["base_url"], "http://127.0.0.1:8318")
        self.assertTrue(record["split_auth"])
        self.assertEqual(record["headers"], "X-Existing: yes\nX-CCP-Fast: 1")
        self.assertEqual(record["argv"], ["--model", "group/ds-free:max", "--disallowed-tools", "WebSearch", *args])
        self.assertNotIn("CREDENTIAL-CANARY", output + errors)
        self.assertNotIn("UNEXPECTED-SERVICE-START", output + errors)
        self.assertFalse((self.fixture / "service-starts").exists())
    self.records.unlink(missing_ok=True)
    status, output, errors = self.launch("ccp-ds-free", args, terminal=False, env=env)
    self.assertEqual(status, 0, output + errors)
    record, = self.read_records()
    self.assertEqual(record["base_url"], "http://127.0.0.1:8318")
    self.assertTrue(record["relay_auth"])

  def test_gemini_launchers_pin_output_cap_to_the_flash_or_pro_ceiling(self):
    # Flash (Hydrogen) answers up to 65536 per reply, Pro/Argon stop at 32768; the mixed
    # launcher takes Flash's cap so its subagents are not cut at 32768.
    expected = {
      "ccp-gemini": (["group/gemini-pro:high"] * 3 + ["group/gemini-flash:high"] * 3, "65536"),
      "ccp-gemini-flash": (["group/gemini-flash:high"] * 6, "65536"),
      "ccp-gemini-pro": (["group/gemini-pro:high"] * 3 + ["group/gemini-pro:medium"] * 3, "32768"),
      "ccp-gemini-argon": (["google/gemini-4-argon:high"] * 6, "32768"),
    }
    for entry, (slots, cap) in expected.items():
      with self.subTest(entry=entry):
        self.records.unlink(missing_ok=True)
        status, output, errors = self.launch(entry, ["-p", "x"], terminal=False, env=self.env | {"CCP_CLAUDE_OAUTH_PRESENT": "1"})
        self.assertEqual(status, 0, output + errors)
        record, = self.read_records()
        self.assertEqual(record["slots"], slots)
        self.assertEqual(record["limits"], [cap, "1048576"])

  def test_un_launch_pins_models_limits_auth_and_preserves_arguments(self):
    slots = ("ANTHROPIC_MODEL", "ANTHROPIC_DEFAULT_FABLE_MODEL", "ANTHROPIC_DEFAULT_OPUS_MODEL",
             "ANTHROPIC_DEFAULT_SONNET_MODEL", "ANTHROPIC_DEFAULT_HAIKU_MODEL", "CLAUDE_CODE_SUBAGENT_MODEL")
    env = self.env | dict.fromkeys(slots, "gpt-outer(max)") | {
      "ANTHROPIC_API_KEY": "OUTER-CREDENTIAL-CANARY",
      "ANTHROPIC_AUTH_TOKEN": "OUTER-AUTH-CANARY",
      "CLAUDE_CODE_MAX_OUTPUT_TOKENS": "128000",
      "CLAUDE_CODE_MAX_CONTEXT_TOKENS": "900000",
    }
    args = ["--resume", "session with spaces", "-p", ""]
    status, output, errors = self.launch("ccp-un", args, terminal=False, env=env | {"CCP_CLAUDE_OAUTH_PRESENT": "1"})
    self.assertEqual(status, 0, output + errors)
    record, = self.read_records()
    self.assertEqual(record["slots"], ["group/un:high"] * 6)
    self.assertEqual(record["limits"], ["32000", "480000"])
    self.assertEqual(record["base_url"], "http://127.0.0.1:8318")
    self.assertTrue(record["split_auth"])
    self.assertEqual(record["argv"], ["--model", "group/un:high", "--disallowed-tools", "WebSearch", *args])
    self.assertNotIn("CREDENTIAL-CANARY", output + errors)
    self.assertNotIn("UNEXPECTED-SERVICE-START", output + errors)
    self.assertFalse((self.fixture / "service-starts").exists())

  def test_un_missing_relay_aborts_without_starting_any_service_or_claude(self):
    with self.stubs.open("a") as source:
      source.write("function /usr/bin/nc { return 1; }\n")
    status, output, errors = self.launch("ccp-un", terminal=False)
    self.assertEqual(status, 1, output + errors)
    self.assertIn("relay :8317 not listening", errors)
    self.assertFalse(self.records.exists())

  def test_ds_free_missing_relay_aborts_without_starting_any_service_or_claude(self):
    with self.stubs.open("a") as source:
      source.write("function /usr/bin/nc { return 1; }\n")
    status, output, errors = self.launch("ccp-ds-free", terminal=False)
    self.assertEqual(status, 1, output + errors)
    self.assertIn("relay :8317 not listening", errors)
    self.assertNotIn("UNEXPECTED-SERVICE-START", output + errors)
    self.assertFalse((self.fixture / "service-starts").exists())
    self.assertFalse(self.records.exists())

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
    self.assertEqual(rows["ccp-sol"][1], "gpt-test-terra(max)")
    record = self.read_records()[0]
    self.assertEqual(record["slots"][3], "gpt-test-terra(max)")
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
    newer.write_text(VERSIONS.replace("gpt-test-sol", "gpt-new-sol").replace("gpt-test-terra", "gpt-new-terra"))
    script = f"ccp-sol; cp {shlex.quote(str(newer))} {shlex.quote(str(self.versions))}; ccp-sol"
    status, output, _ = self.launch("ccp-sol", script=script)
    self.assertEqual(status, 0, output)
    rows = [cells for name, cells in table_rows(output) if name == "ccp-sol"]
    self.assertEqual([row[1] for row in rows], ["gpt-test-sol", "gpt-new-sol"])
    self.assertEqual([row["slots"][0] for row in self.read_records()], ["gpt-test-sol", "gpt-new-sol"])
    self.assertEqual(self.read_records()[1]["slots"][3], "gpt-new-terra(max)")

  def test_partial_version_update_keeps_existing_launch_atomic_and_marks_unknown(self):
    partial = self.fixture / "partial.env"
    partial.write_text("GPT_ASTRA=gpt-new-astra\nGPT_LUNA=gpt-new-luna\n")
    script = f"ccp-sol; cp {shlex.quote(str(partial))} {shlex.quote(str(self.versions))}; ccp-sol"
    status, output, _ = self.launch("ccp-sol", script=script)
    self.assertEqual(status, 0, output)
    records = self.read_records()
    self.assertEqual(records[1]["slots"][0], "gpt-test-sol")
    self.assertEqual(records[1]["slots"][3], "gpt-test-terra(max)")
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

  def test_gpt_main_entries_turn_idle_compaction_off_and_others_leave_it(self):
    flag = "idleCompaction"
    for entry, expected in (("ccp-gpt", True), ("ccp-sol", True), ("ccp-gpt-smart", True), ("ccp-bruce", True),
                            ("ccp-grok", False), ("ccp-glm", False)):
      with self.subTest(entry=entry):
        self.records.unlink(missing_ok=True)
        status, output, _ = self.launch(entry, terminal=False)
        self.assertEqual(status, 0, output)
        argv = self.read_records()[0]["argv"]
        settings = [json.loads(argv[i + 1]) for i, arg in enumerate(argv[:-1]) if arg == "--settings"]
        self.assertEqual(any(item.get(flag) is False for item in settings), expected, argv)

  def test_smart_defaults_to_xhigh_ultracode_without_leaking_to_plain_gpt(self):
    for terminal, args in ((False, []), (True, []), (False, ["--fast", "--resume", "fixture-session"])):
      with self.subTest(terminal=terminal, args=args):
        self.records.unlink(missing_ok=True)
        script = "ccp-gpt-smart " + " ".join(shlex.quote(arg) for arg in args) + "; ccp-gpt"
        status, output, _ = self.launch("ccp-gpt-smart", terminal=terminal, script=script)
        self.assertEqual(status, 0, output)
        smart, plain = self.read_records()
        for record, effort, expected_settings in (
          (smart, "xhigh", {"idleCompaction": False, "ultracode": True}),
          (plain, "medium", {"idleCompaction": False}),
        ):
          argv = record["argv"]
          self.assertEqual(argv.count("--effort"), 1)
          self.assertEqual(argv[argv.index("--effort") + 1], effort)
          self.assertEqual(argv.count("--settings"), 1)
          self.assertEqual(json.loads(argv[argv.index("--settings") + 1]), expected_settings)
        self.assertEqual(smart["fast"], "--fast" in args)
        self.assertFalse(plain["fast"])
        if args:
          self.assertEqual(smart["argv"][-2:], ["--resume", "fixture-session"])
          self.assertNotIn("--fast", smart["argv"])

  def test_opus_maps_to_sol_without_fast_by_default(self):
    for entry, fleet in (("ccp-gpt", "gpt-test-luna(max)"), ("ccp-sol", "gpt-test-terra(max)")):
      with self.subTest(entry=entry):
        self.records.unlink(missing_ok=True)
        status, output, _ = self.launch(entry)
        self.assertEqual(status, 0, output)
        record = self.read_records()[0]
        self.assertFalse(record["fast"])
        self.assertEqual(record["slots"][2:5], ["gpt-test-sol", fleet, fleet])

  def test_narrow_terminal_preserves_complete_launcher_names(self):
    env = self.env | {"COLUMNS": "80"}
    status, output, _ = self.launch("ccp-sol", env=env)
    self.assertEqual(status, 0, output)
    self.assertIn("CC 模型映射", output)
    for entry in ENTRIES:
      self.assertIn(entry, output)

  def test_ccp_gemini_interactive_defaults_to_ultracode_with_opt_outs(self):
    def settings_arg(argv):
      for i in range(len(argv) - 1):
        if argv[i] == "--settings":
          return json.loads(argv[i + 1])
      return None

    def system_prompt_arg(argv):
      for i in range(len(argv) - 1):
        if argv[i] == "--append-system-prompt":
          return argv[i + 1]
      return None

    # Interactive PTY enables ultracode + Flash orchestration prompt + compact reminder hook on ccp-gemini only.
    for entry, expected in (("ccp-gemini", True), ("ccp-gemini-pro", False), ("ccp-gemini-flash", False), ("ccp-gemini-argon", False)):
      with self.subTest(entry=entry):
        self.records.unlink(missing_ok=True)
        status, output, _ = self.launch(entry)
        self.assertEqual(status, 0, output)
        argv = self.read_records()[0]["argv"]
        cfg = settings_arg(argv)
        prompt = system_prompt_arg(argv)
        if expected:
          self.assertIsNotNone(cfg, entry)
          self.assertIs(cfg.get("ultracode"), True)
          hooks = cfg.get("hooks", {}).get("SessionStart", [])
          self.assertEqual(len(hooks), 1)
          self.assertEqual(hooks[0].get("matcher"), "compact")
          self.assertIn("ccp-gemini-ultracode-compact-remind", hooks[0]["hooks"][0]["command"])
          self.assertIsNotNone(prompt, entry)
          self.assertIn("model: 'sonnet'", prompt)
          self.assertIn("routed-judge", prompt)
          self.assertIn("禁止在回報或檔案中印出任何金鑰", prompt)
        else:
          self.assertIsNone(cfg, entry)
          self.assertIsNone(prompt, entry)

    # Recovery granular opt-outs keep ultracode while stripping compact hook or Flash prompt.
    self.records.unlink(missing_ok=True)
    status, output, _ = self.launch("ccp-gemini", env=self.env | {"CCP_GEMINI_COMPACT_REMIND": "0"})
    self.assertEqual(status, 0, output)
    argv = self.read_records()[0]["argv"]
    self.assertEqual(settings_arg(argv), {"ultracode": True})
    self.assertIsNotNone(system_prompt_arg(argv))

    self.records.unlink(missing_ok=True)
    status, output, _ = self.launch("ccp-gemini", env=self.env | {"CCP_GEMINI_FLASH_PROMPT": "0"})
    self.assertEqual(status, 0, output)
    argv = self.read_records()[0]["argv"]
    self.assertEqual(settings_arg(argv), {"ultracode": True})
    self.assertIsNone(system_prompt_arg(argv))

    # Non-TTY, -p/--print, subcommands, --no-ultracode (with -fast in either order), and CCP_GEMINI_ULTRACODE=0 all omit ultracode and prompt.
    cases = (
      ("non_tty", [], False, {}),
      ("print_short", ["-p", "--no-ultracode"], True, {}),
      ("print_long", ["--print", "hello"], True, {}),
      ("subcommand_mcp", ["mcp", "list"], True, {}),
      ("flag_opt_out_before_fast", ["--no-ultracode", "-fast", "--resume", "s1"], True, {}),
      ("flag_opt_out_after_fast", ["-fast", "--no-ultracode", "--resume", "s1"], True, {}),
      ("env_opt_out", ["--resume", "s1"], True, {"CCP_GEMINI_ULTRACODE": "0"}),
    )
    for name, args, term, extra_env in cases:
      with self.subTest(case=name):
        self.records.unlink(missing_ok=True)
        status, output, errors = self.launch("ccp-gemini", args, terminal=term, env=self.env | extra_env)
        self.assertEqual(status, 0, output + errors)
        rec = self.read_records()[0]
        self.assertIsNone(settings_arg(rec["argv"]), name)
        self.assertIsNone(system_prompt_arg(rec["argv"]), name)
        if name == "print_short":
          self.assertEqual(rec["argv"][-2:], ["-p", "--no-ultracode"])
        else:
          self.assertNotIn("--no-ultracode", rec["argv"])
        if "fast" in name:
          self.assertTrue(rec["fast"])
          self.assertEqual(rec["argv"][-2:], ["--resume", "s1"])

  def test_ccp_gemini_compact_remind_hook_contract(self):
    self.records.unlink(missing_ok=True)
    status, output, _ = self.launch("ccp-gemini")
    self.assertEqual(status, 0, output)
    argv = self.read_records()[0]["argv"]
    cfg = json.loads(argv[argv.index("--settings") + 1])
    hook_cmd = cfg["hooks"]["SessionStart"][0]["hooks"][0]["command"]
    hook_script = ROOT / "bin" / "ccp-gemini-ultracode-compact-remind"

    def run_hook(stdin_text, extra_env=None):
      before = sorted(p.relative_to(self.fixture) for p in self.fixture.rglob("*"))
      res = subprocess.run(
        ["/bin/sh", "-c", hook_cmd],
        input=stdin_text,
        text=True,
        capture_output=True,
        env=self.env | (extra_env or {}),
        cwd=str(self.fixture),
        timeout=10,
      )
      after = sorted(p.relative_to(self.fixture) for p in self.fixture.rglob("*"))
      self.assertEqual(before, after, "提示型 hook 不得寫入任何檔案")
      return res

    # 1. known-good: SessionStart + source=compact on main session emits additionalContext.
    good = run_hook(json.dumps({"hook_event_name": "SessionStart", "source": "compact", "session_id": "s-compact"}))
    self.assertEqual(good.returncode, 0, good.stderr)
    parsed = json.loads(good.stdout)
    self.assertEqual(parsed["hookSpecificOutput"]["hookEventName"], "SessionStart")
    ctx = parsed["hookSpecificOutput"]["additionalContext"]
    self.assertIn("model: 'sonnet'", ctx)
    self.assertIn("routed-judge", ctx)
    self.assertIn("禁止在回報或檔案中印出任何金鑰", ctx)

    # 2. known-bad: startup/resume/clear, wrong event, or subagent agent_type all stay silent.
    for label, payload in (
      ("startup", {"hook_event_name": "SessionStart", "source": "startup"}),
      ("resume", {"hook_event_name": "SessionStart", "source": "resume"}),
      ("clear", {"hook_event_name": "SessionStart", "source": "clear"}),
      ("wrong_event", {"hook_event_name": "PreToolUse", "source": "compact"}),
      ("subagent", {"hook_event_name": "SessionStart", "source": "compact", "agent_type": "routed-judge"}),
    ):
      with self.subTest(silent=label):
        res = run_hook(json.dumps(payload))
        self.assertEqual(res.returncode, 0)
        self.assertEqual(res.stdout, "")

    # 3. boundary / fail-open: malformed JSON, non-dict JSON, empty stdin all exit 0 silently.
    for raw in ("", "{malformed", "[]", "null"):
      res = run_hook(raw)
      self.assertEqual(res.returncode, 0)
      self.assertEqual(res.stdout, "")

    # 4. lifecycle (self-content + recovery env switch): feeding own source text does not break, and CCP_GEMINI_COMPACT_REMIND=0 disables output.
    self_payload = json.dumps({
      "hook_event_name": "SessionStart",
      "source": "compact",
      "transcript_excerpt": hook_script.read_text(),
    })
    self.assertEqual(json.loads(run_hook(self_payload).stdout)["hookSpecificOutput"]["hookEventName"], "SessionStart")
    disabled = run_hook(self_payload, {"CCP_GEMINI_COMPACT_REMIND": "0"})
    self.assertEqual(disabled.returncode, 0)
    self.assertEqual(disabled.stdout, "")


if __name__ == "__main__":
  unittest.main()
