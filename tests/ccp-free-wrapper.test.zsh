#!/usr/bin/env zsh
# 本檔在契約測試底下：改完必跑（從 repo root）：zsh tests/ccp-free-wrapper.test.zsh
# 契約（2026-09-11 改版）：ccp-free 與 ccp-mix-gpt 共用 CLIProxyAPI :8317 的 free(max) chain：
# WorkBuddy V4.1 → Cline GLM → Cline DeepSeek → AgentRouter GLM → B.AI GLM；offline FreeLLMAPI 不屬於有效備援。
set -u

ROOT="${0:A:h:h}"
SRC="$ROOT/shell/ccp-functions.sh"
MODEL='free(max)'
SMART_MODEL='free-smart(max)'
CC_KEY='test-cc-key'
WB_KEY='sk-cli2api-canary-key'
CC_URL='http://127.0.0.1:8317'
WB_URL='http://127.0.0.1:3010'
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
    printf 'CLI2API_BASE_URL=%s\n' "$WB_URL"
    printf 'CLI2API_API_KEY=%s\n' "$WB_KEY"
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
  cat > "$FIXTURE/workbuddy-accounts.json" <<'JSON'
{"data":[{"id":"acc_wb_test","provider":"workbuddy","name":"WorkBuddy Test","enabled":true,"status":"ready","ready":true,"runtime_state":"ready","quota":{"used":0,"total":350,"remaining":350,"unit":"credits","exceeded":false}}],"object":"list"}
JSON
  cat > "$FIXTURE/config.yaml" <<'YAML'
openai-compatibility:
  - name: "workbuddy-v41"
    priority: 40
    disabled: false
    models:
      - name: "workbuddy/deepseek-v4.1-flash"
        alias: "free"
  - name: "cline-free-glm"
    priority: 30
    disabled: false
    models:
      - name: "free-glm"
        alias: "free"
  - name: "cline-free-ds"
    priority: 27
    disabled: false
    models:
      - name: "free-ds"
        alias: "free"
  - name: "agentrouter-glm"
    priority: 25
    disabled: false
    models:
      - name: "agentrouter-glm"
        alias: "free"
  - name: "bai-glm"
    priority: 20
    disabled: false
    models:
      - name: "bai-glm"
        alias: "free"
  - name: "mimo-desktop-smart"
    priority: 90
    disabled: false
    models:
      - name: "mimo-x-pro"
        alias: "free-smart"
  - name: "cline-free-glm-smart"
    priority: 65
    disabled: false
    models:
      - name: "free-glm"
        alias: "free-smart"
  - name: "freellmapi"
    disabled: true
    models:
      - name: "auto"
        alias: "free"
YAML
  cat > "$FIXTURE/litellm.config.yaml" <<'YAML'
model_list:
  - model_name: bai-glm
    litellm_params:
      api_key: os.environ/BAI_KEY_1
      order: 1
  - model_name: bai-glm
    litellm_params:
      api_key: os.environ/BAI_KEY_2
      order: 2
YAML
  cat > "$FIXTURE/agentrouter.config.yaml" <<'YAML'
model_list:
  - model_name: agentrouter-glm
    litellm_params:
      api_key: os.environ/AGENTROUTER_KEY_1
      order: 1
  - model_name: agentrouter-glm
    litellm_params:
      api_key: os.environ/AGENTROUTER_KEY_2
      order: 2
YAML
  cat > "$FIXTURE/litellm-calls.jsonl" <<'JSONL'
{"ts":"2026-08-29T20:35:00+08:00","end_ts":"2026-08-29T20:35:06+08:00","status":"success","api_base":"https://api.b.ai/v1/","metadata":{"model_group":"bai-glm"},"messages":[{"content":"LITELLM-PROMPT-CANARY"}],"response":{"id":"LITELLM-RESPONSE-CANARY"}}
{"ts":"2026-08-29T20:40:00+08:00","end_ts":"2026-08-29T20:40:04+08:00","status":"failure","api_base":"https://agentrouter.org/v1/","metadata":{"model_group":"agentrouter-glm"},"error":"LITELLM-ERROR-CANARY"}
JSONL
  write_executable "$FIXTURE/bin/nc" '#!/bin/sh
if [ -f "$CCP_FREE_READY_FILE" ]; then
  exit 0
fi
exit 1'
  write_executable "$FIXTURE/bin/curl" '#!/bin/sh
printf "%s\n" "$*" >> "$CCP_FREE_CURL_LOG"
out="/dev/null"
url=""
first=1
for arg in "$@"; do
  if [ "$first" = "0" ] && [ "${prev-}" = "-o" ]; then
    out="$arg"
  fi
  prev="$arg"
  first=0
  url="$arg"
done
if [ -n "${CCP_FREE_CURL_FAIL_URL:-}" ] && [ "$url" = "$CCP_FREE_CURL_FAIL_URL" ]; then
  exit 7
fi
case "$url" in
  *"/health/liveliness") exit 0 ;;
  *"$CCP_FREE_WORKBUDDY_HEALTH_URL")
    if [ "${CCP_FREE_WB_HEALTH:-up}" = "up" ]; then
      if [ "$out" = "/dev/null" ] || [ -z "$out" ]; then
        printf "%s" "{\"ok\":true,\"service\":\"cli2api\",\"providers\":[\"workbuddy\"]}"
      else
        printf "%s" "{\"ok\":true,\"service\":\"cli2api\",\"providers\":[\"workbuddy\"]}" > "$out"
      fi
      exit 0
    fi
    exit 7 ;;
  *"$CCP_FREE_WORKBUDDY_ACCOUNTS_URL")
    case "${CCP_FREE_WB_ACCOUNTS:-ready}" in
      ready)  content="$(cat "$CCP_FREE_WORKBUDDY_ACCOUNTS_FILE")" ;;
      noready) content="{\"data\":[{\"id\":\"acc_wb_test\",\"provider\":\"workbuddy\",\"status\":\"ready\",\"ready\":false,\"runtime_state\":\"stopped\",\"quota\":{\"used\":0,\"total\":350,\"remaining\":0,\"unit\":\"credits\"}}],\"object\":\"list\"}" ;;
      empty)  content="{\"data\":[],\"object\":\"list\"}" ;;
      *)      content="$(cat "$CCP_FREE_WORKBUDDY_ACCOUNTS_FILE")" ;;
    esac
    if [ "$out" = "/dev/null" ] || [ -z "$out" ]; then
      printf "%s" "$content"
    else
      printf "%s" "$content" > "$out"
    fi
    exit 0 ;;
  *) exit 7 ;;
esac'
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
  local binary_mode="${4:-direct}"
  (
    export CCP_FREE_LAUNCH_MODE="$mode"
    export CCP_FREE_KEYS_FILE="$FIXTURE/keys.env"
    export CCP_FREE_NC_BIN="$FIXTURE/bin/nc"
    export CCP_FREE_LAUNCHCTL_BIN="$FIXTURE/bin/launchctl"
    export CCP_FREE_SLEEP_BIN="$FIXTURE/bin/sleep"
    if [[ "$binary_mode" == "selector" ]]; then
      unset CCP_FREE_CLAUDE_BIN
      export CC_CLAUDE_BIN="$FIXTURE/bin/claude"
    else
      export CCP_FREE_CLAUDE_BIN="$FIXTURE/bin/claude"
      unset CC_CLAUDE_BIN
    fi
    export CCP_FREE_READY_FILE="$FIXTURE/ready"
    export CCP_FREE_LAUNCH_LOG="$FIXTURE/launch.log"
    export CCP_FREE_SLEEP_LOG="$FIXTURE/sleep.log"
    export CCP_FREE_CAPTURE_FILE="$FIXTURE/capture.log"
    export CCP_FREE_ACCOUNTS_FILE="$FIXTURE/accounts.json"
    export CCP_FREE_REQUEST_LOG_FILE="$FIXTURE/request-logs.json"
    export CCP_FREE_CONFIG_FILE="$FIXTURE/config.yaml"
    export CCP_FREE_LITELLM_CONFIG_FILE="$FIXTURE/litellm.config.yaml"
    export CCP_FREE_AGENTROUTER_CONFIG_FILE="$FIXTURE/agentrouter.config.yaml"
    export CCP_FREE_LITELLM_LOG_FILE="$FIXTURE/litellm-calls.jsonl"
    export CCP_FREE_CURL_BIN="$FIXTURE/bin/curl"
    export CCP_FREE_CURL_LOG="$FIXTURE/curl.log"
    export CCP_FREE_STEPFUN_PROBE=off
    export CCP_FREE_BAI_LIVELINESS_URL='http://127.0.0.1:8000/health/liveliness'
    export CCP_FREE_AGENTROUTER_LIVELINESS_URL='http://127.0.0.1:8002/health/liveliness'
    export CCP_FREE_WORKBUDDY_HEALTH_URL="$WB_URL/health"
    export CCP_FREE_WORKBUDDY_ACCOUNTS_URL="$WB_URL/api/accounts"
    export CCP_FREE_WORKBUDDY_ACCOUNTS_FILE="$FIXTURE/workbuddy-accounts.json"
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
if [[ "$LIST_OUTPUT" == *'WorkBuddy V4.1 → Cline GLM → Cline DeepSeek → AgentRouter GLM → B.AI GLM'* ]]; then
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

setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready '' ccp-free selector
assert_status 'selector fallback returns success' 0
assert_file_line 'selector fallback invokes CC_CLAUDE_BIN' "$FIXTURE/capture.log" 'called=1'
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
assert_output_contains 'WorkBuddy primary leaves Cline GLM on standby' '[ccp-free] 備援待命：Cline GLM — 3/3 帳號可用；最近 success 2026-08-29T20:30:00+08:00'
assert_output_contains 'B.AI reports passive local and observed status' '[ccp-free] B.AI GLM：gateway up；2 deployments；最近 success 2026-08-29T20:35:06+08:00；quota unknown'
assert_output_contains 'AgentRouter reports passive local and observed status' '[ccp-free] AgentRouter GLM：gateway up；2 deployments；最近 failure 2026-08-29T20:40:04+08:00；quota／cooldown unknown'
assert_output_contains 'free pool reports Cline DeepSeek standby' '[ccp-free] 備援待命：Cline DeepSeek — 3/3 帳號可用；最近 unknown'
assert_file_line 'B.AI checks only local liveliness' "$FIXTURE/curl.log" '-fsS --max-time 1 -o /dev/null http://127.0.0.1:8000/health/liveliness'
assert_file_line 'AgentRouter checks only local liveliness' "$FIXTURE/curl.log" '-fsS --max-time 1 -o /dev/null http://127.0.0.1:8002/health/liveliness'
assert_line_count 'passive summary performs four local probes' "$FIXTURE/curl.log" 4
assert_file_line 'WorkBuddy accounts probe sends its bearer credential' "$FIXTURE/curl.log" "-fsS --max-time 2 -H Authorization: Bearer $WB_KEY $WB_URL/api/accounts"
assert_output_contains 'free pool reports disabled FreeLLMAPI' '[ccp-free] FreeLLMAPI：已停用'
assert_output_contains 'WorkBuddy reports the sidecar and account health' '[ccp-free] WorkBuddy V4.1：sidecar up；1/1 帳號 ready；350/350 credits remaining；model route 未探活'
assert_output_contains 'WorkBuddy is the first owner so predicts itself' '[ccp-free] 預計使用：WorkBuddy V4.1（free(max)）'
assert_output_contains 'smart chain reports the capability-ordered route' '[ccp-free] free-smart(max) route（config）：MiMo X Pro → Cline GLM（上游健康未知）'
assert_output_not_contains 'healthy free pool omits warning marker' '⚠️'
assert_output_not_contains 'free pool output omits client key' "$CC_KEY"
assert_output_not_contains 'free pool output omits management key' 'mgmt-test'
assert_output_not_contains 'workbuddy summary omits CLI2API key' "$WB_KEY"
assert_output_not_contains 'free pool output omits account email' 'alpha@example.test'
assert_output_not_contains 'free pool output omits secondary email' 'beta@example.test'
assert_output_not_contains 'free pool output omits unused account email' 'gamma@example.test'
assert_output_not_contains 'free pool output omits refresh token canary' 'REFRESH-CANARY'
assert_output_not_contains 'free pool output omits account ID canary' 'ACCOUNT-CANARY'
assert_output_not_contains 'free pool output omits nested canary' 'NESTED-CANARY'
assert_output_not_contains 'free pool output omits LiteLLM prompt canary' 'LITELLM-PROMPT-CANARY'
assert_output_not_contains 'free pool output omits LiteLLM response canary' 'LITELLM-RESPONSE-CANARY'
assert_output_not_contains 'free pool output omits LiteLLM error canary' 'LITELLM-ERROR-CANARY'
assert_file_line 'vendor marker is process-local free' "$FIXTURE/capture.log" 'cc_vendor=free'
assert_file_line 'base URL comes from keys.env' "$FIXTURE/capture.log" "base_url=$CC_URL"
assert_file_line 'auth token is the CC relay key' "$FIXTURE/capture.log" "auth_token=$CC_KEY"
assert_file_line 'Anthropic API key is removed' "$FIXTURE/capture.log" 'api_key='
assert_file_line 'main model is free-smart(max)' "$FIXTURE/capture.log" "model=$SMART_MODEL"
assert_file_line 'FABLE model is hard-pinned free-smart(max)' "$FIXTURE/capture.log" "fable_model=$SMART_MODEL"
assert_file_line 'OPUS model is hard-pinned free(max)' "$FIXTURE/capture.log" "opus_model=$MODEL"
assert_file_line 'SONNET model is hard-pinned free(max)' "$FIXTURE/capture.log" "sonnet_model=$MODEL"
assert_file_line 'HAIKU model is hard-pinned free(max)' "$FIXTURE/capture.log" "haiku_model=$MODEL"
assert_file_line 'custom free-chain option keeps the pooled alias' "$FIXTURE/capture.log" 'custom_option=free(max)'
assert_file_line 'custom option names the current free chain' "$FIXTURE/capture.log" 'custom_name=Free chain (WorkBuddy V4.1 → Cline GLM → Cline DeepSeek → AgentRouter GLM → B.AI GLM)'
assert_file_line 'custom option describes the configured free chain' "$FIXTURE/capture.log" 'custom_description=WorkBuddy V4.1 first; Cline GLM next; Cline DeepSeek next; AgentRouter GLM next; B.AI GLM last'
assert_file_line 'subagent model is hard-pinned free(max)' "$FIXTURE/capture.log" "subagent_model=$MODEL"
assert_file_line 'context window stays under the swe2 empty-body threshold' "$FIXTURE/capture.log" 'max_context_tokens=480000'
assert_file_line 'auto compact window matches the context ceiling' "$FIXTURE/capture.log" 'auto_compact_window=480000'
assert_file_line 'outer compact disable is removed' "$FIXTURE/capture.log" 'disable_compact='
assert_file_line 'paid fallback env is removed' "$FIXTURE/capture.log" 'anthropic_fallback='
assert_file_line 'Claude Code fallback env is removed' "$FIXTURE/capture.log" 'claude_code_fallback='
assert_file_line 'CLI model flag overrides settings' "$FIXTURE/capture.log" 'arg1=--model'
assert_file_line 'CLI model flag pins free-smart(max)' "$FIXTURE/capture.log" "arg2=$SMART_MODEL"
assert_file_line 'WebSearch is disallowed' "$FIXTURE/capture.log" 'arg3=--disallowed-tools'
assert_file_line 'WebSearch tool name follows' "$FIXTURE/capture.log" 'arg4=WebSearch'
assert_file_line 'caller arguments are preserved' "$FIXTURE/capture.log" 'arg5=--print'
teardown_fixture

print -r -- '── WorkBuddy V4.1 health'
setup_fixture
: > "$FIXTURE/ready"
export CCP_FREE_WB_HEALTH=down
invoke_wrapper ready
unset CCP_FREE_WB_HEALTH
assert_status 'workbuddy sidecar down still launches' 0
assert_output_contains 'sidecar down reports WorkBuddy unavailable' '[ccp-free] WorkBuddy V4.1：sidecar down（不可用）'
assert_output_contains 'sidecar down predicts the next free leg' '[ccp-free] 預計切換：Cline GLM'
assert_output_not_contains 'sidecar down does not claim WorkBuddy in use' '[ccp-free] 預計使用：WorkBuddy V4.1'
assert_file_line 'sidecar down still invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
export CCP_FREE_WB_HEALTH=up
export CCP_FREE_WB_ACCOUNTS=noready
invoke_wrapper ready
unset CCP_FREE_WB_HEALTH CCP_FREE_WB_ACCOUNTS
assert_status 'workbuddy with no ready account still launches' 0
assert_output_contains 'sidecar up but no ready account reports unavailable' 'sidecar up；0/1 帳號 ready（不可用）'
assert_output_contains 'no ready account predicts the next free leg' '[ccp-free] 預計切換：Cline GLM'
assert_file_line 'no ready account still invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
cat > "$FIXTURE/config.yaml" <<'YAML'
openai-compatibility:
  - name: "cline-free-glm"
    priority: 30
    disabled: false
    models:
      - name: "free-glm"
        alias: "free"
  - name: "agentrouter-glm"
    priority: 25
    disabled: false
    models:
      - name: "agentrouter-glm"
        alias: "free"
  - name: "bai-glm"
    priority: 20
    disabled: false
    models:
      - name: "bai-glm"
        alias: "free"
  - name: "cline-free-ds"
    priority: 27
    disabled: false
    models:
      - name: "free-ds"
        alias: "free"
YAML
invoke_wrapper ready
assert_status 'workbuddy-free chain still launches' 0
assert_output_not_contains 'chain without WorkBuddy omits the WorkBuddy line' '[ccp-free] WorkBuddy V4.1：'
assert_output_contains 'chain without WorkBuddy keeps the Cline GLM service line' '[ccp-free] 服務中：GLM 帳號池（free(max)）'
assert_file_line 'chain without WorkBuddy still invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
export CCP_FREE_WB_HEALTH=down
invoke_wrapper ready
unset CCP_FREE_WB_HEALTH
assert_status 'workbuddy down with GLM exhausted still launches' 0
assert_output_contains 'workbuddy down reports WorkBuddy unavailable' '[ccp-free] WorkBuddy V4.1：sidecar down（不可用）'
assert_output_contains 'workbuddy down plus GLM exhaustion predicts Cline DeepSeek' '[ccp-free] 預計切換：Cline DeepSeek — WorkBuddy V4.1 與 Cline GLM 目前不可用'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00" | (.accounts[].modelCooldowns["deepseek/deepseek-v4-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
export CCP_FREE_WB_HEALTH=down
invoke_wrapper ready
unset CCP_FREE_WB_HEALTH
assert_status 'workbuddy and both Cline pools down still launches' 0
assert_output_contains 'exhausted primary legs predict AgentRouter' '[ccp-free] 預計切換：AgentRouter GLM（上游健康未知）— WorkBuddy V4.1 與 Cline 帳號池目前不可用'
assert_output_not_contains 'exhausted DeepSeek is not predicted as available' '[ccp-free] 預計切換：Cline DeepSeek'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
cat > "$FIXTURE/config.yaml" <<'YAML'
openai-compatibility:
  - name: "workbuddy-v41"
    priority: 40
    disabled: false
    models:
      - name: "workbuddy/deepseek-v4.1-flash"
        alias: "free"
YAML
invoke_wrapper ready
assert_status 'single-owner WorkBuddy chain still launches' 0
assert_output_contains 'single-owner WorkBuddy is recognized as first' '[ccp-free] 預計使用：WorkBuddy V4.1（free(max)）'
assert_output_not_contains 'healthy single-owner WorkBuddy avoids false empty-pool claim' '[ccp-free] ⚠️  免費池目前沒有可用來源'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00" | (.accounts[].modelCooldowns["deepseek/deepseek-v4-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
cat > "$FIXTURE/config.yaml" <<'YAML'
openai-compatibility:
  - name: "bai-glm"
    priority: 25
    disabled: false
    models:
      - name: "bai-glm"
        alias: "free"
  - name: "agentrouter-glm"
    priority: 20
    disabled: false
    models:
      - name: "agentrouter-glm"
        alias: "free"
  - name: "cline-free-ds"
    priority: 10
    disabled: false
    models:
      - name: "free-ds"
        alias: "free"
YAML
invoke_wrapper ready
assert_status 'chain without Cline GLM still launches' 0
assert_output_contains 'chain without Cline GLM predicts its first configured owner' '[ccp-free] 預計切換：B.AI GLM（上游健康未知）— Cline GLM 帳號池目前不可用'
assert_output_not_contains 'configured external owners prevent a false empty-pool claim' '[ccp-free] ⚠️  免費池目前沒有可用來源'
teardown_fixture

print -r -- '── free pool status variants'
setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
invoke_wrapper ready
assert_status 'idle free pool still launches' 0
assert_output_contains 'idle free pool keeps WorkBuddy as configured intent' '[ccp-free] 預計使用：WorkBuddy V4.1（free(max)）'
assert_file_line 'idle free pool invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
export CCP_FREE_CURL_FAIL_URL='http://127.0.0.1:8002/health/liveliness'
invoke_wrapper ready
unset CCP_FREE_CURL_FAIL_URL
assert_status 'one local gateway down still launches' 0
assert_output_contains 'B.AI remains up when AgentRouter gateway is down' '[ccp-free] B.AI GLM：gateway up；2 deployments'
assert_output_contains 'AgentRouter local gateway failure is visible' '[ccp-free] AgentRouter GLM：gateway down；2 deployments'
assert_file_line 'gateway failure still invokes claude' "$FIXTURE/capture.log" 'called=1'
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
assert_output_contains 'stale GLM success leaves Cline DeepSeek on standby' '[ccp-free] 備援待命：Cline DeepSeek — 3/3 帳號可用；最近 unknown'
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
assert_output_contains 'unrelated model does not hide normalized GLM standby health' '[ccp-free] 備援待命：Cline GLM — 3/3 帳號可用；最近 success 2026-08-29T20:20:00+08:00'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
cat > "$FIXTURE/request-logs.json" <<'JSON'
[
  {
    "completed": true,
    "finishedAt": "2026-08-29T20:50:00+08:00",
    "model": "deepseek/deepseek-v4-flash"
  }
]
JSON
invoke_wrapper ready
assert_status 'DeepSeek-only recent data still launches' 0
assert_output_contains 'DeepSeek-only data keeps its standby timestamp aligned' '[ccp-free] 備援待命：Cline DeepSeek — 3/3 帳號可用；最近 success 2026-08-29T20:50:00+08:00'
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
  - name: "bai-glm"
    priority: 25
    disabled: false
    models:
      - name: "bai-glm"
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
assert_output_contains 'active free owners report the configured chain' '[ccp-free] free(max) route（config）：Cline GLM → B.AI GLM → AgentRouter GLM → Cline DeepSeek（上游健康未知）'
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
  - name: "bai-glm"
    priority: 25
    disabled: false
    models:
      - name: "bai-glm"
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
assert_output_contains 'configured chain follows provider priority' '[ccp-free] free(max) route（config）：Cline GLM → B.AI GLM → AgentRouter GLM → Cline DeepSeek（上游健康未知）'
assert_output_contains 'GLM exhaustion reports B.AI as the next configured leg' '[ccp-free] 預計切換：B.AI GLM（上游健康未知）— Cline GLM 帳號池目前不可用'
assert_output_not_contains 'GLM exhaustion does not skip the GLM pool' '[ccp-free] 預計切換：AgentRouter GLM（上游健康未知）— Cline GLM 帳號池目前不可用'
assert_output_not_contains 'unknown B.AI stage does not claim no free source' '[ccp-free] ⚠️  免費池目前沒有可用來源'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
invoke_wrapper ready
assert_status 'GLM exhaustion still launches' 0
assert_output_contains 'GLM exhaustion keeps WorkBuddy primary' '[ccp-free] 預計使用：WorkBuddy V4.1（free(max)）'
assert_output_contains 'GLM exhaustion leaves Cline DeepSeek on standby' '[ccp-free] 備援待命：Cline DeepSeek — 3/3 帳號可用；最近 unknown'
assert_file_line 'GLM exhaustion invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
print -r -- '[]' > "$FIXTURE/request-logs.json"
jq '(.accounts[].modelCooldowns["z-ai/glm-5.3-flash"]) = "2026-08-30T12:00:00+08:00" | (.accounts[].modelCooldowns["deepseek/deepseek-v4-flash"]) = "2026-08-30T12:00:00+08:00"' "$FIXTURE/accounts.json" > "$FIXTURE/accounts.tmp" && mv "$FIXTURE/accounts.tmp" "$FIXTURE/accounts.json"
invoke_wrapper ready
assert_status 'empty free pool still launches' 0
assert_output_contains 'exhausted Cline pools keep WorkBuddy primary' '[ccp-free] 預計使用：WorkBuddy V4.1（free(max)）'
assert_output_contains 'exhausted Cline pools report the GLM warning' '[ccp-free] ⚠️  Cline GLM 備援目前不可用'
assert_output_contains 'exhausted Cline pools report the DeepSeek warning' '[ccp-free] ⚠️  Cline DeepSeek 備援目前不可用'
assert_output_not_contains 'healthy WorkBuddy prevents a false empty-pool claim' '[ccp-free] ⚠️  免費池目前沒有可用來源'
assert_output_contains 'empty free pool prints diagnostic path' '細節排查：ccp-free-whoami / tail -f ~/.cline2api/service.log'
assert_file_line 'empty free pool invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
/bin/rm "$FIXTURE/accounts.json"
invoke_wrapper ready
assert_status 'missing status data still launches' 0
assert_output_contains 'missing status data prints yellow diagnostic' '[ccp-free] 無法查詢免費池狀態'
assert_output_contains 'missing Cline data still reports B.AI status' '[ccp-free] B.AI GLM：gateway up；2 deployments；最近 success 2026-08-29T20:35:06+08:00；quota unknown'
assert_output_contains 'missing Cline data still reports AgentRouter status' '[ccp-free] AgentRouter GLM：gateway up；2 deployments；最近 failure 2026-08-29T20:40:04+08:00；quota／cooldown unknown'
assert_file_line 'missing status data invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

print -r -- '── ccp-mix-gpt startup summary'
setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready '' ccp-mix-gpt selector
assert_status 'mixed wrapper selector fallback returns success' 0
assert_output_contains 'mixed wrapper reports GPT main route' '[ccp-mix-gpt] Main：GPT-6 Astra'
assert_output_contains 'mixed wrapper reuses WorkBuddy-first free pool summary' '[ccp-mix-gpt] 預計使用：WorkBuddy V4.1（free(max)）'
assert_output_count 'mixed wrapper reports GPT main once' '[ccp-mix-gpt] Main：GPT-6 Astra' 1
assert_output_count 'mixed wrapper queries WorkBuddy status once' '[ccp-mix-gpt] 預計使用：WorkBuddy V4.1（free(max)）' 1
assert_output_not_contains 'mixed wrapper output omits client key' "$CC_KEY"
assert_output_not_contains 'mixed wrapper output omits account email' 'alpha@example.test'
assert_output_not_contains 'mixed wrapper output omits refresh token canary' 'REFRESH-CANARY'
assert_output_not_contains 'mixed wrapper output omits account ID canary' 'ACCOUNT-CANARY'
assert_output_not_contains 'mixed wrapper output omits nested canary' 'NESTED-CANARY'
assert_file_line 'mixed wrapper keeps GPT main model' "$FIXTURE/capture.log" 'model=gpt-6-astra'
assert_file_line 'mixed wrapper pins Astra effort flag' "$FIXTURE/capture.log" 'arg1=--effort'
assert_file_line 'mixed wrapper pins Astra to medium' "$FIXTURE/capture.log" 'arg2=medium'
assert_file_line 'mixed wrapper keeps model flag after effort' "$FIXTURE/capture.log" 'arg3=--model'
assert_file_line 'mixed wrapper passes Astra after model flag' "$FIXTURE/capture.log" 'arg4=gpt-6-astra'
assert_file_line 'mixed wrapper marks GPT main for startup convergence' "$FIXTURE/capture.log" 'cc_vendor=mix-gpt'
assert_file_line 'mixed wrapper keeps free Opus slot' "$FIXTURE/capture.log" 'opus_model=free(max)'
assert_file_line 'mixed wrapper keeps free subagent slot' "$FIXTURE/capture.log" 'subagent_model=free(max)'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
/bin/rm "$FIXTURE/accounts.json"
invoke_wrapper ready '' ccp-mix-gpt
assert_status 'mixed wrapper survives status failure' 0
assert_output_contains 'mixed wrapper prefixes status failure' '[ccp-mix-gpt] 無法查詢免費池狀態'
assert_file_line 'mixed status failure preserves GPT main' "$FIXTURE/capture.log" 'model=gpt-6-astra'
assert_file_line 'mixed status failure still invokes claude' "$FIXTURE/capture.log" 'called=1'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready ds-free ccp-mix-gpt
assert_status 'mixed main override returns success' 0
assert_output_contains 'mixed main summary follows override' '[ccp-mix-gpt] Main：ds-free'
assert_output_not_contains 'mixed main summary does not claim default Sol' '[ccp-mix-gpt] Main：GPT-6 Sol'
assert_file_line 'mixed main override reaches claude' "$FIXTURE/capture.log" 'model=ds-free'
assert_file_line 'mixed non-GPT override keeps the generic vendor marker' "$FIXTURE/capture.log" 'cc_vendor=mix'
assert_file_line 'mixed main override preserves free Opus slot' "$FIXTURE/capture.log" 'opus_model=free(max)'
teardown_fixture

print -r -- '── ccp-mix-sol rollback'
setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready '' ccp-mix-sol selector
assert_status 'mix-sol wrapper returns success' 0
assert_output_contains 'mix-sol wrapper reports Sol main route' '[ccp-mix-gpt] Main：GPT-6 Sol'
assert_file_line 'mix-sol pins main to sol' "$FIXTURE/capture.log" 'model=gpt-6-sol'
assert_file_line 'mix-sol pins Sol effort flag' "$FIXTURE/capture.log" 'arg1=--effort'
assert_file_line 'mix-sol pins Sol to xhigh' "$FIXTURE/capture.log" 'arg2=xhigh'
assert_file_line 'mix-sol keeps model flag after effort' "$FIXTURE/capture.log" 'arg3=--model'
assert_file_line 'mix-sol passes Sol after model flag' "$FIXTURE/capture.log" 'arg4=gpt-6-sol'
assert_file_line 'mix-sol pins FABLE to sol' "$FIXTURE/capture.log" 'fable_model=gpt-6-sol'
assert_file_line 'mix-sol keeps GPT vendor marker' "$FIXTURE/capture.log" 'cc_vendor=mix-gpt'
assert_file_line 'mix-sol keeps free Opus slot' "$FIXTURE/capture.log" 'opus_model=free(max)'
assert_file_line 'mix-sol keeps free subagent slot' "$FIXTURE/capture.log" 'subagent_model=free(max)'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready '' ccp-mix-sol
assert_status 'mix-sol direct mode returns success' 0
assert_file_line 'mix-sol overrides outer FABLE preset' "$FIXTURE/capture.log" 'fable_model=gpt-6-sol'
teardown_fixture

setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready '' ccp-mix-gpt selector
assert_file_line 'bare mix-gpt ignores mix-sol FABLE preset' "$FIXTURE/capture.log" 'fable_model=outer-fable-model'
teardown_fixture

print -r -- '── outer model override passthrough'
setup_fixture
: > "$FIXTURE/ready"
invoke_wrapper ready ds-free
assert_status 'outer override returns success' 0
assert_file_line 'outer model wins the main slot' "$FIXTURE/capture.log" 'model=ds-free'
assert_file_line 'outer model wins the CLI flag' "$FIXTURE/capture.log" 'arg2=ds-free'
assert_file_line 'vendor defaults still pin free-smart(max)' "$FIXTURE/capture.log" "fable_model=$SMART_MODEL"
teardown_fixture

print -r -- '── DeepSeek weight probe (8h cache)'
WEIGHT_DIR="$(mktemp -d)"
mkdir -p "$WEIGHT_DIR/bin"
cat > "$WEIGHT_DIR/config.yaml" <<'YAML'
  - name: "cline-free-proxy"
    priority: 30
    base-url: "http://127.0.0.1:3457/v1"
    api-key-entries:
      - api-key: "stub-key"
    models:
      - name: "deepseek/deepseek-v4-flash"
        alias: "ds-flash"
YAML
cat > "$WEIGHT_DIR/bin/curl" <<'STUB'
#!/usr/bin/env zsh
print -r -- "called" >> "$CCP_FREE_CURL_LOG"
print -r -- '{"model":"deepseek/deepseek-v4-flash-0731","provider":"Reka"}'
STUB
cat > "$WEIGHT_DIR/bin/curl-fail" <<'STUB'
#!/usr/bin/env zsh
print -r -- "called" >> "$CCP_FREE_CURL_LOG"
exit 22
STUB
chmod +x "$WEIGHT_DIR/bin/curl" "$WEIGHT_DIR/bin/curl-fail"

probe_weight() {
  local cache="$1" curl_bin="$2" now_epoch="$3"
  WEIGHT_OUTPUT=$(
    CCP_FREE_WEIGHT_CACHE_FILE="$cache" \
    CCP_FREE_CURL_BIN="$WEIGHT_DIR/bin/$curl_bin" \
    CCP_FREE_CURL_LOG="$WEIGHT_DIR/curl.log" \
    CCP_FREE_CONFIG_FILE="$WEIGHT_DIR/config.yaml" \
    CCP_FREE_NOW_EPOCH="$now_epoch" \
    zsh -c "source '$SRC' && _ccp_free_ds_weight ccp-free" 2>&1
  )
}

assert_weight() {
  local label="$1" needle="$2"
  if [[ "$WEIGHT_OUTPUT" == *"$needle"* ]]; then
    ok "$label"
  else
    bad "$label"
    print -ru2 -- "    expected substring: $needle"
    print -ru2 -- "    actual: $WEIGHT_OUTPUT"
  fi
}

: > "$WEIGHT_DIR/curl.log"
probe_weight "$WEIGHT_DIR/cache" curl 1000000
assert_weight 'cold probe reports the dated build' 'deepseek/deepseek-v4-flash-0731'
assert_weight 'cold probe marks it as fresh' '剛剛探測'
assert_line_count 'cold probe hits the network once' "$WEIGHT_DIR/curl.log" 1

rm -f "$WEIGHT_DIR/curl.log"
probe_weight "$WEIGHT_DIR/cache" curl 1025200
assert_weight 'warm cache still reports the build' 'deepseek/deepseek-v4-flash-0731'
assert_weight 'warm cache reports its age' '420 分鐘前探測'
assert_file_absent 'warm cache skips the network entirely' "$WEIGHT_DIR/curl.log"

: > "$WEIGHT_DIR/curl.log"
probe_weight "$WEIGHT_DIR/cache" curl 1032400
assert_weight 'expired cache re-probes' '剛剛探測'
assert_line_count 'expired cache hits the network once' "$WEIGHT_DIR/curl.log" 1

: > "$WEIGHT_DIR/curl.log"
probe_weight "$WEIGHT_DIR/cache" curl-fail 1100000
assert_weight 'failed probe falls back to the stale value' 'deepseek/deepseek-v4-flash-0731'
assert_weight 'failed probe discloses the staleness' '探測失敗，沿用'

: > "$WEIGHT_DIR/curl.log"
probe_weight "$WEIGHT_DIR/absent-cache" curl-fail 1100000
assert_weight 'failed probe with no cache reports unknown' '未知（探測失敗）'

rm -R "$WEIGHT_DIR"

print -r -- '── standalone ccp-free-whoami'
setup_fixture
: > "$FIXTURE/ready"
WHOAMI_OUTPUT=$(
  CCP_FREE_KEYS_FILE="$FIXTURE/keys.env" \
  CCP_FREE_ACCOUNTS_FILE="$FIXTURE/accounts.json" \
  CCP_FREE_REQUEST_LOG_FILE="$FIXTURE/request-logs.json" \
  CCP_FREE_CONFIG_FILE="$FIXTURE/config.yaml" \
  CCP_FREE_LITELLM_CONFIG_FILE="$FIXTURE/litellm.config.yaml" \
  CCP_FREE_AGENTROUTER_CONFIG_FILE="$FIXTURE/agentrouter.config.yaml" \
  CCP_FREE_LITELLM_LOG_FILE="$FIXTURE/litellm-calls.jsonl" \
  CCP_FREE_CURL_BIN="$FIXTURE/bin/curl" \
  CCP_FREE_CURL_LOG="$FIXTURE/curl.log" \
  CCP_FREE_STEPFUN_PROBE=off \
  CCP_FREE_BAI_LIVELINESS_URL='http://127.0.0.1:8000/health/liveliness' \
  CCP_FREE_AGENTROUTER_LIVELINESS_URL='http://127.0.0.1:8002/health/liveliness' \
  CCP_FREE_WORKBUDDY_HEALTH_URL="$WB_URL/health" \
  CCP_FREE_WORKBUDDY_ACCOUNTS_URL="$WB_URL/api/accounts" \
  CCP_FREE_WORKBUDDY_ACCOUNTS_FILE="$FIXTURE/workbuddy-accounts.json" \
  CCP_FREE_NOW='2026-08-29T21:00:00' \
  CCP_FREE_SINCE='2026-08-29T20:00:00' \
  zsh -c "source '$SRC' && ccp-free-whoami ccp-free-whoami" 2>&1
)
if [[ "$WHOAMI_OUTPUT" == *'[ccp-free-whoami] WorkBuddy V4.1：sidecar up；1/1 帳號 ready；350/350 credits remaining；model route 未探活'* ]]; then
  ok 'standalone whoami reads the WorkBuddy status via keys.env'
else
  bad 'standalone whoami reads the WorkBuddy status via keys.env'
  print -ru2 -- "    actual: $WHOAMI_OUTPUT"
fi
if [[ "$WHOAMI_OUTPUT" != *"$WB_KEY"* ]]; then
  ok 'standalone whoami omits the CLI2API key'
else
  bad 'standalone whoami omits the CLI2API key'
fi
if [[ "$WHOAMI_OUTPUT" == *'[ccp-free-whoami] free(max) route（config）：WorkBuddy V4.1 → Cline GLM → Cline DeepSeek → AgentRouter GLM → B.AI GLM'* ]]; then
  ok 'standalone whoami reports the WorkBuddy-first chain'
else
  bad 'standalone whoami reports the WorkBuddy-first chain'
fi
teardown_fixture

(( FAILURES == 0 ))
