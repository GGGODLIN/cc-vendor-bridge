#!/usr/bin/env zsh
# 本檔在契約測試底下：改完必跑（從 repo root）：zsh tests/ccp-free-wrapper.test.zsh
set -u

ROOT="${0:A:h:h}"
SRC="$ROOT/shell/ccp-functions.sh"
MODEL='open_router/stealth/ox-alpha'
TOKEN='test-proxy-token'
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
  mkdir -p "$FIXTURE/config" "$FIXTURE/bin"
  print -r -- "$TOKEN" > "$FIXTURE/config/proxy-token"
  /bin/chmod 600 "$FIXTURE/config/proxy-token"
  write_executable "$FIXTURE/bin/nc" '#!/bin/sh
if [ -f "$CCP_FREE_READY_FILE" ]; then
  exit 0
fi
exit 1'
  write_executable "$FIXTURE/bin/lsof" '#!/bin/sh
if [ "${CCP_FREE_LSOF_MODE:-match}" = rogue ]; then
  printf "%s\n" "${CCP_FREE_ROGUE_PID:-9999}"
else
  printf "%s\n" "${CCP_FREE_JOB_PID:-4242}"
fi
exit 0'
  write_executable "$FIXTURE/bin/launchctl" '#!/bin/sh
printf "%s\n" "$*" >> "$CCP_FREE_LAUNCH_LOG"
if [ "$1" = print ]; then
  if [ -f "$CCP_FREE_JOB_STATE_FILE" ]; then
    printf "state = running\n"
    printf "pid = %s\n" "$CCP_FREE_JOB_PID"
    exit 0
  fi
  exit 113
fi
case "${CCP_FREE_LAUNCH_MODE:-success}" in
  ready)
    : > "$CCP_FREE_READY_FILE"
    : > "$CCP_FREE_JOB_STATE_FILE"
    exit 0
    ;;
  failure)
    exit 17
    ;;
esac
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
  local mode="$1"
  (
    export CCP_FREE_CONFIG_DIR="$FIXTURE/config"
    export CCP_FREE_NC_BIN="$FIXTURE/bin/nc"
    export CCP_FREE_LSOF_BIN="$FIXTURE/bin/lsof"
    export CCP_FREE_LAUNCHCTL_BIN="$FIXTURE/bin/launchctl"
    export CCP_FREE_JOB_STATE_FILE="$FIXTURE/job.state"
    export CCP_FREE_JOB_PID=4242
    export CCP_FREE_SLEEP_BIN="$FIXTURE/bin/sleep"
    export CCP_FREE_CLAUDE_BIN="$FIXTURE/bin/claude"
    export CCP_FREE_READY_FILE="$FIXTURE/ready"
    export CCP_FREE_LAUNCH_LOG="$FIXTURE/launch.log"
    export CCP_FREE_SLEEP_LOG="$FIXTURE/sleep.log"
    export CCP_FREE_CAPTURE_FILE="$FIXTURE/capture.log"
    export CCP_FREE_LAUNCH_MODE="$mode"
    export ANTHROPIC_MODEL='outer-paid-model'
    export ANTHROPIC_API_KEY='outer-paid-key'
    export ANTHROPIC_AUTH_TOKEN='outer-auth-token'
    export ANTHROPIC_DEFAULT_FABLE_MODEL='outer-fable-model'
    export ANTHROPIC_DEFAULT_OPUS_MODEL='outer-opus-model'
    export ANTHROPIC_DEFAULT_SONNET_MODEL='outer-sonnet-model'
    export ANTHROPIC_DEFAULT_HAIKU_MODEL='outer-haiku-model'
    export CLAUDE_CODE_SUBAGENT_MODEL='outer-subagent-model'
    export ANTHROPIC_FALLBACK_MODEL='claude-opus-4-6'
    export CLAUDE_CODE_FALLBACK_MODEL='claude-opus-4-6'
    export DISABLE_COMPACT=1
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
if [[ "$(ccp-list)" == *'OpenRouter Ox Alpha'* ]]; then
  ok 'ccp-list identifies OpenRouter Ox Alpha'
else
  bad 'ccp-list identifies OpenRouter Ox Alpha'
fi

print -r -- '── token preflight'
setup_fixture
/bin/rm "$FIXTURE/config/proxy-token"
invoke_wrapper ready
assert_status 'missing token returns failure' 1
assert_output_contains 'missing token prints diagnostic' 'proxy token is missing'
assert_file_absent 'missing token does not kickstart' "$FIXTURE/launch.log"
assert_file_absent 'missing token never invokes claude' "$FIXTURE/capture.log"
teardown_fixture

setup_fixture
/bin/chmod 644 "$FIXTURE/config/proxy-token"
invoke_wrapper ready
assert_status 'weak token mode returns failure' 1
assert_output_contains 'weak token mode prints diagnostic' 'must use mode 600'
assert_file_absent 'weak token mode does not kickstart' "$FIXTURE/launch.log"
assert_file_absent 'weak token mode never invokes claude' "$FIXTURE/capture.log"
teardown_fixture

print -r -- '── server identity'
setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper success
assert_status 'ready port without running job returns failure' 1
assert_output_contains 'not-running job prints diagnostic' 'dedicated launchd job is not running'
assert_file_absent 'not-running job never invokes claude' "$FIXTURE/capture.log"
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
: > "$FIXTURE/job.state"
CCP_FREE_LSOF_MODE=rogue invoke_wrapper success
assert_status 'rogue listener owner returns failure' 1
assert_output_contains 'rogue listener prints diagnostic' 'listener owner does not match'
assert_file_absent 'rogue listener never invokes claude' "$FIXTURE/capture.log"
unset CCP_FREE_LSOF_MODE
teardown_fixture

print -r -- '── server already ready'
setup_fixture
: > "$FIXTURE/ready"
: > "$FIXTURE/job.state"
invoke_wrapper success
assert_status 'ready server returns success' 0
assert_file_not_line 'ready server does not kickstart' "$FIXTURE/launch.log" "kickstart gui/$UID/com.gggodlin.ccp-free-fcc"
assert_file_line 'ready server invokes normal claude' "$FIXTURE/capture.log" 'called=1'
assert_file_line 'free marker is process-local' "$FIXTURE/capture.log" 'cc_vendor=free'
assert_file_line 'FCC endpoint is fixed' "$FIXTURE/capture.log" 'base_url=http://127.0.0.1:18082'
assert_file_line 'proxy token is used' "$FIXTURE/capture.log" "auth_token=$TOKEN"
assert_file_line 'Anthropic API key is removed' "$FIXTURE/capture.log" 'api_key='
assert_file_line 'main model is live model' "$FIXTURE/capture.log" "model=$MODEL"
assert_file_line 'FABLE model is live model' "$FIXTURE/capture.log" "fable_model=$MODEL"
assert_file_line 'OPUS model is live model' "$FIXTURE/capture.log" "opus_model=$MODEL"
assert_file_line 'SONNET model is live model' "$FIXTURE/capture.log" "sonnet_model=$MODEL"
assert_file_line 'HAIKU model is live model' "$FIXTURE/capture.log" "haiku_model=$MODEL"
assert_file_line 'subagent model is live model' "$FIXTURE/capture.log" "subagent_model=$MODEL"
assert_file_line 'context window matches Ox metadata' "$FIXTURE/capture.log" 'max_context_tokens=1048576'
assert_file_line 'auto compact requests the supported 1M window' "$FIXTURE/capture.log" 'auto_compact_window=1000000'
assert_file_line 'outer compact disable is removed' "$FIXTURE/capture.log" 'disable_compact='
assert_file_line 'paid fallback env is removed' "$FIXTURE/capture.log" 'anthropic_fallback='
assert_file_line 'Claude Code fallback env is removed' "$FIXTURE/capture.log" 'claude_code_fallback='
assert_file_line 'CLI model flag overrides settings' "$FIXTURE/capture.log" 'arg1=--model'
assert_file_line 'CLI model flag pins live model' "$FIXTURE/capture.log" "arg2=$MODEL"
assert_file_line 'caller arguments are preserved' "$FIXTURE/capture.log" 'arg3=--print'
teardown_fixture

print -r -- '── server not started'
setup_fixture
invoke_wrapper ready
assert_status 'cold server returns success after kickstart' 0
assert_file_line 'only dedicated job is kicked' "$FIXTURE/launch.log" "kickstart gui/$UID/com.gggodlin.ccp-free-fcc"
assert_file_line 'cold server invokes normal claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

print -r -- '── startup timeout'
setup_fixture
invoke_wrapper success
assert_status 'startup timeout returns failure' 1
assert_file_line 'timeout kickstarts dedicated job' "$FIXTURE/launch.log" "kickstart gui/$UID/com.gggodlin.ccp-free-fcc"
assert_output_contains 'timeout prints readiness diagnostic' 'did not become ready'
assert_line_count 'timeout uses the fixed 50 probes' "$FIXTURE/sleep.log" 50
assert_file_absent 'timeout never invokes claude' "$FIXTURE/capture.log"
teardown_fixture

print -r -- '── startup failure'
setup_fixture
invoke_wrapper failure
assert_status 'launch failure returns failure' 1
assert_file_line 'launch failure targets dedicated job' "$FIXTURE/launch.log" "kickstart gui/$UID/com.gggodlin.ccp-free-fcc"
assert_output_contains 'launch failure prints diagnostic' 'failed to kickstart'
assert_file_absent 'launch failure does not wait' "$FIXTURE/sleep.log"
assert_file_absent 'launch failure never invokes claude' "$FIXTURE/capture.log"
teardown_fixture

(( FAILURES == 0 ))
