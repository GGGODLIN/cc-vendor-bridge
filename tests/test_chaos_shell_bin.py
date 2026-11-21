import json
import os
from pathlib import Path
import re
import shlex
import signal
import stat
import subprocess
import tempfile
import threading
import time
from http.server import BaseHTTPRequestHandler, HTTPServer
import unittest


ROOT = Path(__file__).resolve().parents[1]
CCP_FUNCTIONS = ROOT / "shell" / "ccp-functions.sh"
CC_FAST = ROOT / "shell" / "cc-fast.sh"
CCP_WATCH = ROOT / "bin" / "ccp-watch"
CCP_WATCH_RENDER = ROOT / "bin" / "ccp-watch-render"
CCP_BRUCE_WATCH = ROOT / "bin" / "ccp-bruce-watch"
EXA_SEARCH = ROOT / "bin" / "exa-search.sh"
MODEL_MAP = ROOT / "bin" / "ccp-model-map"


class ChaosShellBinTest(unittest.TestCase):
  def setUp(self):
    self.temp = tempfile.TemporaryDirectory()
    self.addCleanup(self.temp.cleanup)
    self.root = Path(self.temp.name)
    self.home = self.root / "home"
    self.tmpdir = self.root / "tmp"
    self.bin_dir = self.root / "bin"
    self.home.mkdir(parents=True)
    self.tmpdir.mkdir(parents=True)
    self.bin_dir.mkdir(parents=True)
    (self.home / ".claude" / "config").mkdir(parents=True)
    (self.home / ".cli-proxy-api").mkdir(parents=True)
    self.models_env = self.home / ".claude" / "config" / "gpt-models.env"
    self.models_env.write_text(
      "GPT_ASTRA=gpt-6-astra\nGPT_SOL=gpt-6-sol\nGPT_TERRA=gpt-6-terra\nGPT_LUNA=gpt-6-luna\n"
    )
    (self.home / ".cli-proxy-api" / "keys.env").write_text(
      "CLIPROXY_BASE_URL=http://127.0.0.1:8317\nCLIPROXY_KEY_CC=relay-key-canary\nCLIPROXY_MGMT_KEY=mgmt-canary\n"
    )
    self.records = self.root / "records.jsonl"
    self.fake_claude = self.bin_dir / "claude"
    self.fake_claude.write_text(
      """#!/usr/bin/env python3
import json, os, sys
rec = {
  "argv": sys.argv[1:],
  "has_api_key": "ANTHROPIC_API_KEY" in os.environ,
  "api_key": os.environ.get("ANTHROPIC_API_KEY"),
  "auth_token": os.environ.get("ANTHROPIC_AUTH_TOKEN"),
  "base_url": os.environ.get("ANTHROPIC_BASE_URL"),
  "cc_vendor": os.environ.get("CC_VENDOR"),
  "personal_bot": os.environ.get("PERSONAL_BOT_SESSION"),
}
with open(os.environ["CHAOS_RECORDS"], "a") as f:
  f.write(json.dumps(rec) + "\\n")
"""
    )
    self.fake_claude.chmod(0o755)
    self.base_env = {
      "PATH": f"{self.bin_dir}:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin",
      "HOME": str(self.home),
      "TMPDIR": str(self.tmpdir),
      "CHAOS_RECORDS": str(self.records),
      "CC_CLAUDE_BIN": str(self.fake_claude),
      "CCP_FREE_CLAUDE_BIN": str(self.fake_claude),
      "CCP_GPT_MODELS_FILE": str(self.models_env),
      "CCP_FREE_KEYS_FILE": str(self.home / ".cli-proxy-api" / "keys.env"),
    }

  def _write_exe(self, path: Path, content: str):
    path.write_text(content)
    path.chmod(0o755)

  def _read_records(self):
    if not self.records.exists():
      return []
    return [json.loads(line) for line in self.records.read_text().splitlines() if line.strip()]

  # 1. Credential leak: unset ANTHROPIC_API_KEY in ccp-deepseek / ccp-mimo / ccp-mimo-payg / ccp-local
  def test_direct_launchers_unset_outer_anthropic_api_key(self):
    stubs = self.root / "stubs.sh"
    stubs.write_text(
      """function /usr/bin/nc { return 0; }
function curl {
  if [[ "$*" == *"/v1/models"* ]]; then
    printf '{"data":[{"id":"local-qwen"}]}'
    return 0
  fi
  if [[ "$*" == *"/props"* ]]; then
    printf '{"default_generation_settings":{"n_ctx":131072}}'
    return 0
  fi
  return 0
}
"""
    )
    env = self.base_env | {
      "ANTHROPIC_API_KEY": "OUTER-LEAK-CANARY",
      "DEEPSEEK_API_KEY": "ds-key-canary",
      "MIMO_SUB_API_KEY": "mimo-sub-canary",
      "MIMO_API_KEY": "mimo-payg-canary",
    }
    for fn in ("ccp-deepseek", "ccp-mimo", "ccp-mimo-payg", "ccp-local"):
      with self.subTest(fn=fn):
        self.records.unlink(missing_ok=True)
        cmd = [
          "zsh", "-f", "-c",
          f"source {shlex.quote(str(stubs))}; source {shlex.quote(str(CCP_FUNCTIONS))}; {fn} -p hi",
        ]
        res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=15)
        self.assertEqual(res.returncode, 0, res.stderr)
        rec = self._read_records()[0]
        self.assertFalse(rec["has_api_key"], f"{fn} leaked ANTHROPIC_API_KEY: {rec}")
        self.assertNotIn("OUTER-LEAK-CANARY", res.stdout + res.stderr)

  # 3. ccp-watch: vendor injection, exit code propagation, tail -n +1, safe quoting
  def test_ccp_watch_rejects_regex_and_newline_vendor_injection(self):
    marker = self.root / "pwned"
    for bad_vendor in (".*", "glm.*", f"glm\n; touch {marker}", "deepseek|id", "unknown"):
      with self.subTest(vendor=bad_vendor):
        env = self.base_env | {"CMUX_WORKSPACE_ID": "ws-test"}
        res = subprocess.run(
          [str(CCP_WATCH), "--vendor", bad_vendor, "hello"],
          env=env,
          capture_output=True,
          text=True,
          timeout=10,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertIn("unsupported vendor", res.stderr)
        self.assertFalse(marker.exists(), f"injection ran for {bad_vendor!r}")

  def test_ccp_watch_preserves_exit_code_and_uses_tail_from_start_and_safe_quoting(self):
    cmux_log = self.root / "cmux.log"
    self._write_exe(
      self.bin_dir / "cmux",
      f"""#!/usr/bin/env bash
printf '%s\\n' "$*" >> {shlex.quote(str(cmux_log))}
case "$1" in
  new-split) echo "surface:99" ;;
  identify) exit 0 ;;
  *) exit 0 ;;
esac
""",
    )
    self._write_exe(
      self.bin_dir / "claude",
      """#!/usr/bin/env bash
echo '{"type":"system","subtype":"init","session_id":"s1","model":"m1","cwd":"/tmp"}'
exit 42
""",
    )
    # Create a space + single-quote subdir copy/symlink to bin dir to test quoting
    tricky_dir = self.root / "dir with 'quote"
    tricky_dir.mkdir()
    tricky_watch = tricky_dir / "ccp-watch"
    tricky_render = tricky_dir / "ccp-watch-render"
    tricky_watch.write_text(CCP_WATCH.read_text())
    tricky_watch.chmod(0o755)
    tricky_render.write_text(CCP_WATCH_RENDER.read_text())
    tricky_render.chmod(0o755)

    env = self.base_env | {
      "CMUX_WORKSPACE_ID": "ws-test",
      "CCP_WATCH_DWELL": "0",
    }
    res = subprocess.run(
      [str(tricky_watch), "test task"],
      env=env,
      capture_output=True,
      text=True,
      timeout=15,
    )
    self.assertEqual(res.returncode, 42, f"expected exit 42, got {res.returncode}\nstderr={res.stderr}")
    cmux_text = cmux_log.read_text()
    self.assertIn("tail -n +1 -F", cmux_text)
    # Verify renderer command in SIDE_CMD is safely shell-parsed back to tricky_render
    send_line = next(l for l in cmux_text.splitlines() if l.startswith("send --surface surface:99 "))
    side_cmd = send_line.split("send --surface surface:99 ", 1)[1]
    self.assertNotIn(f"'{tricky_render}'", side_cmd)
    # Check that side_cmd is syntactically valid bash
    parse_check = subprocess.run(["bash", "-n", "-c", side_cmd], capture_output=True, text=True)
    self.assertEqual(parse_check.returncode, 0, parse_check.stderr)

  # 4. ccp-watch-render: lossless multiline/tab delta + no printf format injection
  def test_ccp_watch_render_preserves_newlines_tabs_backslashes_and_percent_signs(self):
    events = [
      {
        "type": "system",
        "subtype": "init",
        "session_id": "abc12345%s%n",
        "model": "model-%s-%n-\\x",
        "cwd": "/tmp/dir\t%s%n\\end",
      },
      {
        "type": "system",
        "subtype": "hook_%s",
        "hook_event_name": "evt_%n",
      },
      {
        "type": "stream_event",
        "event": {"type": "content_block_start", "content_block": {"type": "tool_use", "name": "tool_%s_%n\\q"}},
      },
      {
        "type": "stream_event",
        "event": {
          "type": "content_block_delta",
          "delta": {"type": "text_delta", "text": "line1\nline2\tafter_tab\t%s%n\\backslash"},
        },
      },
      {
        "type": "stream_event",
        "event": {
          "type": "content_block_delta",
          "delta": {"type": "thinking_delta", "thinking": "think1\nthink2\tthink_tab\t%s"},
        },
      },
      {"type": "stream_event", "event": {"type": "content_block_stop"}},
      {"type": "rate_limit_event", "message": {"status": "ok_%s", "rateLimitType": "rpm_%n"}},
      {"type": "mystery_%s", "x": 1},
      {"type": "result", "duration_ms": 1500, "num_turns": 2, "total_cost_usd": 0.1234, "subtype": "ok_%s"},
      {"type": "ccp_watch_eof"},
    ]
    ndjson = "\n".join(json.dumps(ev) for ev in events) + "\n"
    res = subprocess.run(
      [str(CCP_WATCH_RENDER)],
      input=ndjson,
      env=self.base_env,
      capture_output=True,
      text=True,
      timeout=10,
    )
    self.assertEqual(res.returncode, 0, res.stderr)
    self.assertEqual(res.stderr, "", f"unexpected stderr: {res.stderr}")
    # Strip ANSI escapes to verify exact text fidelity
    plain = re.sub(r"\x1b\[[0-9;]*m", "", res.stdout)
    self.assertIn("line1\nline2\tafter_tab\t%s%n\\backslash", plain)
    self.assertIn("think1\nthink2\tthink_tab\t%s", plain)
    self.assertIn("model-%s-%n-\\x", plain)
    self.assertIn("/tmp/dir\t%s%n\\end", plain)
    self.assertIn("tool_%s_%n\\q", plain)
    self.assertIn("hook_%s", plain)
    self.assertIn("evt_%n", plain)
    self.assertIn("ok_%s / rpm_%n", plain)
    self.assertIn("? mystery_%s", plain)
    self.assertIn("result (ok_%s)", plain)

  # 5. ccp-bruce-watch: macOS ms timer, http_code=000 JSON, missing flag value, signal cleanup
  def test_ccp_bruce_watch_missing_arg_does_not_unbound_crash(self):
    for flag in ("--interval", "--timeout", "--warn-below", "--stab-alert-below"):
      with self.subTest(flag=flag):
        res = subprocess.run(
          [str(CCP_BRUCE_WATCH), flag],
          env=self.base_env | {"BRUCE_API_KEY": "bruce-canary"},
          capture_output=True,
          text=True,
          timeout=10,
        )
        self.assertNotEqual(res.returncode, 0)
        self.assertNotIn("unbound variable", res.stderr)
        self.assertIn("requires an argument", res.stderr)

  def test_ccp_bruce_watch_handles_http_000_and_latency_without_crash(self):
    self._write_exe(self.bin_dir / "osascript", "#!/bin/sh\nexit 0\n")
    # Pick an unbound local port so curl immediately fails with connection refused -> 000
    import socket
    s = socket.socket()
    s.bind(("127.0.0.1", 0))
    dead_port = s.getsockname()[1]
    s.close()

    env = self.base_env | {
      "BRUCE_API_KEY": "bruce-canary",
      "CCP_BRUCE_WATCH_URL": f"http://127.0.0.1:{dead_port}/v1/pool/status",
      "CCP_BRUCE_WATCH_MAX_PROBES": "1",
    }
    res = subprocess.run(
      [str(CCP_BRUCE_WATCH), "--interval", "0", "--timeout", "1"],
      env=env,
      capture_output=True,
      text=True,
      timeout=15,
    )
    self.assertEqual(res.returncode, 0, f"stderr={res.stderr}\nstdout={res.stdout}")
    self.assertNotIn("value too great for base", res.stderr)
    self.assertNotIn("invalid JSON", res.stderr)
    log_file = self.home / ".claude" / "logs" / "bruce-pool-health.jsonl"
    self.assertTrue(log_file.exists())
    row = json.loads(log_file.read_text().strip().splitlines()[0])
    self.assertEqual(row["endpoint_status"], 0)
    self.assertIsInstance(row["endpoint_latency_ms"], int)
    self.assertGreaterEqual(row["endpoint_latency_ms"], 0)
    self.assertIsNone(row["health_percent"])

  def test_ccp_bruce_watch_signal_cleans_up_temp_body_file(self):
    self._write_exe(self.bin_dir / "osascript", "#!/bin/sh\nexit 0\n")

    class SlowHandler(BaseHTTPRequestHandler):
      def do_GET(self):
        time.sleep(5)
      def log_message(self, *args):
        pass

    srv = HTTPServer(("127.0.0.1", 0), SlowHandler)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    self.addCleanup(srv.shutdown)
    self.addCleanup(srv.server_close)

    env = self.base_env | {
      "BRUCE_API_KEY": "bruce-canary",
      "CCP_BRUCE_WATCH_URL": f"http://127.0.0.1:{srv.server_address[1]}/v1/pool/status",
    }
    proc = subprocess.Popen(
      [str(CCP_BRUCE_WATCH), "--interval", "1", "--timeout", "10"],
      env=env,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
    )
    # Wait until mktemp creates the body file inside isolated TMPDIR
    deadline = time.time() + 5
    while time.time() < deadline:
      if list(self.tmpdir.glob("ccp-bruce-watch.*")):
        break
      time.sleep(0.05)
    proc.send_signal(signal.SIGTERM)
    out, err = proc.communicate(timeout=10)
    self.assertEqual(proc.returncode, 0, err)
    leftovers = list(self.tmpdir.glob("ccp-bruce-watch.*"))
    self.assertEqual(leftovers, [], f"leaked temp files: {leftovers}")

  # 6. exa-search.sh: network failure double-000 + non-numeric N
  def test_exa_search_network_failure_does_not_produce_double_000_syntax_error(self):
    self._write_exe(
      self.bin_dir / "security",
      "#!/usr/bin/env bash\necho 'exa-key-canary'\n",
    )
    self._write_exe(
      self.bin_dir / "curl",
      "#!/usr/bin/env bash\nprintf '000'\nexit 7\n",
    )
    res = subprocess.run(
      [str(EXA_SEARCH), "test query", "3"],
      env=self.base_env,
      capture_output=True,
      text=True,
      timeout=10,
    )
    self.assertEqual(res.returncode, 3, res.stderr)
    self.assertNotIn("integer expression expected", res.stderr)
    self.assertNotIn("000000", res.stderr)
    self.assertIn("ERROR: HTTP 000\n", res.stderr)

  def test_exa_search_rejects_non_numeric_n_cleanly(self):
    self._write_exe(self.bin_dir / "security", "#!/usr/bin/env bash\necho 'exa-key-canary'\n")
    for bad_n in ("abc", "0", "-5", "1.5"):
      with self.subTest(n=bad_n):
        res = subprocess.run(
          [str(EXA_SEARCH), "test query", bad_n],
          env=self.base_env,
          capture_output=True,
          text=True,
          timeout=10,
        )
        self.assertEqual(res.returncode, 1)
        self.assertIn("positive integer", res.stderr)
        self.assertNotIn("jq:", res.stderr)

  # 7. ccp-functions.sh + cc-fast.sh + ccp-model-map boundaries
  def test_ccp_relay_priority_apply_creates_tmp_with_0600_and_cleans_on_failure(self):
    auth_dir = self.home / ".cli-proxy-api"
    f = auth_dir / "codex-test.json"
    f.write_text('{"email":"a@example.test","access_token":"TOK"}\n')
    os.chmod(f, 0o600)

    # Wrap jq to capture permissions of the created temp file while stdout is redirected to it
    real_jq = subprocess.check_output(["which", "jq"], text=True).strip()
    perm_log = self.root / "tmp_perm.log"
    self._write_exe(
      self.bin_dir / "jq",
      f"""#!/usr/bin/env python3
import glob, os, stat, sys
for p in glob.glob(os.path.join({repr(str(auth_dir))}, "codex-*.tmp.*")):
  with open({repr(str(perm_log))}, "a") as log:
    log.write(oct(stat.S_IMODE(os.stat(p).st_mode)) + "\\n")
os.execv({repr(real_jq)}, [{repr(real_jq)}, *sys.argv[1:]])
""",
    )
    cmd = [
      "zsh", "-f", "-c",
      f"umask 022; source {shlex.quote(str(CCP_FUNCTIONS))}; CCP_RELAY_AUTH_DIR={shlex.quote(str(auth_dir))} ccp-relay-priority-apply <<< $'a@example.test\\t10'",
    ]
    res = subprocess.run(cmd, env=self.base_env, capture_output=True, text=True, timeout=10)
    self.assertEqual(res.returncode, 0, res.stderr)
    perms = perm_log.read_text().splitlines()
    self.assertTrue(perms)
    self.assertEqual(perms[-1], "0o600", f"temp file created with insecure mode {perms[-1]} before chmod!")

  def test_ccp_effort_for_model_empty_env_does_not_wildcard_match_all(self):
    cmd = [
      "zsh", "-f", "-c",
      f"source {shlex.quote(str(CCP_FUNCTIONS))}; GPT_ASTRA=''; GPT_SOL=''; print -r -- \"$(_ccp_effort_for_model claude-sonnet-4-6)|$(_ccp_effort_for_model ds-free)\"",
    ]
    res = subprocess.run(cmd, env=self.base_env, capture_output=True, text=True, timeout=10)
    self.assertEqual(res.returncode, 0, res.stderr)
    self.assertEqual(res.stdout.strip(), "|")

  def test_nounset_safety_when_keys_or_optional_vars_unset(self):
    stubs = self.root / "nounset_stubs.sh"
    stubs.write_text(
      """function /usr/bin/nc { return 0; }
function curl {
  if [[ "$*" == *"/v1/models"* ]]; then
    printf '{"data":[{"id":"local-qwen"}]}'
    return 0
  fi
  return 0
}
"""
    )
    env = dict(self.base_env)
    for k in ("DEEPSEEK_API_KEY", "ZAI_API_KEY", "MIMO_SUB_API_KEY", "MIMO_API_KEY", "BRUCE_API_KEY", "LITELLM_MASTER_KEY", "LOCAL_MODEL", "CC_VENDOR"):
      env.pop(k, None)

    for fn in ("ccp-deepseek", "ccp-glm", "ccp-mimo", "ccp-mimo-payg", "ccp-bruce", "ccp-bruce-status", "ccp-bruce-watch", "codex-bruce", "codex-glm"):
      with self.subTest(fn=fn):
        cmd = ["zsh", "-f", "-u", "-c", f"source {shlex.quote(str(CCP_FUNCTIONS))}; {fn}"]
        res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(res.returncode, 1, res.stderr)
        self.assertNotIn("parameter not set", res.stderr)

    # ccp-local under set -u with LOCAL_MODEL unset
    cmd_local = [
      "zsh", "-f", "-u", "-c",
      f"source {shlex.quote(str(stubs))}; source {shlex.quote(str(CCP_FUNCTIONS))}; ccp-local -p hi",
    ]
    res_local = subprocess.run(cmd_local, env=env, capture_output=True, text=True, timeout=10)
    self.assertEqual(res_local.returncode, 0, res_local.stderr)
    self.assertNotIn("parameter not set", res_local.stderr)

    # ccp-resume under set -u with CC_VENDOR unset (fake fzf/jq path)
    proj_hash = str(self.root).lstrip("/").replace("/", "-")
    proj_dir = self.home / ".claude" / "projects" / f"-{proj_hash}"
    proj_dir.mkdir(parents=True)
    sid = "12345678-1234-1234-1234-123456789abc"
    (proj_dir / f"{sid}.jsonl").write_text(
      json.dumps({"type": "assistant", "message": {"model": "claude-opus-4-6"}}) + "\n"
    )
    self._write_exe(self.bin_dir / "fzf", f"#!/usr/bin/env bash\necho '{sid}'\n")
    cmd_resume = [
      "zsh", "-f", "-u", "-c",
      f"cd {shlex.quote(str(self.root))} && source {shlex.quote(str(CCP_FUNCTIONS))}; ccp-resume",
    ]
    res_resume = subprocess.run(cmd_resume, env=env, capture_output=True, text=True, timeout=10)
    self.assertEqual(res_resume.returncode, 0, res_resume.stderr)
    self.assertNotIn("parameter not set", res_resume.stderr)

  def test_cc_fast_does_not_swallow_bot_as_value_of_resume_or_model(self):
    for flag in ("--resume", "--model", "-r"):
      with self.subTest(flag=flag):
        self.records.unlink(missing_ok=True)
        cmd = [
          "zsh", "-f", "-c",
          f"source {shlex.quote(str(CC_FAST))}; cc_fast_run {shlex.quote(str(self.fake_claude))} -- {flag} -bot -p hi",
        ]
        res = subprocess.run(cmd, env=self.base_env, capture_output=True, text=True, timeout=10)
        self.assertEqual(res.returncode, 0, res.stderr)
        rec = self._read_records()[0]
        self.assertIsNone(rec["personal_bot"], f"{flag} -bot wrongly activated bot mode")
        self.assertEqual(rec["argv"], [flag, "-bot", "-p", "hi"])

    # Leading -bot and boolean flag + -bot still activate bot mode
    for args, expected_argv in ((["-bot", "--resume", "s1"], ["--resume", "s1"]), (["-c", "-bot"], ["-c"])):
      with self.subTest(args=args):
        self.records.unlink(missing_ok=True)
        quoted = " ".join(shlex.quote(a) for a in args)
        cmd = [
          "zsh", "-f", "-c",
          f"source {shlex.quote(str(CC_FAST))}; cc_fast_run {shlex.quote(str(self.fake_claude))} -- {quoted}",
        ]
        res = subprocess.run(cmd, env=self.base_env, capture_output=True, text=True, timeout=10)
        self.assertEqual(res.returncode, 0, res.stderr)
        rec = self._read_records()[0]
        self.assertEqual(rec["personal_bot"], "1")
        self.assertEqual(rec["argv"], expected_argv)

  def test_run_claude_test_flag_position_and_direct_vendor_auth_preservation(self):
    stubs = self.root / "test_stubs.sh"
    stubs.write_text("function /usr/bin/nc { return 0; }\n")
    test_dir = self.root / "unii-exp"
    (test_dir / "plugin").mkdir(parents=True)
    (test_dir / "trigger").mkdir(parents=True)
    env = self.base_env | {
      "CCP_TEST_DIR": str(test_dir),
      "ZAI_API_KEY": "zai-secret-canary",
      "CCP_CLAUDE_OAUTH_PRESENT": "1",
    }

    # 1. -test after `--` or as value of `--resume` / `--model` must NOT be consumed
    for args in (["--", "-test"], ["--resume", "-test"], ["--model", "-test"], ["-p", "-test"]):
      with self.subTest(args=args):
        self.records.unlink(missing_ok=True)
        quoted = " ".join(shlex.quote(a) for a in args)
        cmd = [
          "zsh", "-f", "-c",
          f"source {shlex.quote(str(stubs))}; source {shlex.quote(str(CCP_FUNCTIONS))}; ccp-glm {quoted}",
        ]
        res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(res.returncode, 0, res.stderr)
        rec = self._read_records()[0]
        self.assertNotIn("--plugin-dir", rec["argv"])
        for a in args:
          self.assertIn(a, rec["argv"])

    # 2. Leading -test on direct vendor (ccp-glm) injects plugins and keeps ZAI_API_KEY even without CLIPROXY_KEY_CC
    self.records.unlink(missing_ok=True)
    cmd_glm = [
      "zsh", "-f", "-c",
      f"unset CLIPROXY_KEY_CC; source {shlex.quote(str(stubs))}; source {shlex.quote(str(CCP_FUNCTIONS))}; ccp-glm -test -p hi",
    ]
    res_glm = subprocess.run(cmd_glm, env=env, capture_output=True, text=True, timeout=10)
    self.assertEqual(res_glm.returncode, 0, res_glm.stderr)
    rec_glm = self._read_records()[0]
    self.assertIn("--plugin-dir", rec_glm["argv"])
    self.assertNotIn("-test", rec_glm["argv"])
    self.assertEqual(rec_glm["auth_token"], "zai-secret-canary")

    # 3. Leading -test on split relay (ccp-ds-free with OAuth present) switches auth token to CLIPROXY_KEY_CC
    self.records.unlink(missing_ok=True)
    cmd_relay = [
      "zsh", "-f", "-c",
      f"source {shlex.quote(str(stubs))}; source {shlex.quote(str(CCP_FUNCTIONS))}; ccp-ds-free -test -p hi",
    ]
    res_relay = subprocess.run(cmd_relay, env=env, capture_output=True, text=True, timeout=10)
    self.assertEqual(res_relay.returncode, 0, res_relay.stderr)
    rec_relay = self._read_records()[0]
    self.assertIn("--plugin-dir", rec_relay["argv"])
    self.assertEqual(rec_relay["auth_token"], "relay-key-canary")

  def test_model_map_matches_downstream_base_url_without_trailing_slash(self):
    relay_cfg = self.root / "relay.yaml"
    litellm_cfg = self.root / "litellm.yaml"
    agentrouter_cfg = self.root / "agentrouter.yaml"
    relay_cfg.write_text(
      """openai-compatibility:
  - name: bai-no-slash
    priority: 10
    base-url: http://127.0.0.1:8000
    models:
      - name: bai-glm
        alias: free
  - name: ar-no-slash
    priority: 5
    base-url: http://127.0.0.1:8002
    models:
      - name: ar-glm
        alias: free
"""
    )
    litellm_cfg.write_text(
      """model_list:
  - model_name: bai-glm
    litellm_params:
      model: openai/glm-5.3-no-slash
"""
    )
    agentrouter_cfg.write_text(
      """model_list:
  - model_name: ar-glm
    litellm_params:
      model: openai/responses/gpt-ar-no-slash
"""
    )
    import importlib.machinery
    import importlib.util
    loader = importlib.machinery.SourceFileLoader("ccp_model_map", str(MODEL_MAP))
    spec = importlib.util.spec_from_loader("ccp_model_map", loader)
    mod = importlib.util.module_from_spec(spec)
    loader.exec_module(mod)
    old_env = os.environ.copy()
    try:
      os.environ["CCP_FREE_CONFIG_FILE"] = str(relay_cfg)
      os.environ["CCP_FREE_LITELLM_CONFIG_FILE"] = str(litellm_cfg)
      os.environ["CCP_FREE_AGENTROUTER_CONFIG_FILE"] = str(agentrouter_cfg)
      pools = mod.pools()
    finally:
      os.environ.clear()
      os.environ.update(old_env)
    terminals = {row[2]: row[3] for row in pools["free"]}
    self.assertEqual(terminals["bai-no-slash"], "glm-5.3-no-slash")
    self.assertEqual(terminals["ar-no-slash"], "gpt-ar-no-slash")

  def test_ccp_watch_render_survives_invalid_utf8_bytes(self):
    ev1 = {"type": "system", "subtype": "init", "session_id": "s12345678", "model": "m1", "cwd": "/tmp"}
    ev2 = {"type": "stream_event", "event": {"type": "content_block_delta", "delta": {"type": "text_delta", "text": "after-bad-bytes"}}}
    ev3 = {"type": "result", "duration_ms": 500, "num_turns": 1, "total_cost_usd": 0.01, "subtype": "success"}
    eof = {"type": "ccp_watch_eof"}
    payload = (
      json.dumps(ev1).encode("utf-8") + b"\n"
      + b"\xff\xfe bad utf8\n"
      + json.dumps(ev2).encode("utf-8") + b"\n"
      + json.dumps(ev3).encode("utf-8") + b"\n"
      + json.dumps(eof).encode("utf-8") + b"\n"
    )
    res = subprocess.run(
      [str(CCP_WATCH_RENDER)],
      input=payload,
      env=self.base_env,
      capture_output=True,
      timeout=10,
    )
    self.assertEqual(res.returncode, 0, res.stderr.decode("utf-8", "replace"))
    self.assertNotIn(b"UnicodeDecodeError", res.stderr)
    out = res.stdout.decode("utf-8", "replace")
    self.assertIn("s1234567", out)
    self.assertIn("after-bad-bytes", out)
    self.assertIn("result (success)", out)
    self.assertIn("stream end", out)

  def test_cc_flag_takes_value_shared_across_fast_and_run_claude(self):
    stubs = self.root / "flag_stubs.sh"
    stubs.write_text("function /usr/bin/nc { return 0; }\n")
    test_dir = self.root / "unii-exp"
    (test_dir / "plugin").mkdir(parents=True)
    (test_dir / "trigger").mkdir(parents=True)
    env = self.base_env | {
      "CCP_TEST_DIR": str(test_dir),
      "ZAI_API_KEY": "zai-secret-canary",
    }
    new_flags = (
      "--agent",
      "--debug-file",
      "--max-budget-usd",
      "--autocompact",
      "--plugin-url",
      "--permission-prompts",
      "--environment",
      "--betas",
      "--file",
      "--system-prompt-file",
      "--append-system-prompt-file",
      "--remote-control-session-name-prefix",
    )
    for flag in new_flags:
      with self.subTest(mode="cc_fast", flag=flag):
        self.records.unlink(missing_ok=True)
        cmd = [
          "zsh", "-f", "-c",
          f"source {shlex.quote(str(CC_FAST))}; cc_fast_run {shlex.quote(str(self.fake_claude))} -- {flag} -bot -p hi",
        ]
        res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(res.returncode, 0, res.stderr)
        rec = self._read_records()[0]
        self.assertIsNone(rec["personal_bot"], f"{flag} -bot wrongly activated bot mode")
        self.assertEqual(rec["argv"], [flag, "-bot", "-p", "hi"])

      with self.subTest(mode="_ccp_run_claude", flag=flag):
        self.records.unlink(missing_ok=True)
        cmd = [
          "zsh", "-f", "-c",
          f"source {shlex.quote(str(stubs))}; source {shlex.quote(str(CCP_FUNCTIONS))}; ccp-glm {flag} -test -p hi",
        ]
        res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(res.returncode, 0, res.stderr)
        rec = self._read_records()[0]
        self.assertNotIn("--plugin-dir", rec["argv"], f"{flag} -test wrongly activated test mode")
        self.assertIn(flag, rec["argv"])
        self.assertIn("-test", rec["argv"])

  def test_run_claude_test_does_not_leak_relay_key_when_base_url_empty(self):
    test_dir = self.root / "unii-exp"
    (test_dir / "plugin").mkdir(parents=True)
    (test_dir / "trigger").mkdir(parents=True)
    env = self.base_env | {
      "CCP_TEST_DIR": str(test_dir),
      "CLIPROXY_KEY_CC": "relay-key-canary",
    }
    env.pop("ANTHROPIC_BASE_URL", None)
    env.pop("ANTHROPIC_AUTH_TOKEN", None)
    self.records.unlink(missing_ok=True)
    cmd = [
      "zsh", "-f", "-c",
      f"source {shlex.quote(str(CCP_FUNCTIONS))}; _ccp_run_claude {shlex.quote(str(self.fake_claude))} -test -p hi",
    ]
    res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=10)
    self.assertEqual(res.returncode, 0, res.stderr)
    rec = self._read_records()[0]
    self.assertIn("--plugin-dir", rec["argv"])
    self.assertIsNone(rec["base_url"])
    self.assertIsNone(rec["auth_token"])

  def test_nounset_safety_when_gpt_models_file_missing_and_mgmt_key_unset(self):
    # Remove CLIPROXY_MGMT_KEY from keys.env and point CCP_GPT_MODELS_FILE to missing path
    (self.home / ".cli-proxy-api" / "keys.env").write_text(
      "CLIPROXY_BASE_URL=http://127.0.0.1:8317\nCLIPROXY_KEY_CC=relay-key-canary\n"
    )
    stubs = self.root / "missing_models_stubs.sh"
    stubs.write_text(
      """function /usr/bin/nc { return 0; }
function curl { return 1; }
"""
    )
    env = self.base_env | {
      "CCP_GPT_MODELS_FILE": str(self.root / "nonexistent-gpt-models.env"),
      "BRUCE_API_KEY": "bruce-canary",
      "CCP_CLAUDE_OAUTH_PRESENT": "1",
    }
    env.pop("CLIPROXY_MGMT_KEY", None)

    res_whoami = subprocess.run(
      ["zsh", "-f", "-u", "-c", f"source {shlex.quote(str(stubs))}; source {shlex.quote(str(CCP_FUNCTIONS))}; ccp-gpt-whoami"],
      env=env,
      capture_output=True,
      text=True,
      timeout=10,
    )
    self.assertNotIn("parameter not set", res_whoami.stderr)

    stubs_launch = self.root / "missing_models_launch_stubs.sh"
    stubs_launch.write_text(
      """function /usr/bin/nc { return 0; }
function ccp-gpt-whoami { return 0; }
function ccp-free-whoami { return 0; }
"""
    )
    for fn in ("ccp-bruce", "ccp-gpt", "ccp-sol", "ccp-gpt-smart", "ccp-mix-gpt", "ccp-mix-sol"):
      with self.subTest(fn=fn):
        self.records.unlink(missing_ok=True)
        cmd = [
          "zsh", "-f", "-u", "-c",
          f"source {shlex.quote(str(stubs_launch))}; source {shlex.quote(str(CCP_FUNCTIONS))}; {fn} -p hi",
        ]
        res = subprocess.run(cmd, env=env, capture_output=True, text=True, timeout=10)
        self.assertEqual(res.returncode, 0, res.stderr)
        self.assertNotIn("parameter not set", res.stderr)

  def test_ccp_bruce_watch_rejects_non_numeric_args_and_handles_non_numeric_api_fields(self):
    self._write_exe(self.bin_dir / "osascript", "#!/usr/bin/env bash\nexit 0\n")
    env = self.base_env | {"BRUCE_API_KEY": "bruce-canary"}
    for args, extra_env in (
      (["--interval", "abc"], {}),
      (["--timeout", "-1"], {}),
      (["--warn-below", "xyz"], {}),
      (["--stab-alert-below", "1.5"], {}),
      (["--interval", "0"], {"CCP_BRUCE_WATCH_MAX_PROBES": "notnum"}),
    ):
      with self.subTest(args=args, extra_env=extra_env):
        res = subprocess.run(
          [str(CCP_BRUCE_WATCH), *args],
          env=env | extra_env,
          capture_output=True,
          text=True,
          timeout=10,
        )
        self.assertEqual(res.returncode, 1)
        self.assertNotIn("unbound variable", res.stderr)
        self.assertIn("non-negative integer", res.stderr)

    payloads = iter([
      b'{"healthPercent":"bad","serviceStabilityPercent":"n/a"}',
      b'{"healthPercent":80,"serviceStabilityPercent":"oops"}',
    ])

    class BadFieldsHandler(BaseHTTPRequestHandler):
      def do_GET(self):
        body = next(payloads, b'{"healthPercent":100,"serviceStabilityPercent":100}')
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)
      def log_message(self, *args):
        pass

    srv = HTTPServer(("127.0.0.1", 0), BadFieldsHandler)
    t = threading.Thread(target=srv.serve_forever, daemon=True)
    t.start()
    self.addCleanup(srv.shutdown)
    self.addCleanup(srv.server_close)

    res = subprocess.run(
      [str(CCP_BRUCE_WATCH), "--interval", "0", "--timeout", "2"],
      env=env | {
        "CCP_BRUCE_WATCH_URL": f"http://127.0.0.1:{srv.server_address[1]}/v1/pool/status",
        "CCP_BRUCE_WATCH_MAX_PROBES": "2",
      },
      capture_output=True,
      text=True,
      timeout=15,
    )
    self.assertEqual(res.returncode, 0, res.stderr)
    self.assertNotIn("jq:", res.stderr)
    log_file = self.home / ".claude" / "logs" / "bruce-pool-health.jsonl"
    rows = [json.loads(line) for line in log_file.read_text().splitlines() if line.strip()]
    self.assertEqual(len(rows), 2)
    self.assertIsNone(rows[0]["health_percent"])
    self.assertIsNone(rows[0]["service_stability_percent"])
    self.assertEqual(rows[1]["health_percent"], 80)
    self.assertIsNone(rows[1]["service_stability_percent"])

  def test_ccp_watch_new_split_failure_releases_lock_and_cleans_temp_files(self):
    self._write_exe(
      self.bin_dir / "cmux",
      """#!/usr/bin/env bash
case "$1" in
  new-split) echo "cmux error: no window" >&2; exit 1 ;;
  *) exit 0 ;;
esac
""",
    )
    watch_tmp = self.root / "watch_tmp_fail"
    watch_tmp.mkdir()
    env = self.base_env | {
      "CMUX_WORKSPACE_ID": "ws-test",
      "CCP_WATCH_TMPDIR": str(watch_tmp),
    }
    res = subprocess.run(
      [str(CCP_WATCH), "test task"],
      env=env,
      capture_output=True,
      text=True,
      timeout=10,
    )
    self.assertEqual(res.returncode, 4, res.stderr)
    self.assertFalse((watch_tmp / "ccp-watch.lock.d").exists(), "LOCKDIR leaked on new-split failure")
    leftovers = list(watch_tmp.glob("ccp-watch-ndjson.*")) + list(watch_tmp.glob("ccp-watch-err.*"))
    self.assertEqual(leftovers, [], f"temp files leaked on new-split failure: {leftovers}")

  def test_ccp_watch_cleanup_runs_once_on_sigterm(self):
    cmux_log = self.root / "cmux_sigterm.log"
    self._write_exe(
      self.bin_dir / "cmux",
      f"""#!/usr/bin/env bash
printf '%s\\n' "$*" >> {shlex.quote(str(cmux_log))}
case "$1" in
  new-split) echo "surface:77" ;;
  identify) exit 0 ;;
  *) exit 0 ;;
esac
""",
    )
    self._write_exe(
      self.bin_dir / "claude",
      """#!/usr/bin/env bash
echo '{"type":"system","subtype":"init","session_id":"s1","model":"m1","cwd":"/tmp"}'
sleep 1
""",
    )
    watch_tmp = self.root / "watch_tmp_sig"
    watch_tmp.mkdir()
    env = self.base_env | {
      "CMUX_WORKSPACE_ID": "ws-test",
      "CCP_WATCH_TMPDIR": str(watch_tmp),
      "CCP_WATCH_DWELL": "0",
    }
    proc = subprocess.Popen(
      [str(CCP_WATCH), "long task"],
      env=env,
      stdout=subprocess.PIPE,
      stderr=subprocess.PIPE,
      text=True,
    )
    self.addCleanup(lambda: (proc.poll() is None and proc.kill(), proc.wait()))
    deadline = time.time() + 5
    while time.time() < deadline:
      if cmux_log.exists() and "send-key --surface surface:77 Enter" in cmux_log.read_text():
        break
      time.sleep(0.05)
    time.sleep(0.6)
    proc.send_signal(signal.SIGTERM)
    out, err = proc.communicate(timeout=10)
    self.assertEqual(err.count("stream archived:"), 1, f"cleanup ran multiple times:\n{err}")
    close_count = sum(1 for line in cmux_log.read_text().splitlines() if line.startswith("close-surface"))
    self.assertEqual(close_count, 1, f"close-surface ran {close_count} times")

  def test_ccp_watch_survives_non_json_zshrc_noise_and_creates_0600_temp_files(self):
    cmux_log = self.root / "cmux_noise.log"
    self._write_exe(
      self.bin_dir / "cmux",
      f"""#!/usr/bin/env bash
printf '%s\\n' "$*" >> {shlex.quote(str(cmux_log))}
case "$1" in
  new-split) echo "surface:55" ;;
  identify) exit 0 ;;
  *) exit 0 ;;
esac
""",
    )
    (self.home / ".zshrc").write_text(
      """echo "Welcome from interactive .zshrc"
ccp-glm-rescue() {
  echo "extra banner line"
  echo "{broken json"
  echo '{"type":"system","subtype":"init","session_id":"s1","model":"glm","cwd":"/tmp"}'
  echo '{"type":"result","result":"noise-survived"}'
}
"""
    )
    watch_tmp = self.root / "watch_tmp_noise"
    watch_tmp.mkdir()
    env = self.base_env | {
      "CMUX_WORKSPACE_ID": "ws-test",
      "CCP_WATCH_TMPDIR": str(watch_tmp),
      "CCP_WATCH_DWELL": "0",
    }
    res = subprocess.run(
      [str(CCP_WATCH), "--vendor", "glm", "test task"],
      env=env,
      capture_output=True,
      text=True,
      timeout=15,
    )
    self.assertEqual(res.returncode, 0, res.stderr)
    self.assertIn("noise-survived", res.stdout)
    ndjson_files = list(watch_tmp.glob("ccp-watch-ndjson.*"))
    err_files = list(watch_tmp.glob("ccp-watch-err.*"))
    self.assertEqual(len(ndjson_files), 1)
    self.assertEqual(len(err_files), 1)
    self.assertEqual(stat.S_IMODE(os.stat(ndjson_files[0]).st_mode), 0o600)
    self.assertEqual(stat.S_IMODE(os.stat(err_files[0]).st_mode), 0o600)


if __name__ == "__main__":
  unittest.main(verbosity=2)
