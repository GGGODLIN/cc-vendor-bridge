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

# Captured at source time so wrapper functions can locate sibling bin/ scripts.
# zsh idiom: %x = currently-sourced file path; :A = absolute; :h = parent dir.
_CC_VENDOR_BRIDGE_DIR="${${(%):-%x}:A:h:h}"

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
# Source: https://docs.z.ai/devpack/tool/claude
# Verified 2026-06-19 — GLM-5.2 released 2026-06-13, 1M ctx via `[1m]` suffix.
# Subscription (GLM Coding Plan) and PAYG share same key + endpoint — auto-attached to account.
#
# Caveat #16: outer ANTHROPIC_MODEL leakage + ~/.claude/settings.json "model" field
# both override env vars and can cause CC's internal claude-opus-*[1m] alias to bypass
# ANTHROPIC_BASE_URL (same trap as ccp-bruce). Defenses (belt-and-suspenders):
#   1. unset ANTHROPIC_API_KEY (must use AUTH_TOKEN as Bearer)
#   2. Hard-set ANTHROPIC_MODEL / DEFAULT_*_MODEL (NOT ${VAR:-default}) — neutralize leaks
#   3. --model 'glm-5.2[1m]' CLI flag — highest precedence, beats settings.json + env
#
# Caveat #17 (zsh-specific, found 2026-06-19): `glm-5.2[1m]` MUST be single-quoted in
# zsh — `[1m]` is a glob character-class pattern, and an unquoted occurrence aborts
# the function with "no matches found: glm-5.2[1m]". bash doesn't trip this (no NOMATCH
# default). `setopt local_options no_nomatch` is a 防呆 net inside the subshell.
#
# 派工策略：所有 alias 全 glm-5.2[1m] (2026-06-22 改)
# 改前：Opus=glm-5.2[1m] / Sonnet/Haiku/Subagent=glm-4.7（省 quota）
# 改因：subagent / sonnet alias 也享 1M context（5.2 有 1M、4.7 沒有）、跨 alias
#       行為一致、未來不會踩到「opus 走 5.2 / subagent 走 4.7 → context 不對稱」
# 倍率：promo 期 (~2026-09) 內 1× 同 4.7、過後變 2-3×（peak 3× / off-peak 2×）
#
# ⚠️ 2026-06-22 WebSearch tool 問題不是 model 問題 — z.ai 不支援 CC client-side
#    WebSearch tool schema（4.7/5.2 都噴 400 [1210] Invalid API parameter）。
#    z.ai server-side `web_search_20250305` 是工作的（curl probe 確認）、但 CC
#    走的 client-side wrapper schema 不認得。deep-research-paced 等需 WebSearch
#    的 workflow 在 ccp-glm 跑會死、要改走 anthropic 或自寫 Bash + urllib 路徑
#
# ⚠️ 2026-09 review：promo 結束時重評 5.2 全配對 2-3× 成本是否還划算
ccp-glm() {
  if [[ -z "$ZAI_API_KEY" ]]; then
    echo "ccp-glm: ZAI_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    setopt local_options no_nomatch 2>/dev/null
    unset ANTHROPIC_API_KEY
    export CC_VENDOR=glm
    export ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
    export ANTHROPIC_AUTH_TOKEN=$ZAI_API_KEY
    export ANTHROPIC_MODEL='glm-5.2[1m]'
    export ANTHROPIC_DEFAULT_OPUS_MODEL='glm-5.2[1m]'
    export ANTHROPIC_DEFAULT_SONNET_MODEL='glm-5.2[1m]'
    export ANTHROPIC_DEFAULT_HAIKU_MODEL='glm-5.2[1m]'
    export CLAUDE_CODE_SUBAGENT_MODEL='glm-5.2[1m]'
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000
    export API_TIMEOUT_MS=3000000
    export ENABLE_TOOL_SEARCH=auto
    # C-1 harness: propagate --append-system-prompt to subagents + workflow agents.
    export CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1
    # --disallowed-tools WebSearch — z.ai endpoint rejects CC client-side WebSearch
    # tool schema with 400 [1210] Invalid API parameter (2026-06-22 verified for
    # glm-4.7 / glm-5.2; see _index_cc_model_swap entry 2026-06-22). Disable upfront
    # + nudge to client-side Exa avoids the silent workflow-die (deep-research-paced
    # etc. 5/5 Search agents 400-killed) AND saves z.ai Coding Plan monthly quota
    # (if endpoint later returns to the older web_search_prime substitution pattern).
    # --fallback-model pinned to glm-5.2[1m] — on main-model API errors (e.g. z.ai
    # 400 [1301] content filter / [1210] param reject) CC's built-in fallback ignores
    # ANTHROPIC_MODEL env and retries with claude-opus-4-7, which z.ai silently maps
    # to glm-4.7 (200K window): large sessions wedge on a misleading "context window
    # limit" error, small sessions silently degrade (2026-07-04 proxy-capture verified,
    # sessions bcaae410 / a2a18881).
    claude --model 'glm-5.2[1m]' \
      --fallback-model 'glm-5.2[1m]' \
      --disallowed-tools WebSearch \
      --append-system-prompt "WebSearch is disabled on this vendor (z.ai endpoint rejects CC client-side WebSearch schema with 400 [1210] — verified 2026-06-22 for glm-4.7 / glm-5.2). For web search use Bash tool: ${_CC_VENDOR_BRIDGE_DIR}/bin/exa-search.sh \"<query>\" — returns top 5 results with LLM-ready highlights from Exa neural search (free tier 20K req/month, no z.ai Coding Plan quota cost). Pass --json flag for raw JSON if you need to parse fields. IMPORTANT: When dispatching Task subagents or workflow agents that may need web search, you MUST include this verbatim instruction in their prompt: 'For web search use Bash tool: ${_CC_VENDOR_BRIDGE_DIR}/bin/exa-search.sh \"<query>\"' — subagents do not auto-inherit this nudge (session 2650cf5f verified: subagent fell back to DuckDuckGo/Bing/Google HTML scraping)." \
      "$@"
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

# ===== Bruce token proxy (internal test, "GPT-5.5" backend) =====
# Source: https://hackmd.io/@vTE3u1D4ROSvEVdRv4OW5Q/BJcnidZzfl
# Probe verified 2026-06-18:
#   - Anthropic SSE format, backed by OpenAI Responses (resp_* ids)
#   - /v1/models 404; backend force-routes to "gpt-5.5" regardless of client model
#   - Auth must be Authorization: Bearer (x-api-key rejected → 401)
#     → MUST use ANTHROPIC_AUTH_TOKEN (which CC sends as Bearer), NOT ANTHROPIC_API_KEY
#   - Caller's ANTHROPIC_MODEL / DEFAULT_*_MODEL FORCED off (no ${VAR:-default}):
#     CC's `claude-opus-*[1m]` alias has internal Anthropic-only routing that bypasses
#     ANTHROPIC_BASE_URL; if outer shell has any ANTHROPIC_MODEL lingering, leakage
#     would silently route to api.anthropic.com instead of Bruce.
ccp-bruce() {
  if [[ -z "$BRUCE_API_KEY" ]]; then
    echo "ccp-bruce: BRUCE_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export CC_VENDOR=bruce
    export ANTHROPIC_BASE_URL=https://bruce-token-proxy-431026649525.asia-east1.run.app
    export ANTHROPIC_AUTH_TOKEN=$BRUCE_API_KEY
    unset ANTHROPIC_API_KEY  # HackMD warns: must use AUTH_TOKEN, NOT API_KEY
    # Force model pins — intentionally NOT using ${VAR:-default} to neutralize
    # any outer ANTHROPIC_MODEL=claude-opus-4-7[1m] that would route to Anthropic.
    export ANTHROPIC_MODEL=gpt-5.5
    export ANTHROPIC_DEFAULT_OPUS_MODEL=gpt-5.5
    export ANTHROPIC_DEFAULT_SONNET_MODEL=gpt-5.5
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=gpt-5.5
    export CLAUDE_CODE_SUBAGENT_MODEL=gpt-5.5
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    # Deferred tool loading. Was FORCEd off pre-2026-06-19 because Bruce proxy
    # rejected `tool_reference` content blocks with 400 messages.X.content Invalid
    # (36/36 subagent kill rate in devspace-pr-review-eval workflow). Admin
    # confirmed fix 2026-06-19; bin/probe-bruce-tool-reference.sh passes (200).
    # Restored to default auto — recovers ~30-100K tokens of system-prompt budget.
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    # Match ccp-deepseek / ccp-mimo convention — disable client-side auto-compact.
    # Backend ctx lifted to 1M 2026-06-19 (admin confirmed; user re-probed pass).
    export DISABLE_COMPACT=${DISABLE_COMPACT:-1}
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1000000}
    # C-1 harness: --append-system-prompt propagates to every Task-tool subagent +
    # nested subagents + workflow agents (gate documented in CC binary, verified
    # 2026-06-19). Tiny system prompt below to keep propagation cheap.
    export CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1
    # --disallowed-tools WebSearch — HARD safety. The 2026-06-19 fix to issue 2
    # (proxy now accepts web_search_20250305 schema) regressed into SILENT
    # FABRICATION: proxy returns 200 + tool_result body with fake citations
    # dressed in Anthropic's "REMINDER: You MUST include the sources above..."
    # injection. Verified session 580f03bc (3/3 prompts), model dutifully quoted
    # fabricated URLs / dates. Worse than the original 400 because the failure
    # is invisible to client + user. Keep disabled until proxy implements a real
    # search backend (e.g. Bocha, like DeepSeek's /anthropic does) OR returns
    # honest is_error tool_result. See docs/caveats.md §13b.
    # --model CLI flag has highest precedence (above settings.json + ANTHROPIC_MODEL env);
    # without it settings.json "model":"claude-opus-4-7[1m]" overrides env force-pin
    # and CC TUI displays the wrong model (API still routes to Bruce).
    claude --model gpt-5.5 \
      --disallowed-tools WebSearch \
      --append-system-prompt "WebSearch is disabled on this vendor (Bruce proxy returns fabricated SERP results — verified 2026-06-19 session 580f03bc). For web search use Bash tool: ${_CC_VENDOR_BRIDGE_DIR}/bin/exa-search.sh \"<query>\" — returns top 5 results with LLM-ready highlights from Exa neural search (free tier 20K req/month, no Bruce token cost). Pass --json flag for raw JSON if you need to parse fields. IMPORTANT: When dispatching Task subagents or workflow agents that may need web search, you MUST include this verbatim instruction in their prompt: 'For web search use Bash tool: ${_CC_VENDOR_BRIDGE_DIR}/bin/exa-search.sh \"<query>\"' — subagents do not auto-inherit this nudge (session 2650cf5f verified: subagent fell back to DuckDuckGo/Bing/Google HTML scraping)." \
      "$@"
  )
}

# ===== Bruce one-shot status snapshot (quota + pool health + service stability) =====
#合併三條 curl-系查詢：
#   /v1/usage/quota   →  consumed / remaining USD                (per-key billing)
#   /v1/pool/status   →  healthPercent + serviceStabilityPercent (admin endpoints)
#
# healthPercent (2026-06-20 calibrated leading indicator)
#   pool 容量 — 15-account pool 還有多少 5h quota 沒被吃掉，6.67% step。
#   < 20% = pool 接近耗盡、imminent 503 風險。
#
# serviceStabilityPercent (新增 2026-06-28，無 historic calibration)
#   服務層可用性（推測為 success rate / 反向 error rate），連續百分比、100=全綠。
#   推測門檻（待 trend 累積資料校準）：
#     ≥ 80%: 正常
#     50-80: 服務有波動，可能 upstream provider 部分異常
#     < 50%: 服務嚴重不穩、建議 pause 大量工作 workflow
#
# Usage:
#   ccp-bruce-status              # human-readable snapshot
#   ccp-bruce-status --json       # merged raw JSON ({quota, pool})
ccp-bruce-status() {
  if [[ -z "$BRUCE_API_KEY" ]]; then
    echo "ccp-bruce-status: BRUCE_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi

  if ! command -v jq >/dev/null; then
    echo "ccp-bruce-status: jq not found" >&2
    return 1
  fi

  local raw=0
  if [[ "${1:-}" == "--json" ]]; then
    raw=1
  fi

  local base="https://bruce-token-proxy-2kjfv3lttq-de.a.run.app"
  local quota pool
  if ! quota=$(curl -fsS -m 10 \
    -H "Authorization: Bearer $BRUCE_API_KEY" \
    "$base/v1/usage/quota"); then
    echo "ccp-bruce-status: /v1/usage/quota request failed" >&2
    return 1
  fi
  if ! pool=$(curl -fsS -m 10 \
    -H "Authorization: Bearer $BRUCE_API_KEY" \
    "$base/v1/pool/status"); then
    echo "ccp-bruce-status: /v1/pool/status request failed" >&2
    return 1
  fi

  if [[ "$raw" == 1 ]]; then
    jq -n --argjson quota "$quota" --argjson pool "$pool" '{quota: $quota, pool: $pool}'
    return
  fi

  jq -nr \
    --argjson quota "$quota" \
    --argjson pool "$pool" \
    '
    ($quota.consumedUsd // 0) as $c
    | ($quota.remainingUsd) as $r
    | ($pool.healthPercent // null) as $h
    | ($pool.serviceStabilityPercent // null) as $s
    | (if $r == null then "unlimited" else "$\($r * 100 | round / 100)" end) as $rStr
    | (if $r == null then "unlimited" else "$\(($c + $r) * 100 | round / 100)" end) as $tStr
    | (if $r == null or ($c + $r) <= 0 then "n/a" else "\($c / ($c + $r) * 1000 | round / 10)%" end) as $pctStr
    | "[ccp-bruce-status]\n"
      + "quota   consumed=$\($c * 100 | round / 100) / total=\($tStr)   used=\($pctStr)   remaining=\($rStr)\n"
      + "pool    healthPercent=\($h // "?")%   (15-acct pool capacity, 6.67% step, leading indicator for 503)\n"
      + "service serviceStabilityPercent=\($s // "?")%   (service-layer reliability, 100=all-green; thresholds推測 ≥80 normal / 50-80 wobble / <50 unstable)"
    '
}

# ===== Bruce pool health watcher =====
# Polls /v1/pool/status healthPercent (no token cost) and fires macOS
# notifications on cross-down of warn / alert / critical thresholds. The
# earlier ccp-bruce-correlate experiment confirmed (2026-06-20 636-sample
# / 2h9min run) healthPercent is a leading indicator — messages stayed
# 100% 2xx while health swung 86.67% → 20%. Logic folded into watch;
# correlate retired.
ccp-bruce-watch() {
  if [[ -z "$BRUCE_API_KEY" ]]; then
    echo "ccp-bruce-watch: BRUCE_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  "${_CC_VENDOR_BRIDGE_DIR}/bin/ccp-bruce-watch" "$@"
}

# ===== Codex side: codex CLI through Bruce (OpenAI Responses path) =====
# Companion of ccp-bruce (Anthropic-side claude wrapper). Same backend, different
# wire — codex CLI 0.139+ speaks OpenAI Responses API natively; Bruce exposes
# both Anthropic SSE (for CC) and OpenAI Responses (for codex) on the same host.
#
# Mechanism: top-level `-c model_provider=bruce` is a per-invocation override
# (codex top-level OPTIONS, applies to every subcommand). NO restart, NO
# CODEX_HOME swap, NO change to default provider — the ChatGPT OAuth bundle in
# ~/.codex/auth.json stays intact, business team quota untouched.
#
# Prerequisite (one-time): ~/.codex/config.toml must contain
#   [model_providers.bruce]
#   name = "Bruce"
#   base_url = "https://bruce-token-proxy-431026649525.asia-east1.run.app/v1"
#   wire_api = "responses"
#   env_key = "BRUCE_API_KEY"
# Setup done 2026-06-19.
#
# Usage:
#   codex-bruce                              # interactive via bruce
#   codex-bruce review --base main           # native review (OpenAI-tuned subagent) via bruce
#   codex-bruce exec "<task>"                # exec via bruce
#   codex-bruce exec --skip-git-repo-check --output-schema s.json -o out.json "..." < /dev/null
#
# Notes:
#   - Plugin (/codex:review, /pr-review) still binds to default openai provider
#     by design — to swap plugin side too you'd need to flip the default in
#     ~/.codex/config.toml (NOT done here, since the whole point of codex-bruce
#     is "OpenAI default, bruce on demand").
#   - Native `codex review` subcommand walks the SAME review subagent the plugin
#     uses via `runAppServerReview` (OpenAI-tuned prompt, calibration preserved).
#     Going through `codex review --base main` via codex-bruce thus keeps quality.
#   - Bruce backend force-routes everything to gpt-5.5 regardless of -c model=...
#     so `model = "gpt-5.5"` in config.toml is consistent across openai/bruce.
codex-bruce() {
  if [[ -z "$BRUCE_API_KEY" ]]; then
    echo "codex-bruce: BRUCE_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  codex -c model_provider=bruce "$@"
}

# ===== Codex side: codex CLI through z.ai GLM (via local LiteLLM bridge) =====
# Setup 2026-06-24. End-to-end smoke verified: codex exec → LiteLLM (port 4000)
# → z.ai glm-5.2 → response + 11.8K tokens accounted.
#
# Why a proxy: z.ai 不暴露 /v1/responses (probed 2026-06-24: 4 條 base 全 404),
# codex 0.139+ 只接 wire_api = "responses"。LiteLLM bridge 把 client 的
# /v1/responses 翻譯成 /v1/chat/completions 再 forward 到 z.ai Coding Plan。
# 配套 yaml: config/litellm-zai.yaml (use_chat_completions_api: true)。
#
# Prerequisites:
#   1. ~/.codex/config.toml has [model_providers.zai] block pointing to
#      http://localhost:4000/v1 (added 2026-06-24)
#   2. LITELLM_MASTER_KEY env exported (matches general_settings.master_key
#      in yaml — see ~/.zsh_secrets)
#   3. LiteLLM proxy running:  bin/codex-glm-proxy-start.sh
#
# The 9 --disable flags are mandatory: codex 0.142 ships 20+ built-in tools
# including 5 namespace-type (multi_agent, apps), 1 web_search, 1 image_generation.
# z.ai chat completions only accepts tools[].type = "function" and rejects
# anything else with 400 "tools[N].type:type is illegal". Disabling these
# features strips the non-function tools at request build time.
#
# Caveats:
#   - Plugin (/codex:review etc.) bypasses this wrapper (plugin spawns codex
#     with hardcoded ["app-server"] args, no -c injection surface). Use codex
#     review subcommand instead, or flip default provider in config.toml.
#   - Two non-fatal stderr warnings ("failed to refresh available models",
#     "OutputTextDelta without active item") — don't affect functionality.
#   - z.ai 429 self-throttle is common; codex internal retry doesn't backoff
#     well. For important tasks probe z.ai health first.
#   - Tools stripped: multi-agent, plugins, browser_use, computer_use,
#     image_generation, goals, tool_suggest, web_search. Agentic capability
#     half-crippled vs native — use for fallback, not as daily driver.
codex-glm() {
  if [[ -z "$ZAI_API_KEY" ]]; then
    echo "codex-glm: ZAI_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  if [[ -z "$LITELLM_MASTER_KEY" ]]; then
    echo "codex-glm: LITELLM_MASTER_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  if ! /usr/sbin/lsof -nP -iTCP:4000 -sTCP:LISTEN >/dev/null 2>&1; then
    echo "codex-glm: LiteLLM proxy not running on :4000." >&2
    echo "  Start it:  ${_CC_VENDOR_BRIDGE_DIR}/bin/codex-glm-proxy-start.sh" >&2
    return 1
  fi
  codex -c model_provider=zai -c model=glm-5.2 \
    --disable multi_agent \
    --disable apps \
    --disable image_generation \
    --disable browser_use \
    --disable browser_use_external \
    --disable computer_use \
    --disable plugins \
    --disable goals \
    --disable tool_suggest \
    "$@"
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

# ===== CLIProxyAPI self-hosted relay (subscription-to-API hub) =====
# Backend: ~/Desktop/projects/cliproxyapi-setup (management handbook in its CLAUDE.md).
# Serves Codex OAuth (gpt-5.5/5.4), Antigravity OAuth (claude-opus-4-6-thinking /
# claude-sonnet-4-6 / gemini-pro-agent=3.1-Pro-High / nano-banana-2 image), and the
# free pool (ds-flash = Zen-priority + NVIDIA-fallback cross-provider alias).
# Per-call override:
#   ANTHROPIC_MODEL=claude-sonnet-4-6 ccp-relay        # Antigravity Claude
#   ANTHROPIC_MODEL='gpt-5.5(high)' ccp-relay          # effort suffix works
#   ANTHROPIC_MODEL=ds-flash ccp-relay -p "cheap task" # free pool
ccp-relay() {
  if [[ ! -f ~/.cli-proxy-api/keys.env ]]; then
    echo "ccp-relay: ~/.cli-proxy-api/keys.env not found. See cliproxyapi-setup/CLAUDE.md" >&2
    return 1
  fi
  # Health check: relay is a launchd KeepAlive service on 8317; kickstart if down.
  if ! /usr/bin/nc -z 127.0.0.1 8317 2>/dev/null; then
    echo "[ccp-relay] relay not listening, kickstarting launchd service..." >&2
    launchctl kickstart "gui/$UID/com.philip.cli-proxy-api" 2>/dev/null
    local i=0
    while (( i < 50 )); do
      /usr/bin/nc -z 127.0.0.1 8317 2>/dev/null && break
      sleep 0.1; ((i++))
    done
    if (( i >= 50 )); then
      print -P "%F{red}[ccp-relay] relay did not become ready in 5s — check ~/.cli-proxy-api/logs/%f" >&2
      return 1
    fi
  fi
  (
    source ~/.cli-proxy-api/keys.env
    unset ANTHROPIC_API_KEY  # relay auth goes through AUTH_TOKEN (Bearer)
    export CC_VENDOR=relay
    export ANTHROPIC_BASE_URL=$CLIPROXY_BASE_URL
    export ANTHROPIC_AUTH_TOKEN=$CLIPROXY_KEY_CC
    export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-gpt-5.5}
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-gpt-5.5}
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-gpt-5.5}
    # HAIKU slot → free pool: background/summarization traffic costs nothing.
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-ds-flash}
    export CLAUDE_CODE_SUBAGENT_MODEL=${CLAUDE_CODE_SUBAGENT_MODEL:-gpt-5.5}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    # --disallowed-tools WebSearch — untested how CLIProxyAPI translates the
    # web_search_20250305 server-tool schema to Codex/Antigravity upstreams
    # (glm rejects with 400, bruce silently fabricates — see docs/caveats.md §13b).
    # Keep disabled until probed; remove after a verified pass.
    claude --disallowed-tools WebSearch "$@"
  )
}

# ===== CLIProxyAPI relay, all-GPT slot mapping (GPT-5.6 family) =====
# Recipe from OpenAI Codex lead Tibo Sottiaux (x.com/thsottiaux/status/2076119366647894371,
# 2026-07-12) plus community fixes from the same thread. Tier mapping per OpenAI's
# official positioning (Sol=flagship, Terra=balanced default, Luna=fast/cheap):
#   OPUS→gpt-5.6-sol  SONNET→gpt-5.6-terra  HAIKU→gpt-5.6-luna
# Context pinned to GPT-5.6's 272k cap (CC otherwise assumes 200k/1M); one thread
# report says 272k broke auto-compact — watch for it, both vars are overridable.
# Per-call override:
#   ANTHROPIC_MODEL='gpt-5.6-sol(high)' ccp-gpt        # effort suffix works
#   CLAUDE_CODE_SUBAGENT_MODEL=gpt-5.6-sol ccp-gpt     # explicitly override routing
ccp-gpt() {
  if [[ ! -f ~/.cli-proxy-api/keys.env ]]; then
    echo "ccp-gpt: ~/.cli-proxy-api/keys.env not found. See cliproxyapi-setup/CLAUDE.md" >&2
    return 1
  fi
  if ! /usr/bin/nc -z 127.0.0.1 8317 2>/dev/null; then
    echo "[ccp-gpt] relay not listening, kickstarting launchd service..." >&2
    launchctl kickstart "gui/$UID/com.philip.cli-proxy-api" 2>/dev/null
    local i=0
    while (( i < 50 )); do
      /usr/bin/nc -z 127.0.0.1 8317 2>/dev/null && break
      sleep 0.1; ((i++))
    done
    if (( i >= 50 )); then
      print -P "%F{red}[ccp-gpt] relay did not become ready in 5s — check ~/.cli-proxy-api/logs/%f" >&2
      return 1
    fi
  fi
  (
    source ~/.cli-proxy-api/keys.env
    unset ANTHROPIC_API_KEY  # relay auth goes through AUTH_TOKEN (Bearer)
    export CC_VENDOR=gpt
    export ANTHROPIC_BASE_URL=$CLIPROXY_BASE_URL
    export ANTHROPIC_AUTH_TOKEN=$CLIPROXY_KEY_CC
    export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-gpt-5.6-sol}
    export ANTHROPIC_DEFAULT_FABLE_MODEL=${ANTHROPIC_DEFAULT_FABLE_MODEL:-gpt-5.6-sol}
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-gpt-5.6-sol}
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-gpt-5.6-terra}
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-gpt-5.6-luna}
    export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=${CLAUDE_CODE_ALWAYS_ENABLE_EFFORT:-1}
    export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=${CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY:-3}
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-272000}
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-240000}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    # Single-shot injection caps for the 272k window: oversized MCP output spills
    # to a temp file, oversized bash output truncates with a [KB removed] marker.
    export MAX_MCP_OUTPUT_TOKENS=${MAX_MCP_OUTPUT_TOKENS:-25000}
    export BASH_MAX_OUTPUT_LENGTH=${BASH_MAX_OUTPUT_LENGTH:-30000}
    # Tibo's alias sets false outright; GPT models' deferred-tool handling unverified.
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-false}
    # WebSearch: same unprobed relay translation path as ccp-relay (docs/caveats.md §13b).
    # Skill(claude-api): the bundled skill injects ~800KB (~200k tokens) when triggered
    # (and it triggers on ANY Claude/LLM mention) — with this env's ~57k baseline that
    # blows the 272k window with "Prompt is too long" (session c83482eb, 2026-07-14).
    # Fine under fable[1m]; fatal on 272k models.
    # --model flag beats settings.json "model" (user pins claude-fable-5[1m] there,
    # which otherwise silently overrides ANTHROPIC_MODEL and mis-routes on the relay).
    claude --model "$ANTHROPIC_MODEL" --disallowed-tools 'WebSearch' 'Skill(claude-api)' "$@"
  )
}

ccp-gpt-fast() {
  (
    if [[ -n "${ANTHROPIC_CUSTOM_HEADERS:-}" ]]; then
      export ANTHROPIC_CUSTOM_HEADERS="${ANTHROPIC_CUSTOM_HEADERS}"$'\n'"X-CCP-Fast: 1"
    else
      export ANTHROPIC_CUSTOM_HEADERS="X-CCP-Fast: 1"
    fi
    ccp-gpt "$@"
  )
}

# ===== Helper: list available functions =====
ccp-list() {
  cat <<EOF
Available cc-vendor-bridge functions:

  ccp-deepseek      → DeepSeek V4-Pro / V4-Flash
  ccp-glm           → Zhipu GLM-5.1 / 4.7-Flash (z.ai intl)
  ccp-mimo          → Xiaomi MiMo V2.5-Pro Token Plan (Singapore subscription)
  ccp-mimo-payg     → Xiaomi MiMo V2.5-Pro (intl PAYG)
  ccp-bruce         → Bruce token proxy (internal test, "GPT-5.5" backend; force-routed)
  ccp-local         → Rapid-MLX local (auto-detect model via /v1/models on :8002, Apple Silicon, zero cost)
                      Override: LOCAL_MODEL=... / RAPID_MLX_LOCAL_URL=...
                      Needs vllm_mlx tool-content-flatten patch for Qwen3.6 strict template (see local-model-bench FINDINGS §8.6)
  ccp-relay         → CLIProxyAPI self-hosted relay :8317 (default gpt-5.5 via Codex team OAuth;
                      HAIKU slot→ds-flash free pool; claude-sonnet-4-6 / gemini-pro-agent via Antigravity)
                      Override: ANTHROPIC_MODEL=<any relay model> ccp-relay; WebSearch disabled until probed
  ccp-gpt           → CLIProxyAPI relay, all-GPT-5.6 slot mapping (OPUS→sol / SONNET→terra /
                      HAIKU→luna / subagent routing preserved), Tibo-recipe env vars (effort on,
                      concurrency 3, 272k context, tool search off)
  ccp-gpt-fast      → Same routing and context as ccp-gpt; priority service tier for all GPT-5.6 requests

  ccp-resume        → 互動 picker 選 prior session resume，自動 dispatch 對應 vendor
                      (workaround caveat 11: 跨 vendor resume 會炸 thinking signature)

  ccp-bruce-status  → Bruce 三件事 snapshot (quota + pool health + service stability)
                      取代舊 ccp-bruce-quota / ccp-bruce-usage 的日常使用 (--json 印合併原始)
  ccp-bruce-watch   → Bruce 長期守護 watcher (healthPercent + serviceStabilityPercent 雙 metric
                      threshold 觸發，jsonl log 落檔，macOS notification)

Disabled (API key not configured):
  ccp-kimi / ccp-kimi-cn / ccp-glm-cn / ccp-qwen / ccp-qwen-coding

Codex side (OpenAI Responses path, runs codex CLI not claude):
  codex-bruce       → codex CLI through Bruce (per-invocation -c override)
                      Default codex provider stays openai (ChatGPT OAuth) — only
                      this wrapper routes to bruce; plugin /codex:review unaffected.
                      Examples:
                        codex-bruce review --base main      (native review via bruce)
                        codex-bruce exec "<task>"
                        codex-bruce                          (interactive)

Each ccp-* opens a Claude Code session backed by that vendor.
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
