#!/usr/bin/env zsh
# 本檔在契約測試底下：改完必跑（從 repo root）：zsh tests/ccp-free-wrapper.test.zsh
# 契約（2026-08-29 改版）：ccp-free 與 ccp-mix-gpt 共用 CLIProxyAPI :8317 的 free(max) chain：
# Cline GLM → AgentRouter GLM → Cline DeepSeek；offline FreeLLMAPI 不屬於有效備援。
set -u

ROOT="${0:A:h:h}"
SRC="$ROOT/shell/ccp-functions.sh"
MODEL='free(max)'
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

assert_output_not_contains() {
  local label="$1" needle="$2"
  if ! /usr/bin/grep -Fq -- "$needle" "$FIXTURE/output.log"; then
    ok "$label"
  else
    bad "$label"
  fi
}

assert_output_count() {
  local label="$1" needle="$2" expected="$3" actual
  actual=$(/usr/bin/grep -Fc -- "$needle" "$FIXTURE/output.log" || true)
  if [[ "$actual" == "$expected" ]]; then
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
  cat > "$FIXTURE/accounts.json" <<'JSON'
{
  "accounts": [
    {
      "accountId": "ACCOUNT-CANARY-ALPHA",
      "email": "alpha@example.test",
      "refreshToken": "REFRESH-CANARY-ALPHA",
      "metadata": {"secret": "NESTED-CANARY-ALPHA"},
      "status": "active",
      "modelCooldowns": {}
    },
    {
      "accountId": "ACCOUNT-CANARY-BETA",
      "email": "beta@example.test",
      "refreshToken": "REFRESH-CANARY-BETA",
      "metadata": {"secret": "NESTED-CANARY-BETA"},
      "status": "active",
      "modelCooldowns": {}
    },
    {
      "accountId": "ACCOUNT-CANARY-GAMMA",
      "email": "gamma@example.test",
      "refreshToken": "REFRESH-CANARY-GAMMA",
      "status": "active",
      "modelCooldowns": {}
    }
  ]
}
JSON
  cat > "$FIXTURE/request-logs.json" <<'JSON'
[
  {
    "completed": true,
    "finishedAt": "2026-08-29T20:30:00+08:00",
    "model": "z-ai/glm-5.3-flash"
  }
]
JSON
  cat > "$FIXTURE/config.yaml" <<'YAML'
openai-compatibility:
  - name: "cline-free-proxy"
    disabled: false
    models:
      - name: "free"
        alias: "free"
  - name: "freellmapi"
    disabled: true
    models:
      - name: "auto"
        alias: "free"
YAML
  write_executable "$FIXTURE/bin/nc" '#!/bin/sh
if [ -f "$CCP_FREE_READY_FILE" ]; then
  exit 0
fi
exit 1'
  write_executable "$FIXTURE/bin/launchctl" '#!/bin/sh
printf "%s\n" "$*" >> "$CCP_FREE_LAUNCH_LOG"
if [ "${CCP_FREE_LAUNCH_MODE:-success}" = ready ]; then
  : > "$CCP_FREE_READY_FILE"
fi
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
  printf "custom_name=%s\n" "${ANTHROPIC_CUSTOM_MODEL_OPTION_NAME-}"
  printf "custom_description=%s\n" "${ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION-}"
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
  local outer_model="${2-}"
  local wrapper="${3:-ccp-free}"
  (
    export CCP_FREE_LAUNCH_MODE="$mode"
    export CCP_FREE_KEYS_FILE="$FIXTURE/keys.env"
    export CCP_FREE_NC_BIN="$FIXTURE/bin/nc"
    export CCP_FREE_LAUNCHCTL_BIN="$FIXTURE/bin/launchctl"
    export CCP_FREE_SLEEP_BIN="$FIXTURE/bin/sleep"
    export CCP_FREE_CLAUDE_BIN="$FIXTURE/bin/claude"
    export CCP_FREE_READY_FILE="$FIXTURE/ready"
    export CCP_FREE_LAUNCH_LOG="$FIXTURE/launch.log"
    export CCP_FREE_SLEEP_LOG="$FIXTURE/sleep.log"
    export CCP_FREE_CAPTURE_FILE="$FIXTURE/capture.log"
    export CCP_FREE_ACCOUNTS_FILE="$FIXTURE/accounts.json"
    export CCP_FREE_REQUEST_LOG_FILE="$FIXTURE/request-logs.json"
    export CCP_FREE_CONFIG_FILE="$FIXTURE/config.yaml"
    export CCP_FREE_NOW='2026-08-29T21:00:00'
    export CCP_FREE_SINCE='2026-08-29T20:00:00'
    export ANTHROPIC_API_KEY='outer-paid-key'
    export ANTHROPIC_DEFAULT_FABLE_MODEL='outer-fable-model'
    export ANTHROPIC_DEFAULT_OPUS_MODEL='outer-opus-model'
    export ANTHROPIC_DEFAULT_SONNET_MODEL='outer-sonnet-model'
    export ANTHROPIC_DEFAULT_HAIKU_MODEL='outer-haiku-model'
    export CLAUDE_CODE_SUBAGENT_MODEL='outer-subagent-model'
    unset ANTHROPIC_MODEL ANTHROPIC_CUSTOM_MODEL_OPTION ANTHROPIC_CUSTOM_MODEL_OPTION_NAME \
      ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION CLAUDE_CODE_MAX_CONTEXT_TOKENS \
      CLAUDE_CODE_AUTO_COMPACT_WINDOW CLIPROXY_BASE_URL CLIPROXY_KEY_CC
    if [[ -n "$outer_model" ]]; then
      export ANTHROPIC_MODEL="$outer_model"
    fi
    source "$SRC"
    "$wrapper" --print probe
  ) > "$FIXTURE/output.log" 2>&1
  WRAPPER_STATUS=$?
}

teardown_fixture() {
  rm -R "$FIXTURE"
  FIXTURE=''
}

source "$SRC"
LIST_OUTPUT="$(ccp-list)"
if [[ "$LIST_OUTPUT" == *'ccp-free'* ]]; then
  ok 'ccp-list exposes ccp-free'
else
  bad 'ccp-list exposes ccp-free'
fi
if [[ "$LIST_OUTPUT" == *'Cline GLM → AgentRouter GLM → Cline DeepSeek'* ]]; then
  ok 'ccp-list identifies the current free chain'
else
  bad 'ccp-list identifies the current free chain'
fi
if [[ "$LIST_OUTPUT" != *'MiniMax'* && "$LIST_OUTPUT" != *'FreeLLMAPI'* ]]; then
  ok 'ccp-list omits inactive free-chain fallbacks'
else
  bad 'ccp-list omits inactive free-chain fallbacks'
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
: > "$FIXTURE/ready"
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
assert_output_contains 'free pool reports observed GLM service' '[ccp-free] 服務中：GLM 帳號池（free(max)）'
assert_output_contains 'free pool counts unused active GLM accounts' '3/3 帳號可用'
assert_output_contains 'free pool reports DeepSeek standby' '[ccp-free] 備援待命：DeepSeek — 3/3 帳號可用'
assert_output_contains 'free pool reports disabled FreeLLMAPI' '[ccp-free] FreeLLMAPI：已停用'
assert_output_not_contains 'healthy free pool omits warning marker' '⚠️'
assert_output_not_contains 'free pool output omits client key' "$CC_KEY"
assert_output_not_contains 'free pool output omits management key' 'mgmt-test'
assert_output_not_contains 'free pool output omits account email' 'alpha@example.test'
assert_output_not_contains 'free pool output omits secondary email' 'beta@example.test'
assert_output_not_contains 'free pool output omits unused account email' 'gamma@example.test'
assert_output_not_contains 'free pool output omits refresh token canary' 'REFRESH-CANARY'
assert_output_not_contains 'free pool output omits account ID canary' 'ACCOUNT-CANARY'
assert_output_not_contains 'free pool output omits nested canary' 'NESTED-CANARY'
assert_file_line 'vendor marker is process-local free' "$FIXTURE/capture.log" 'cc_vendor=free'
assert_file_line 'base URL comes from keys.env' "$FIXTURE/capture.log" "base_url=$CC_URL"
assert_file_line 'auth token is the CC relay key' "$FIXTURE/capture.log" "auth_token=$CC_KEY"
assert_file_line 'Anthropic API key is removed' "$FIXTURE/capture.log" 'api_key='
assert_file_line 'main model is free(max)' "$FIXTURE/capture.log" "model=$MODEL"
assert_file_line 'FABLE model is hard-pinned free(max)' "$FIXTURE/capture.log" "fable_model=$MODEL"
assert_file_line 'OPUS model is hard-pinned free(max)' "$FIXTURE/capture.log" "opus_model=$MODEL"
assert_file_line 'SONNET model is hard-pinned free(max)' "$FIXTURE/capture.log" "sonnet_model=$MODEL"
assert_file_line 'HAIKU model is hard-pinned free(max)' "$FIXTURE/capture.log" "haiku_model=$MODEL"
assert_file_line 'custom free-chain option is exposed' "$FIXTURE/capture.log" 'custom_option=free(max)'
assert_file_line 'custom option names the current free chain' "$FIXTURE/capture.log" 'custom_name=Free chain (Cline GLM → AgentRouter GLM → Cline DeepSeek)'
assert_file_line 'custom option describes the configured free chain' "$FIXTURE/capture.log" 'custom_description=Cline GLM first; AgentRouter GLM next; Cline DeepSeek last'
assert_file_line 'subagent model is hard-pinned free(max)' "$FIXTURE/capture.log" "subagent_model=$MODEL"
assert_file_line 'context window matches GLM metadata' "$FIXTURE/capture.log" 'max_context_tokens=1048576'
assert_file_line 'auto compact requests the supported 1M window' "$FIXTURE/capture.log" 'auto_compact_window=1000000'
assert_file_line 'outer compact disable is removed' "$FIXTURE/capture.log" 'disable_compact='
assert_file_line 'paid fallback env is removed' "$FIXTURE/capture.log" 'anthropic_fallback='
assert_file_line 'Claude Code fallback env is removed' "$FIXTURE/capture.log" 'claude_code_fallback='
assert_file_line 'CLI model flag overrides settings' "$FIXTURE/capture.log" 'arg1=--model'
assert_file_line 'CLI model flag pins free(max)' "$FIXTURE/capture.log" "arg2=$MODEL"
assert_file_line 'WebSearch is disallowed' "$FIXTURE/capture.log" 'arg3=--disallowed-tools'
assert_file_line 'WebSearch tool name follows' "$FIXTURE/capture.log" 'arg4=WebSearch'
assert_file_line 'caller arguments are preserved' "$FIXTURE/capture.log" 'arg5=--print'
teardown_fixture

print -r -- '── free pool status variants'
setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
invoke_wrapper ready
assert_status 'idle free pool still launches' 0
assert_output_contains 'idle free pool reports configured intent' '[ccp-free] 預計使用：GLM 帳號池（free(max)）— 無近期流量'
assert_file_line 'idle free pool invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
jq '.accounts[1].modelCooldowns["z-ai/glm-5.3-flash"] = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
invoke_wrapper ready
assert_status 'partial GLM cooldown still launches' 0
assert_output_contains 'partial GLM cooldown reports available count' '[ccp-free] ⚠️  GLM 帳號池：2/3 可用，其餘 cooldown／daily limit'
assert_file_line 'partial GLM cooldown invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
invoke_wrapper ready
assert_status 'stale GLM success still launches' 0
assert_output_not_contains 'stale GLM success does not override exhausted pool' '[ccp-free] 服務中：GLM 帳號池'
assert_output_contains 'stale GLM success predicts DeepSeek' '[ccp-free] 預計切換：DeepSeek — GLM 帳號池目前不可用'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
cat > "$FIXTURE/request-logs.json" <<'JSON'
[
  {
    "completed": false,
    "finishedAt": "2026-08-29T20:45:00+08:00",
    "model": "z-ai/glm-5.3-flash"
  }
]
JSON
invoke_wrapper ready
assert_status 'recent upstream failure still launches' 0
assert_output_contains 'recent upstream failure is visible' '[ccp-free] ⚠️  最近請求失敗：GLM'
assert_file_line 'recent upstream failure invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
cat > "$FIXTURE/request-logs.json" <<'JSON'
[
  {
    "completed": true,
    "finishedAt": "2026-08-29T20:10:00+08:00",
    "model": "z-ai/glm-5.3-flash"
  },
  {
    "completed": true,
    "finishedAt": "2026-08-29T20:20:00+08:00",
    "model": "z-ai/glm-5.3-flash(xhigh)"
  },
  {
    "completed": true,
    "finishedAt": "2026-08-29T20:30:00+08:00",
    "model": "poolside/laguna-s-2.1:free"
  }
]
JSON
invoke_wrapper ready
assert_status 'unrelated recent model still launches' 0
assert_output_contains 'unrelated model does not hide normalized GLM success' '[ccp-free] 服務中：GLM 帳號池（free(max)）'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
cat > "$FIXTURE/config.yaml" <<'YAML'
openai-compatibility:
  - name: "cline-free-proxy"
    disabled: true
    models:
      - name: "free"
        alias: "free"
  - name: "freellmapi"
    disabled: true
    models:
      - name: "auto"
        alias: "free"
YAML
invoke_wrapper ready
assert_status 'disabled free route still launches' 0
assert_output_contains 'disabled free route reports unavailable route' '[ccp-free] ⚠️  免費池 route 目前停用'
assert_output_not_contains 'disabled free route does not claim GLM service' '[ccp-free] 服務中：GLM 帳號池'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
cat > "$FIXTURE/config.yaml" <<'YAML'
openai-compatibility:
  - name: "cline-free-glm"
    priority: 30
    disabled: false
    models:
      - name: "glm-5.3-flash"
        alias: "free"
  - name: "agentrouter-glm"
    priority: 20
    disabled: false
    models:
      - name: "glm-5.3-flash"
        alias: "free"
  - name: "cline-free-ds"
    priority: 10
    disabled: false
    models:
      - name: "deepseek-v4-flash"
        alias: "free"
  - name: "cline-free-proxy"
    disabled: false
    models:
      - name: "glm-5.3-flash"
        alias: "cline-free-proxy-glm"
      - name: "deepseek-v4-flash"
        alias: "cline-free-proxy-ds"
YAML
invoke_wrapper ready
assert_status 'active free owners still launch' 0
assert_output_not_contains 'active free owners do not report disabled route' '免費池 route 目前停用'
assert_output_contains 'active free owners report the configured chain' '[ccp-free] free(max) route（config）：Cline GLM → AgentRouter GLM → Cline DeepSeek（上游健康未知）'
assert_output_contains 'configured chain marks upstream health as unknown' '上游健康未知'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
cat > "$FIXTURE/config.yaml" <<'YAML'
openai-compatibility:
  - name: "cline-free-ds"
    priority: 10
    disabled: false
    models:
      - name: "deepseek-v4-flash"
        alias: "free"
  - name: "agentrouter-glm"
    priority: 20
    disabled: false
    models:
      - name: "glm-5.3-flash"
        alias: "free"
  - name: "cline-free-glm"
    priority: 30
    disabled: false
    models:
      - name: "glm-5.3-flash"
        alias: "free"
  - name: "cline-free-proxy"
    disabled: false
    models:
      - name: "glm-5.3-flash"
        alias: "glm-free"
YAML
invoke_wrapper ready
assert_status 'priority-ordered route still launches' 0
assert_output_contains 'configured chain follows provider priority' '[ccp-free] free(max) route（config）：Cline GLM → AgentRouter GLM → Cline DeepSeek（上游健康未知）'
assert_output_contains 'GLM exhaustion reports AgentRouter as the next unknown stage' '[ccp-free] 預計切換：AgentRouter GLM（上游健康未知）— Cline GLM 帳號池目前不可用'
assert_output_not_contains 'GLM exhaustion does not skip AgentRouter to DeepSeek' '[ccp-free] 預計切換：DeepSeek — GLM 帳號池目前不可用'
assert_output_not_contains 'unknown AgentRouter stage does not claim no free source' '[ccp-free] ⚠️  免費池目前沒有可用來源'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
invoke_wrapper ready
assert_status 'GLM exhaustion still launches' 0
assert_output_contains 'GLM exhaustion predicts DeepSeek fallback' '[ccp-free] 預計切換：DeepSeek — GLM 帳號池目前不可用'
assert_file_line 'GLM exhaustion invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00" | (.accounts[].modelCooldowns["deepseek/deepseek-v4-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
invoke_wrapper ready
assert_status 'empty free pool still launches' 0
assert_output_contains 'empty free pool reports no usable source' '[ccp-free] ⚠️  免費池目前沒有可用來源'
assert_output_contains 'empty free pool prints diagnostic path' '細節排查：ccp-free-whoami / tail -f ~/.cline2api/service.log'
assert_file_line 'empty free pool invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
/bin/rm "$FIXTURE/accounts.json"
invoke_wrapper ready
assert_status 'missing status data still launches' 0
assert_output_contains 'missing status data prints yellow diagnostic' '[ccp-free] 無法查詢免費池狀態'
assert_file_line 'missing status data invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

print -r -- '── ccp-mix-gpt startup summary'
setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready '' ccp-mix-gpt
assert_status 'mixed wrapper returns success' 0
assert_output_contains 'mixed wrapper reports GPT main route' '[ccp-mix-gpt] Main：GPT-5.6 Sol'
assert_output_contains 'mixed wrapper reuses free pool summary' '[ccp-mix-gpt] 服務中：GLM 帳號池（free(max)）'
assert_output_count 'mixed wrapper reports GPT main once' '[ccp-mix-gpt] Main：GPT-5.6 Sol' 1
assert_output_count 'mixed wrapper queries free status once' '[ccp-mix-gpt] 服務中：GLM 帳號池（free(max)）' 1
assert_output_not_contains 'mixed wrapper output omits client key' "$CC_KEY"
assert_output_not_contains 'mixed wrapper output omits account email' 'alpha@example.test'
assert_output_not_contains 'mixed wrapper output omits refresh token canary' 'REFRESH-CANARY'
assert_output_not_contains 'mixed wrapper output omits account ID canary' 'ACCOUNT-CANARY'
assert_output_not_contains 'mixed wrapper output omits nested canary' 'NESTED-CANARY'
assert_file_line 'mixed wrapper keeps GPT main model' "$FIXTURE/capture.log" 'model=gpt-5.6-sol'
assert_file_line 'mixed wrapper keeps free Opus slot' "$FIXTURE/capture.log" 'opus_model=free(max)'
assert_file_line 'mixed wrapper keeps free subagent slot' "$FIXTURE/capture.log" 'subagent_model=free(max)'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
/bin/rm "$FIXTURE/accounts.json"
invoke_wrapper ready '' ccp-mix-gpt
assert_status 'mixed wrapper survives status failure' 0
assert_output_contains 'mixed wrapper prefixes status failure' '[ccp-mix-gpt] 無法查詢免費池狀態'
assert_file_line 'mixed status failure preserves GPT main' "$FIXTURE/capture.log" 'model=gpt-5.6-sol'
assert_file_line 'mixed status failure still invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready ds-free ccp-mix-gpt
assert_status 'mixed main override returns success' 0
assert_output_contains 'mixed main summary follows override' '[ccp-mix-gpt] Main：ds-free'
assert_output_not_contains 'mixed main summary does not claim default Sol' '[ccp-mix-gpt] Main：GPT-5.6 Sol'
assert_file_line 'mixed main override reaches claude' "$FIXTURE/capture.log" 'model=ds-free'
assert_file_line 'mixed main override preserves free Opus slot' "$FIXTURE/capture.log" 'opus_model=free(max)'
teardown_fixture

print -r -- '── outer model override passthrough'
setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready ds-free
assert_status 'outer override returns success' 0
assert_file_line 'outer model wins the main slot' "$FIXTURE/capture.log" 'model=ds-free'
assert_file_line 'outer model wins the CLI flag' "$FIXTURE/capture.log" 'arg2=ds-free'
assert_file_line 'vendor defaults still pin free(max)' "$FIXTURE/capture.log" "fable_model=$MODEL"
teardown_fixture

(( FAILURES == 0 ))
