#!/usr/bin/env zsh
# cc-vendor-bridge — Path 0 zsh functions
#
# Each ccp-* function opens Claude Code pointed at a different vendor's
# Anthropic-native endpoint, using a subshell so env vars don't leak.
#
# Setup:
#   1. cp shell/secrets.example ~/.zsh_secrets && chmod 600 ~/.zsh_secrets
#   2. Edit ~/.zsh_secrets, fill in your keys
#   3. Add to ~/.zshrc:
#        [[ -f ~/.zsh_secrets ]] && source ~/.zsh_secrets
#        source /path/to/cc-vendor-bridge/shell/ccp-functions.sh
#   4. exec zsh
#
# Usage:
#   ccp-deepseek                # default DeepSeek session
#   ccp-deepseek -c             # continue last DeepSeek session
#   ccp-kimi /path/to/proj      # open in specific dir
#
# Per-call override (env vars use ${VAR:-default} so caller can pre-set):
#   ANTHROPIC_MODEL=deepseek-v4-flash ccp-deepseek -p "task"  # main = flash
#   CLAUDE_CODE_EFFORT_LEVEL=low ccp-deepseek                  # less thinking
#   CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-pro ccp-deepseek    # subagent = pro
#
# Hardcoded (NOT overridable, since they bind the function to a specific vendor):
#   - ANTHROPIC_BASE_URL  (vendor endpoint)
#   - ANTHROPIC_AUTH_TOKEN (sourced from secrets)
#   - CC_VENDOR            (vendor marker for hook Defense 0)

# ===== DeepSeek V4-Pro =====
# Source: https://api-docs.deepseek.com/zh-cn/quick_start/agent_integrations/claude_code
ccp-deepseek() {
  if [[ -z "$DEEPSEEK_API_KEY" ]]; then
    echo "ccp-deepseek: DEEPSEEK_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi

  # Health check: ensure proxy daemon is up (rewrites tool_choice for caveat 9 fix).
  # If not listening, kickstart via launchd and wait up to 5s for ready.
  if ! /usr/bin/nc -z 127.0.0.1 9091 2>/dev/null; then
    echo "[ccp-deepseek] proxy not listening, kickstarting launchd service..." >&2
    launchctl kickstart "gui/$UID/com.gggodlin.cc-vendor-bridge-proxy" 2>/dev/null
    local i=0
    while (( i < 50 )); do
      /usr/bin/nc -z 127.0.0.1 9091 2>/dev/null && break
      sleep 0.1; ((i++))
    done
    if (( i >= 50 )); then
      print -P "%F{red}[ccp-deepseek] proxy did not become ready in 5s — aborting (check ~/Library/Logs/cc-vendor-bridge-proxy.log)%f" >&2
      return 1
    fi
  fi

  (
    export CC_VENDOR=deepseek
    export ANTHROPIC_BASE_URL=http://127.0.0.1:9091
    export ANTHROPIC_AUTH_TOKEN=$DEEPSEEK_API_KEY
    export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-deepseek-v4-pro}
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-deepseek-v4-pro}
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-deepseek-v4-pro}
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-deepseek-v4-flash}
    export CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL:-deepseek-v4-flash}
    export CLAUDE_CODE_EFFORT_LEVEL=${CLAUDE_CODE_EFFORT_LEVEL:-max}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    export DISABLE_COMPACT=${DISABLE_COMPACT:-1}
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1000000}
    claude "$@"
  )
}

# DISABLED: MOONSHOT_API_KEY not configured
# ===== Moonshot Kimi K2.5 (international PAYG) =====
# Source: https://platform.kimi.ai/docs/guide/agent-support
# ccp-kimi() {
#   if [[ -z "$MOONSHOT_API_KEY" ]]; then
#     echo "ccp-kimi: MOONSHOT_API_KEY not set. See shell/secrets.example" >&2
#     return 1
#   fi
#   (
#     export CC_VENDOR=kimi
#     export ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic
#     export ANTHROPIC_AUTH_TOKEN=$MOONSHOT_API_KEY
#     export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-kimi-k2.5}
#     export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
#     claude "$@"
#   )
# }

# DISABLED: MOONSHOT_CN_API_KEY not configured
# ===== Moonshot Kimi 大陸 PAYG =====
# Source: https://platform.kimi.com/docs/guide/agent-support
# ccp-kimi-cn() {
#   if [[ -z "$MOONSHOT_CN_API_KEY" ]]; then
#     echo "ccp-kimi-cn: MOONSHOT_CN_API_KEY not set. See shell/secrets.example" >&2
#     return 1
#   fi
#   (
#     export CC_VENDOR=kimi-cn
#     export ANTHROPIC_BASE_URL=https://api.moonshot.cn/anthropic
#     export ANTHROPIC_AUTH_TOKEN=$MOONSHOT_CN_API_KEY
#     export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-kimi-k2.5}
#     export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
#     claude "$@"
#   )
# }

# ===== Zhipu GLM (z.ai international) =====
# Source: https://docs.z.ai/scenario-example/develop-tools/claude
ccp-glm() {
  if [[ -z "$ZAI_API_KEY" ]]; then
    echo "ccp-glm: ZAI_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export CC_VENDOR=glm
    export ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
    export ANTHROPIC_AUTH_TOKEN=$ZAI_API_KEY
    export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-GLM-5.1}
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-GLM-5.1}
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-GLM-4.7}
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-GLM-4.7-Flash}
    export CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL:-GLM-4.7}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    claude "$@"
  )
}

# DISABLED: BIGMODEL_API_KEY not configured
# ===== Zhipu GLM 大陸 (bigmodel) =====
# Source: https://docs.bigmodel.cn/cn/guide/develop/claude
# ccp-glm-cn() {
#   if [[ -z "$BIGMODEL_API_KEY" ]]; then
#     echo "ccp-glm-cn: BIGMODEL_API_KEY not set. See shell/secrets.example" >&2
#     return 1
#   fi
#   (
#     export CC_VENDOR=glm-cn
#     export ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
#     export ANTHROPIC_AUTH_TOKEN=$BIGMODEL_API_KEY
#     export ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-GLM-4.7}
#     export ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-GLM-4.7}
#     export ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-GLM-4.5-Air}
#     export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
#     export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
#     claude "$@"
#   )
# }

# ===== Xiaomi MiMo V2.5-Pro Token Plan (Singapore subscription) =====
# Source: https://token-plan-sgp.xiaomimimo.com/
ccp-mimo() {
  if [[ -z "$MIMO_SUB_API_KEY" ]]; then
    echo "ccp-mimo: MIMO_SUB_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export CC_VENDOR=mimo
    export ANTHROPIC_BASE_URL=https://token-plan-sgp.xiaomimimo.com/anthropic
    export ANTHROPIC_AUTH_TOKEN=$MIMO_SUB_API_KEY
    export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-mimo-v2.5-pro}
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-mimo-v2.5-pro}
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-mimo-v2.5-pro}
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-mimo-v2.5-pro}
    export DISABLE_COMPACT=${DISABLE_COMPACT:-1}
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1100000}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    claude "$@"
  )
}

# ===== Xiaomi MiMo V2.5-Pro (international PAYG) =====
# Source: https://platform.xiaomimimo.com/
ccp-mimo-payg() {
  if [[ -z "$MIMO_API_KEY" ]]; then
    echo "ccp-mimo-payg: MIMO_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export CC_VENDOR=mimo-payg
    export ANTHROPIC_BASE_URL=https://api.xiaomimimo.com/anthropic
    export ANTHROPIC_AUTH_TOKEN=$MIMO_API_KEY
    export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-mimo-v2.5-pro}
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-mimo-v2.5-pro}
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-mimo-v2.5-pro}
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-mimo-v2.5-pro}
    export DISABLE_COMPACT=${DISABLE_COMPACT:-1}
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1100000}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    claude "$@"
  )
}

# ===== Rapid-MLX local (auto-detect model from running serve) =====
# Source: https://github.com/raullenchai/Rapid-MLX
#
# 取代舊 ccp-qwen-3.6-35B / ccp-qwen-3.6-27B（model 名硬寫死）。
# 行為：connect 到 RAPID_MLX_LOCAL_URL（預設 http://127.0.0.1:8002），
# 透過 /v1/models 自動撈當下 serve 的 model alias，把 ANTHROPIC_MODEL 跟
# 三條 default model（opus/sonnet/haiku）跟 subagent model 全部指過去。
# 換 model 不用改 wrapper — kill 後 `rapid-mlx serve <new-alias> --port 8002 ...` 再呼叫即可。
#
# 2026-05-20 verdict (Qwen3.6-35B-A3B + patched vllm_mlx, local-model-bench
# FINDINGS §8.6): tool-call streaming + multi-turn agent flow 跑得起來。前提是
# vllm_mlx 必須打過 patches/vllm_mlx-tool-content-flatten.patch（extract_multimodal_content
# tool 分支對 list content flatten 成 str），否則 Qwen3.6 嚴格版 chat_template 會在 turn 2
# raise TemplateError 'Unexpected item type in content.'。
#
# 啟動 serve 範例：
#   rapid-mlx serve qwen3.6-35b --no-thinking --tool-call-parser qwen3_coder_xml \
#     --enable-auto-tool-choice --port 8002 --api-key local
#
# Override:
#   LOCAL_MODEL=qwen3.6-35b ccp-local                # 強制 model id（跳過 auto-detect）
#   RAPID_MLX_LOCAL_URL=http://127.0.0.1:8004 ccp-local   # 跑在別的 port
#   ANTHROPIC_MODEL=mlx-community/Qwen3.6-35B-A3B-4bit ccp-local   # 用長 id
ccp-local() {
  local url="${RAPID_MLX_LOCAL_URL:-http://127.0.0.1:8002}"
  local v1="${url%/v1}/v1"
  if ! curl -sf -m 3 "$v1/models" -H "Authorization: Bearer local" >/dev/null 2>&1; then
    echo "ccp-local: 連不到 $v1 (rapid-mlx serve 沒起?)" >&2
    echo "    Start it first, e.g.:" >&2
    echo "      rapid-mlx serve qwen3.6-35b --no-thinking --tool-call-parser qwen3_coder_xml --enable-auto-tool-choice --port 8002 --api-key local" >&2
    return 1
  fi
  local model="${LOCAL_MODEL}"
  if [[ -z "$model" ]]; then
    model=$(curl -sf -m 3 "$v1/models" -H "Authorization: Bearer local" 2>/dev/null | python3 -c '
import json, sys
try:
    data = json.load(sys.stdin).get("data", [])
except Exception:
    sys.exit(2)
ids = [m.get("id", "") for m in data if isinstance(m, dict)]
short = [i for i in ids if i and "/" not in i]
print((short or ids or [""])[0])
')
  fi
  if [[ -z "$model" ]]; then
    echo "ccp-local: 無法從 $v1/models 解析 model id (設 LOCAL_MODEL=... 強制)" >&2
    return 1
  fi
  # Auto-detect n_ctx via llama-server /props (llama.cpp native; rapid-mlx 沒這 endpoint、會走 fallback)
  local props_url="${url%/v1}/props"
  local n_ctx
  n_ctx=$(curl -sf -m 3 "$props_url" -H "Authorization: Bearer local" 2>/dev/null | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
    print(d.get("default_generation_settings", {}).get("n_ctx", 0))
except Exception:
    print(0)
' 2>/dev/null)
  if [[ -z "$n_ctx" || "$n_ctx" == "0" ]]; then
    n_ctx=200000  # safe fallback (rapid-mlx 或無 /props 的 server)
    echo "ccp-local: /props 沒回 n_ctx、用 fallback $n_ctx" >&2
  fi
  echo "ccp-local: model=$model n_ctx=$n_ctx" >&2
  (
    export CC_VENDOR=rapid-mlx
    export ANTHROPIC_BASE_URL="$url"
    # `not-needed` 是 rapid-mlx 時期 placeholder (rapid-mlx 不校驗 api key)。
    # llama-server `--api-key local` 會校驗 → 401 Invalid API Key。改 default 為 `local` 跟
    # opencode/aider-local 約定對齊；user 可用 ANTHROPIC_AUTH_TOKEN 自帶 token 蓋掉。
    export ANTHROPIC_AUTH_TOKEN="${ANTHROPIC_AUTH_TOKEN:-local}"
    export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-$model}"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL:-$model}"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="${ANTHROPIC_DEFAULT_SONNET_MODEL:-$model}"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-$model}"
    export CLAUDE_CODE_SUBAGENT_MODEL="${CLAUDE_CODE_SUBAGENT_MODEL:-$model}"
    # Auto-detect ctx: 蓋掉 CC 預設 Opus [1m] suffix、用 server 真實 n_ctx
    # 舊註：rapid-mlx 時期故意不設、靠 CC fallback 200K。
    # 現況：llama.cpp 不 reject、CC 默認加 [1m] (1M)、超出 server 真 n_ctx 會 truncate。
    # 解法：查 /props 拿真 n_ctx 寫進 CC。AutoCompact 仍開、~90% 觸發、server 留 10% buffer
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS="${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-$n_ctx}"
    export API_TIMEOUT_MS="${API_TIMEOUT_MS:-3000000}"
    export ENABLE_TOOL_SEARCH="${ENABLE_TOOL_SEARCH:-auto}"
    # 起手用 sonnet alias：CC 對 Opus alias 強制套 [1m]/1M mode、ignore CLAUDE_CODE_MAX_CONTEXT_TOKENS。
    # Sonnet alias 走 200K tier default、display 乾淨無 [1m]、跟 CLAUDE_CODE_MAX_CONTEXT_TOKENS 設定 align（≥ 200K 都安全）。
    # User 仍可在 TUI 內 /model opus 切回 (會看到 [1m] / 1M、知道 trade-off 自己決定)。
    # User 若 args 已含 --model 由 user 決定優先。
    local has_model_arg=0
    for arg in "$@"; do
      [[ "$arg" == "--model" || "$arg" == --model=* ]] && has_model_arg=1
    done
    if (( has_model_arg )); then
      claude "$@"
    else
      claude --model sonnet "$@"
    fi
  )
}

# DISABLED: DASHSCOPE_INTL_API_KEY not configured
# ===== Alibaba Qwen Max (international Singapore PAYG) =====
# Source: https://www.alibabacloud.com/help/en/model-studio/claude-code
# Defaults to qwen3-max because thinking mode only works on Max series
# ccp-qwen() {
#   if [[ -z "$DASHSCOPE_INTL_API_KEY" ]]; then
#     echo "ccp-qwen: DASHSCOPE_INTL_API_KEY not set. See shell/secrets.example" >&2
#     return 1
#   fi
#   (
#     export CC_VENDOR=qwen
#     export ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/apps/anthropic
#     export ANTHROPIC_AUTH_TOKEN=$DASHSCOPE_INTL_API_KEY
#     export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-qwen3-max}
#     export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
#     claude "$@"
#   )
# }

# DISABLED: QWEN_CODING_PLAN_KEY not configured
# ===== Alibaba Qwen Coding Plan (subscription, separate quota) =====
# ccp-qwen-coding() {
#   if [[ -z "$QWEN_CODING_PLAN_KEY" ]]; then
#     echo "ccp-qwen-coding: QWEN_CODING_PLAN_KEY not set. See shell/secrets.example" >&2
#     return 1
#   fi
#   (
#     export CC_VENDOR=qwen-coding
#     export ANTHROPIC_BASE_URL=https://coding-intl.dashscope.aliyuncs.com/apps/anthropic
#     export ANTHROPIC_AUTH_TOKEN=$QWEN_CODING_PLAN_KEY
#     export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-qwen3-coder-next}
#     export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
#     claude "$@"
#   )
# }

# ===== Helper: list available functions =====
ccp-list() {
  cat <<EOF
Available cc-vendor-bridge functions:

  ccp-deepseek      → DeepSeek V4-Pro / V4-Flash
  ccp-glm           → Zhipu GLM-5.1 / 4.7-Flash (z.ai intl)
  ccp-mimo          → Xiaomi MiMo V2.5-Pro Token Plan (Singapore subscription)
  ccp-mimo-payg     → Xiaomi MiMo V2.5-Pro (intl PAYG)
  ccp-local         → Rapid-MLX local (auto-detect model via /v1/models on :8002, Apple Silicon, zero cost)
                      Override: LOCAL_MODEL=... / RAPID_MLX_LOCAL_URL=...
                      Needs vllm_mlx tool-content-flatten patch for Qwen3.6 strict template (see local-model-bench FINDINGS §8.6)

  ccp-resume        → 互動 picker 選 prior session resume，自動 dispatch 對應 vendor
                      (workaround caveat 11: 跨 vendor resume 會炸 thinking signature)

Disabled (API key not configured):
  ccp-kimi / ccp-kimi-cn / ccp-glm-cn / ccp-qwen / ccp-qwen-coding

Each opens a Claude Code session backed by that vendor.
Pass any args you'd pass to 'claude' (e.g. '-c', '/path/to/proj').

Per-call env override (use \${VAR:-default} pattern):
  ANTHROPIC_MODEL=deepseek-v4-flash ccp-deepseek -p "task"
  CLAUDE_CODE_EFFORT_LEVEL=low ccp-deepseek
  CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-pro ccp-deepseek

To switch mid-conversation: Ctrl-D to exit, then run a different ccp-* function.
EOF
}

# ===== Helper: resume any prior CC session, auto-dispatch by vendor =====
# Lists all sessions for the current project (cwd-based), lets you pick via fzf,
# detects which vendor wrote it (from jsonl assistant message model), then
# dispatches to the corresponding ccp-* function (or plain `claude` for
# Anthropic-backed sessions).
#
# Workaround for caveat 11: cross-vendor /resume crashes on thinking signature
# mismatch. ccp-resume warns + asks confirm before crossing vendors.
ccp-resume() {
  command -v fzf >/dev/null || { echo "ccp-resume: requires fzf" >&2; return 1; }
  command -v jq  >/dev/null || { echo "ccp-resume: requires jq"  >&2; return 1; }

  local project_hash="$(pwd | sed 's|^/|-|; s|/|-|g')"
  local proj_dir="$HOME/.claude/projects/$project_hash"
  [[ -d "$proj_dir" ]] || { echo "ccp-resume: no CC sessions for $(pwd)" >&2; return 1; }

  local lines=()
  local f sid model snippet mtime
  # zsh glob qualifier: `om` = newest first (counterintuitively NOT `Om`).
  # `o` with `m` directly means "most recent first"; `O` reverses that.
  for f in "$proj_dir"/*.jsonl(.omN); do
    sid="$(basename "$f" .jsonl)"
    # Last main-thread assistant model (exclude subagent sidechain entries).
    # tail -1 reflects the model user was most recently using when session ended.
    model="$(jq -rc 'select(.type=="assistant" and (.isSidechain // false) == false) | .message.model' "$f" 2>/dev/null | tail -1)"
    # Prefer CC-generated ai-title (concise AI summary, ~30-50 char). Fallback
    # to first user message snippet when no ai-title (covers ~19% of sessions).
    snippet="$(jq -rc 'select(.type=="ai-title") | .aiTitle' "$f" 2>/dev/null | tail -1)"
    [[ -z "$snippet" ]] && snippet="$(jq -rc 'select(.type=="user" and (.message.content|type)=="string") | .message.content[:50]' "$f" 2>/dev/null | head -1)"
    mtime="$(stat -f "%Sm" -t "%m-%d %H:%M" "$f")"
    lines+=("${mtime}|${model:-?}|${sid}|${snippet:-(empty)}")
  done
  (( ${#lines[@]} == 0 )) && { echo "ccp-resume: no sessions in $proj_dir" >&2; return 1; }

  local sel
  # --layout=default: cursor at bottom, items grow upward → newest (first input
  # line, due to zsh `Om` glob) sits at cursor. Explicit override for any
  # FZF_DEFAULT_OPTS=--reverse user might have.
  sel="$(printf '%s\n' "${lines[@]}" | column -t -s '|' | fzf --layout=default --header="Resume CC session (auto-dispatch by model):")"
  [[ -z "$sel" ]] && return 0

  # Robust extract: UUID regex (avoids breakage from `column -t` realigning the
  # mtime "MM-DD HH:MM" — that internal space would shift awk column counts).
  # Model: re-query jsonl rather than parsing picker line.
  local fullsid="$(echo "$sel" | grep -oE '[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}')"
  [[ -z "$fullsid" ]] && { echo "[ccp-resume] failed to extract session ID from selection" >&2; return 1; }
  local model="$(jq -rc 'select(.type=="assistant" and (.isSidechain // false) == false) | .message.model' "$proj_dir/$fullsid.jsonl" 2>/dev/null | tail -1)"
  [[ -z "$model" ]] && model="?"

  local vendor
  case "$model" in
    deepseek-*)        vendor="deepseek" ;;
    kimi-*|moonshot-*) vendor="kimi" ;;        # kimi vs kimi-cn 同 model name 無法區分，default 國際版
    GLM-*|glm-*)       vendor="glm" ;;         # glm vs glm-cn 同上
    mimo-*)            vendor="mimo" ;;
    qwen3-coder-*)     vendor="qwen-coding" ;;
    qwen3-*|qwen-*)    vendor="qwen" ;;
    claude-*)          vendor="anthropic" ;;
    *)                 vendor="unknown" ;;
  esac

  if [[ -n "$CC_VENDOR" && "$CC_VENDOR" != "$vendor" ]]; then
    echo "⚠️  [ccp-resume] 當前 \$CC_VENDOR=$CC_VENDOR, target session model=$model (vendor=$vendor)" >&2
    echo "    cross-vendor resume 會炸 thinking signature (docs/caveats.md §11)" >&2
    printf "    強制繼續? [y/N]: " >&2
    local confirm
    read -r confirm
    [[ "$confirm" != "y" && "$confirm" != "Y" ]] && { echo "cancelled."; return 1; }
  fi

  # Inject ANTHROPIC_MODEL so resumed session uses the jsonl's last model
  # (otherwise CC defaults to ccp-* function's default, e.g. GLM-5.1).
  if [[ "$vendor" == "anthropic" || "$vendor" == "unknown" ]]; then
    echo "[ccp-resume] resuming via plain 'claude --resume' (model=$model)"
    ANTHROPIC_MODEL="$model" claude --resume "$fullsid"
  else
    local fn="ccp-$vendor"
    if ! type "$fn" >/dev/null 2>&1; then
      echo "[ccp-resume] function '$fn' undefined — source ccp-functions.sh first" >&2
      return 1
    fi
    echo "[ccp-resume] dispatching: ANTHROPIC_MODEL=$model $fn --resume $fullsid"
    ANTHROPIC_MODEL="$model" "$fn" --resume "$fullsid"
  fi
}
