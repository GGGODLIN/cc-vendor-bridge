#!/usr/bin/env zsh
# 本檔在契約測試底下：改完必跑（從 repo root）：zsh tests/ccp-free-wrapper.test.zsh
# 契約（2026-08-28 改版）：ccp-free 走 CLIProxyAPI :8317 免費層（glm-free，經 cline2api → Cline 帳號），
# 不再依賴 FCC server（:18082 / com.gggodlin.ccp-free-fcc 已退役）。
set -u

ROOT="${0:A:h:h}"
SRC="$ROOT/shell/ccp-functions.sh"
MODEL='glm-free'
CC_KEY='test-cc-key'
CC_URL='http://127.0.0.1:8317'
FAILURES=0
FIXTURE=''
WRAPPER_STATUS=0

ok() {
  print -r -- "ok - $1"
}

bad() {
  print -ru2 -- "not ok - $1"
  (( FAILURES++ ))
}

assert_status() {
  local label="$1" expected="$2"
  if (( WRAPPER_STATUS == expected )); then
    ok "$label"
  else
    bad "$label"
  fi
}

assert_file_line() {
  local label="$1" path="$2" line="$3"
  if [[ -f "$path" ]] && /usr/bin/grep -Fqx -- "$line" "$path"; then
    ok "$label"
  else
    bad "$label"
  fi
}

assert_file_not_line() {
  local label="$1" path="$2" line="$3"
  if [[ ! -f "$path" ]] || ! /usr/bin/grep -Fqx -- "$line" "$path"; then
    ok "$label"
  else
    bad "$label"
  fi
}

assert_file_absent() {
  local label="$1" path="$2"
  if [[ ! -e "$path" ]]; then
    ok "$label"
  else
    bad "$label"
  fi
}

assert_output_contains() {
  local label="$1" needle="$2"
  if /usr/bin/grep -Fq -- "$needle" "$FIXTURE/output.log"; then
    ok "$label"
  else
    bad "$label"
  fi
}

assert_line_count() {
  local label="$1" path="$2" expected="$3" actual
  actual=$(/usr/bin/wc -l < "$path" | /usr/bin/tr -d ' ')
  if [[ "$actual" == "$expected" ]]; then
    ok "$label"
  else
    bad "$label"
  fi
}

write_executable() {
  local path="$1" content="$2"
  print -r -- "$content" > "$path"
  /bin/chmod 700 "$path"
}

setup_fixture() {
  FIXTURE=$(mktemp -d)
  mkdir -p "$FIXTURE/bin"
  {
    printf 'CLIPROXY_BASE_URL=%s\n' "$CC_URL"
    printf 'CLIPROXY_MGMT_KEY=mgmt-test\n'
    printf 'CLIPROXY_KEY_ADMIN=sk-admin-test\n'
    printf 'CLIPROXY_KEY_CC=%s\n' "$CC_KEY"
  } > "$FIXTURE/keys.env"
  write_executable "$FIXTURE/bin/nc" '#!/bin/sh
if [ -f "$CCP_FREE_READY_FILE" ]; then
  exit 0
fi
exit 1'
  write_executable "$FIXTURE/bin/launchctl" '#!/bin/sh
printf "%s\n" "$*" >> "$CCP_FREE_LAUNCH_LOG"
exit 0'
  write_executable "$FIXTURE/bin/sleep" '#!/bin/sh
printf "slept\n" >> "$CCP_FREE_SLEEP_LOG"
exit 0'
  write_executable "$FIXTURE/bin/claude" '#!/bin/sh
{
  printf "called=1\n"
  printf "cc_vendor=%s\n" "${CC_VENDOR-}"
  printf "base_url=%s\n" "${ANTHROPIC_BASE_URL-}"
  printf "auth_token=%s\n" "${ANTHROPIC_AUTH_TOKEN-}"
  printf "api_key=%s\n" "${ANTHROPIC_API_KEY-}"
  printf "model=%s\n" "${ANTHROPIC_MODEL-}"
  printf "fable_model=%s\n" "${ANTHROPIC_DEFAULT_FABLE_MODEL-}"
  printf "opus_model=%s\n" "${ANTHROPIC_DEFAULT_OPUS_MODEL-}"
  printf "sonnet_model=%s\n" "${ANTHROPIC_DEFAULT_SONNET_MODEL-}"
  printf "haiku_model=%s\n" "${ANTHROPIC_DEFAULT_HAIKU_MODEL-}"
  printf "custom_option=%s\n" "${ANTHROPIC_CUSTOM_MODEL_OPTION-}"
  printf "subagent_model=%s\n" "${CLAUDE_CODE_SUBAGENT_MODEL-}"
  printf "max_context_tokens=%s\n" "${CLAUDE_CODE_MAX_CONTEXT_TOKENS-}"
  printf "auto_compact_window=%s\n" "${CLAUDE_CODE_AUTO_COMPACT_WINDOW-}"
  printf "disable_compact=%s\n" "${DISABLE_COMPACT-}"
  printf "anthropic_fallback=%s\n" "${ANTHROPIC_FALLBACK_MODEL-}"
  printf "claude_code_fallback=%s\n" "${CLAUDE_CODE_FALLBACK_MODEL-}"
  index=1
  for arg in "$@"; do
    printf "arg%s=%s\n" "$index" "$arg"
    index=$((index + 1))
  done
} > "$CCP_FREE_CAPTURE_FILE"
exit 0'
}

invoke_wrapper() {
  (
    export CCP_FREE_KEYS_FILE="$FIXTURE/keys.env"
    export CCP_FREE_NC_BIN="$FIXTURE/bin/nc"
    export CCP_FREE_LAUNCHCTL_BIN="$FIXTURE/bin/launchctl"
    export CCP_FREE_SLEEP_BIN="$FIXTURE/bin/sleep"
    export CCP_FREE_CLAUDE_BIN="$FIXTURE/bin/claude"
    export CCP_FREE_READY_FILE="$FIXTURE/ready"
    export CCP_FREE_LAUNCH_LOG="$FIXTURE/launch.log"
    export CCP_FREE_SLEEP_LOG="$FIXTURE/sleep.log"
    export CCP_FREE_CAPTURE_FILE="$FIXTURE/capture.log"
    export ANTHROPIC_API_KEY='outer-paid-key'
    export ANTHROPIC_DEFAULT_FABLE_MODEL='outer-fable-model'
    export ANTHROPIC_DEFAULT_OPUS_MODEL='outer-opus-model'
    export ANTHROPIC_DEFAULT_SONNET_MODEL='outer-sonnet-model'
    export ANTHROPIC_DEFAULT_HAIKU_MODEL='outer-haiku-model'
    export CLAUDE_CODE_SUBAGENT_MODEL='outer-subagent-model'
    if [[ -n "${CCP_FREE_OUTER_MODEL-}" ]]; then
      export ANTHROPIC_MODEL="$CCP_FREE_OUTER_MODEL"
    fi
    source "$SRC"
    ccp-free --print probe
  ) > "$FIXTURE/output.log" 2>&1
  WRAPPER_STATUS=$?
}

teardown_fixture() {
  rm -R "$FIXTURE"
  FIXTURE=''
}

source "$SRC"
if [[ "$(ccp-list)" == *'ccp-free'* ]]; then
  ok 'ccp-list exposes ccp-free'
else
  bad 'ccp-list exposes ccp-free'
fi
if [[ "$(ccp-list)" == *'GLM-5.3-Flash'* ]]; then
  ok 'ccp-list identifies GLM-5.3-Flash free tier'
else
  bad 'ccp-list identifies GLM-5.3-Flash free tier'
fi

print -r -- '── keys preflight'
setup_fixture
/bin/rm "$FIXTURE/keys.env"
invoke_wrapper ready
assert_status 'missing keys file returns failure' 1
assert_output_contains 'missing keys file prints diagnostic' 'keys file is missing'
assert_file_absent 'missing keys file does not kickstart' "$FIXTURE/launch.log"
assert_file_absent 'missing keys file never invokes claude' "$FIXTURE/capture.log"
teardown_fixture

setup_fixture
print -r -- 'CLIPROXY_BASE_URL=http://127.0.0.1:8317' > "$FIXTURE/keys.env"
invoke_wrapper ready
assert_status 'keys file without CC key returns failure' 1
assert_output_contains 'incomplete keys file prints diagnostic' 'must define CLIPROXY_BASE_URL'
assert_file_absent 'incomplete keys file never invokes claude' "$FIXTURE/capture.log"
teardown_fixture

print -r -- '── relay discovery'
setup_fixture
invoke_wrapper ready
assert_status 'ready relay returns success' 0
assert_file_not_line 'ready relay does not kickstart' "$FIXTURE/launch.log" "kickstart gui/$UID/com.philip.cli-proxy-api"
assert_file_line 'ready relay invokes normal claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

print -r -- '── cold relay'
setup_fixture
invoke_wrapper ready
assert_status 'cold relay succeeds after kickstart' 0
assert_file_line 'only cli-proxy-api job is kicked' "$FIXTURE/launch.log" "kickstart gui/$UID/com.philip.cli-proxy-api"
assert_file_not_line 'fcc job is never kicked' "$FIXTURE/launch.log" 'ccp-free-fcc'
assert_file_line 'cold relay invokes normal claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

print -r -- '── startup timeout'
setup_fixture
invoke_wrapper success
assert_status 'startup timeout returns failure' 1
assert_output_contains 'timeout prints readiness diagnostic' 'did not become ready'
assert_file_line 'timeout kicks the relay job' "$FIXTURE/launch.log" "kickstart gui/$UID/com.philip.cli-proxy-api"
assert_line_count 'timeout uses the fixed 50 probes' "$FIXTURE/sleep.log" 50
assert_file_absent 'timeout never invokes claude' "$FIXTURE/capture.log"
teardown_fixture

print -r -- '── env pinning (default slots)'
setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready
assert_status 'pinned invocation returns success' 0
assert_file_line 'vendor marker is process-local free' "$FIXTURE/capture.log" 'cc_vendor=free'
assert_file_line 'base URL comes from keys.env' "$FIXTURE/capture.log" "base_url=$CC_URL"
assert_file_line 'auth token is the CC relay key' "$FIXTURE/capture.log" "auth_token=$CC_KEY"
assert_file_line 'Anthropic API key is removed' "$FIXTURE/capture.log" 'api_key='
assert_file_line 'main model is glm-free' "$FIXTURE/capture.log" 'model=glm-free'
assert_file_line 'FABLE model is hard-pinned glm-free' "$FIXTURE/capture.log" 'fable_model=glm-free'
assert_file_line 'OPUS model is hard-pinned glm-free' "$FIXTURE/capture.log" 'opus_model=glm-free'
assert_file_line 'SONNET model is hard-pinned glm-free' "$FIXTURE/capture.log" 'sonnet_model=glm-free'
assert_file_line 'HAIKU model is hard-pinned glm-free' "$FIXTURE/capture.log" 'haiku_model=glm-free'
assert_file_line 'custom thinking option is exposed' "$FIXTURE/capture.log" 'custom_option=glm-free(xhigh)'
assert_file_line 'subagent model is hard-pinned glm-free' "$FIXTURE/capture.log" 'subagent_model=glm-free'
assert_file_line 'context window matches GLM metadata' "$FIXTURE/capture.log" 'max_context_tokens=1048576'
assert_file_line 'auto compact requests the supported 1M window' "$FIXTURE/capture.log" 'auto_compact_window=1000000'
assert_file_line 'outer compact disable is removed' "$FIXTURE/capture.log" 'disable_compact='
assert_file_line 'paid fallback env is removed' "$FIXTURE/capture.log" 'anthropic_fallback='
assert_file_line 'Claude Code fallback env is removed' "$FIXTURE/capture.log" 'claude_code_fallback='
assert_file_line 'CLI model flag overrides settings' "$FIXTURE/capture.log" 'arg1=--model'
assert_file_line 'CLI model flag pins glm-free' "$FIXTURE/capture.log" 'arg2=glm-free'
assert_file_line 'WebSearch is disallowed' "$FIXTURE/capture.log" 'arg3=--disallowed-tools'
assert_file_line 'WebSearch tool name follows' "$FIXTURE/capture.log" 'arg4=WebSearch'
assert_file_line 'caller arguments are preserved' "$FIXTURE/capture.log" 'arg5=--print'
teardown_fixture

print -r -- '── outer model override passthrough'
setup_fixture
: > "$FIXTURE/ready"
CCP_FREE_OUTER_MODEL='ds-free' invoke_wrapper ready
assert_status 'outer override returns success' 0
assert_file_line 'outer model wins the main slot' "$FIXTURE/capture.log" 'model=ds-free'
assert_file_line 'outer model wins the CLI flag' "$FIXTURE/capture.log" 'arg2=ds-free'
assert_file_line 'vendor defaults still pin glm-free' "$FIXTURE/capture.log" 'fable_model=glm-free'
teardown_fixture

(( FAILURES == 0 ))
