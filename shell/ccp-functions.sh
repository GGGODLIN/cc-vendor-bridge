#!/usr/bin/env zsh
# cc-vendor-bridge — Path 0 zsh functions
#
# ⚠️ 本檔在契約測試底下 — 改完必跑（從 repo root）：
#   for t in tests/ccp-free-wrapper.test.zsh tests/ccp-gpt-routing-fast.zsh tests/ccp-gpt-whoami.test.zsh tests/ccp-relay-priority.test.zsh; do zsh "$t" || break; done
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
#   ccp-deepseek-flash          # DeepSeek, ALL model slots forced to V4-Flash
#   ccp-deepseek-pro            # DeepSeek, ALL model slots forced to V4-Pro
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

_cc_vendor_claude() {
  local launcher="${CC_CLAUDE_BIN:-claude}"
  command "$launcher" "$@"
}

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
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    export DISABLE_COMPACT=${DISABLE_COMPACT:-1}
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1000000}
    _cc_vendor_claude "$@"
  )
}

# ===== DeepSeek V4-Flash / V4-Pro — all model slots forced =====
# Thin wrappers that pre-pin all 5 model slots (main / opus / sonnet / haiku /
# subagent) then delegate to ccp-deepseek, which reuses the proxy health-check +
# env convention. Pre-setting beats its ${VAR:-default} fallbacks, so a lingering
# outer ANTHROPIC_MODEL can't redirect any slot to the other variant or Anthropic
# (same anti-leak rationale as ccp-bruce's hard-set pins).
ccp-deepseek-flash() {
  ANTHROPIC_MODEL=deepseek-v4-flash \
  ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-flash \
  ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-flash \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash \
  CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash \
    ccp-deepseek "$@"
}

ccp-deepseek-pro() {
  ANTHROPIC_MODEL=deepseek-v4-pro \
  ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro \
  ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro \
  ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-pro \
  CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-pro \
    ccp-deepseek "$@"
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
    # Subagent propagation moved to the --append-subagent-system-prompt flag below.
    # CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1 sat here from 2026-06-22 (e7933f1)
    # as "propagate --append-system-prompt to subagents" and was never verified; a
    # 2026-08-22 marker probe on CC 2.1.239 showed the env var alone is the gate, not
    # the carrier — the subagent saw nothing while the main session saw the marker.
    # The flag implies the env var, so setting it separately is redundant.
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
    local _nudge="WebSearch is disabled on this vendor (z.ai endpoint rejects CC client-side WebSearch schema with 400 [1210] — verified 2026-06-22 for glm-4.7 / glm-5.2). For web search use Bash tool: ${_CC_VENDOR_BRIDGE_DIR}/bin/exa-search.sh \"<query>\" — returns top 5 results with LLM-ready highlights from Exa neural search (free tier 20K req/month, no z.ai Coding Plan quota cost). Pass --json flag for raw JSON if you need to parse fields."
    _cc_vendor_claude --model 'glm-5.2[1m]' \
      --fallback-model 'glm-5.2[1m]' \
      --disallowed-tools WebSearch \
      --append-system-prompt "${_nudge} IMPORTANT: When dispatching Task subagents or workflow agents that may need web search, you MUST include this verbatim instruction in their prompt: 'For web search use Bash tool: ${_CC_VENDOR_BRIDGE_DIR}/bin/exa-search.sh \"<query>\"' — in interactive mode subagents do not inherit this nudge (session 2650cf5f verified: subagent fell back to DuckDuckGo/Bing/Google HTML scraping; 2026-08-22 marker probe confirmed the flag below covers --print runs only)." \
      --append-subagent-system-prompt "$_nudge" \
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
    _cc_vendor_claude "$@"
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
    _cc_vendor_claude "$@"
  )
}

# ===== BRUCEAI gateway — GPT-5.6 family, prepaid credits =====
# Official docs: https://www.bruceai.net/docs/claude-code · pricing: /pricing
# Rebuilt 2026-08-17 against api.bruceai.net. The internal-test Cloud Run hosts
# (bruce-token-proxy-431026649525.asia-east1 / -2kjfv3lttq-de.a.run.app) still answer
# and share the same backend and balance, but api.bruceai.net is the documented one.
# Every claim in the old comment block was re-probed and most had expired:
#   - /v1/models: was 404, now 200 listing sol / terra / luna / 5.5 / 5.4 / 5.4-mini
#     / codex-auto-review
#   - routing: was "force-routed to gpt-5.5 whatever the client asks", now genuinely
#     per-id. Same prompt: sol 13.1s/598tok · terra 6.3s/263 · luna 8.3s/312 ·
#     5.4-mini 30.0s/1982 — four distinct behaviours, so the slot mapping below is real
#   - prompt cache: works and is free to write. A repeated 27,603-token prefix came back
#     cache_read=27,392 / cache_creation=0 (OpenAI-style implicit caching), so the
#     "cache write" column in the price table never actually fires
#   - WebSearch: was silent fabrication, now real — see the --append-system-prompt note
# Auth is the one thing unchanged: Bearer only, so ANTHROPIC_AUTH_TOKEN and never
# ANTHROPIC_API_KEY (x-api-key → 401).
#
# Per-call override:
#   ANTHROPIC_MODEL=gpt-5.6-terra ccp-bruce        # different main model
#   CCP_BRUCE_EFFORT=max ccp-bruce                 # deeper reasoning, costs more output
ccp-bruce() {
  if [[ -z "$BRUCE_API_KEY" ]]; then
    echo "ccp-bruce: BRUCE_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export CC_VENDOR=bruce
    export ANTHROPIC_BASE_URL=https://api.bruceai.net
    export ANTHROPIC_AUTH_TOKEN=$BRUCE_API_KEY
    unset ANTHROPIC_API_KEY  # Bruce docs: must use AUTH_TOKEN, NOT API_KEY
    # Per-call model override is supported, but a stray claude-* value from the outer
    # shell must not survive: CC's claude-* aliases carry Anthropic-only routing that
    # bypasses ANTHROPIC_BASE_URL, so the session would silently bill Anthropic instead
    # of Bruce. Drop it rather than force-pinning, which would kill the override too.
    if [[ "${ANTHROPIC_MODEL:-}" == claude-* ]]; then
      print -P "%F{yellow}[ccp-bruce] 忽略外層 ANTHROPIC_MODEL=${ANTHROPIC_MODEL}（claude-* 會繞過 Bruce 直接計費到 Anthropic）%f" >&2
      unset ANTHROPIC_MODEL
    fi
    # Slot mapping mirrors ccp-gpt: flagship for judgement, cheap tier for the rest.
    # Terra is skipped for the same reason ccp-gpt dropped it — it sits in the middle
    # being neither. 5.4-mini is cheaper than luna (0.75 vs 1.00 credits/M input) but
    # probes badly: 30.0s and 1,982 output tokens on a prompt luna answered in 8.3s
    # with 312, so it loses on total cost anyway.
    # NOTE the effort suffix ccp-gpt uses — `gpt-5.6-luna(max)` — is CLIProxyAPI syntax.
    # Bruce rejects it: 400 `Model "requested model(max)" is not supported`. Effort
    # travels in output_config instead, via the --effort flag below.
    export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-gpt-5.6-sol}
    export ANTHROPIC_DEFAULT_FABLE_MODEL=${ANTHROPIC_DEFAULT_FABLE_MODEL:-gpt-5.6-sol}
    export ANTHROPIC_DEFAULT_OPUS_MODEL=${ANTHROPIC_DEFAULT_OPUS_MODEL:-gpt-5.6-sol}
    export ANTHROPIC_DEFAULT_SONNET_MODEL=${ANTHROPIC_DEFAULT_SONNET_MODEL:-gpt-5.6-luna}
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=${ANTHROPIC_DEFAULT_HAIKU_MODEL:-gpt-5.6-luna}
    # Deliberately NOT setting CLAUDE_CODE_SUBAGENT_MODEL: leaving it unset lets the
    # slot mapping do the routing, so ~/.claude/agents/routed-*.md land where the policy
    # says (routed-impl/judge/secure = opus → sol, routed-mech = sonnet → luna).
    # Effort is a real knob here — same reasoning prompt ran 9.2s/384 tokens at low
    # versus 20.5s/1042 at max. ccp-gpt pins xhigh for Sol because Codex OAuth is a subscription;
    # Bruce bills per token, so max costs ~2.7x the output. high is the default trade.
    export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=${CLAUDE_CODE_ALWAYS_ENABLE_EFFORT:-1}
    # Context: the hard ceiling probed between 824,850 (accepted) and ~900,000
    # (rejected with 「內容已達模型上限，請執行 /compact 後繼續。」), so the docs' 1.05M
    # is not actually reachable. It barely matters, because the binding limit is
    # commercial, not technical: once input + cache reads pass 272,000 the WHOLE request
    # is rebilled at the long-context rate (input x2, output x1.5). So the window is
    # pinned at that cliff and auto-compact is left ON to stay under it.
    # Compact fires at min(window, max_context) - min(max_output, 20k) - 13k = 217,000.
    # CC only measures at turn boundaries and overshoots — worst observed on ccp-gpt
    # across 44 real auto-compacts was 21,415 — which lands ~238,415, leaving ~33K of
    # headroom for concurrent tool injections before the cliff.
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-272000}
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-250000}
    # Single-shot injection caps, tightened from ccp-gpt's 25000/30000: a 272K window
    # cannot absorb what a 1M window shrugs off. Three concurrent MCP calls at 12000
    # is 36,000, which the headroom above just covers.
    export MAX_MCP_OUTPUT_TOKENS=${MAX_MCP_OUTPUT_TOKENS:-12000}
    export BASH_MAX_OUTPUT_LENGTH=${BASH_MAX_OUTPUT_LENGTH:-20000}
    export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=${CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY:-3}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    # Deferred tool loading. Was forced off pre-2026-06-19 when Bruce rejected
    # `tool_reference` content blocks with 400 (36/41 subagents killed in the
    # devspace-pr-review-eval workflow); re-probed 200 on api.bruceai.net 2026-08-17.
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    # Subagent propagation moved to --append-subagent-system-prompt below; the env var
    # that sat here since 2026-06-22 is only the gate and carries nothing on its own
    # (2026-08-22 marker probe on CC 2.1.239). The flag implies it.
    # WebSearch is ENABLED again as of 2026-08-17. The 2026-06-19 verdict (session
    # 580f03bc, "silent fabrication", 3/3 prompts) no longer reproduces. Controlled
    # re-probe used a fact that cannot exist in any training set — the claude-code
    # release tag published three days earlier:
    #   with the web_search tool offered  → "v2.1.233 — August 14, 2026" + correct
    #                                        release URL, input_tokens 21,081
    #   with no tools offered             → "UNKNOWN", input_tokens 162
    #   no tools, luna                    → "UNKNOWN"
    # It only searches when CC actually offers the tool, and it declines to guess when
    # it cannot. Caveat: the reply carries no `web_search_tool_result` block (content is
    # just thinking + text), so CC's citation UI stays dark — the URLs land in prose.
    # The real cost is context, not accuracy: ~21K tokens injected per search against a
    # 272K window, hence the exa-first nudge below.
    # Skill(claude-api) unblocked 2026-08-25 (trial claude-api-skill-unblock, review
    # 2026-09-01): CC 2.1.243 loads it progressively — headless probe measured ~19k
    # tokens per invoke on the relay (52,879 baseline → 71,875 with the skill), not the
    # ~200k that blew the 272k window on 2026-07-14 (session c83482eb). Re-block if the
    # trial shows GPT invoking it several times per session.
    # --model CLI flag outranks settings.json, whose "model" pin would otherwise
    # override the env mapping and mis-route the session.
    local _nudge="This vendor bills per token against a prepaid balance, and the context window is pinned at 272,000 because crossing that line rebills the entire request at double the input rate. Budget context deliberately. WebSearch works here and returns real results, but each call injects roughly 21,000 tokens of search output — about 8% of the whole window. For lightweight factual lookups prefer the Bash tool: ${_CC_VENDOR_BRIDGE_DIR}/bin/exa-search.sh \"<query>\" — top 5 results with LLM-ready highlights from Exa neural search, free tier, zero Bruce token cost, and a fraction of the context. Pass --json for raw fields. Reserve WebSearch for cases that genuinely need live page content or where exa comes back empty."
    _cc_vendor_claude --effort "${CCP_BRUCE_EFFORT:-high}" \
      --model "$ANTHROPIC_MODEL" \
      --append-system-prompt "${_nudge} IMPORTANT: when dispatching Task subagents or workflow agents, include this guidance verbatim in their prompt — in interactive mode subagents do not inherit it (session 2650cf5f: a subagent fell back to scraping DuckDuckGo/Bing/Google HTML; 2026-08-22 marker probe confirmed the flag below covers --print runs only)." \
      --append-subagent-system-prompt "$_nudge" \
      "$@"
  )
}

# ===== Bruce one-shot status snapshot (balance + service stability) =====
# 兩條 curl（都不花 token）：
#   /v1/usage       →  預付額度餘額（= /v1/usage/balance，同一份 payload）
#   /v1/pool/status →  healthPercent + serviceStabilityPercent
#
# ⚠️ 2026-08-17 換過來源：舊的 /v1/usage/quota 已經壞了 — 5 次採樣 4 次空 body、
#    1 次 500 Internal server error。改讀 /v1/usage，欄位是
#    {total, used, remaining, balance, planName, is_active}。
#
# 額度換算：官方定價頁寫 每 US$1 = 21 額度。API 的 "unit":"USD" 名不副實，
#    數字其實是額度，所以下面自己除以 21 換回美金給人看。
#
# serviceStabilityPercent
#   服務層可用性，連續百分比、100 = 全綠。門檻仍是推測值（2026-06-28 起未校準）：
#     ≥ 80%: 正常 / 50-80: 有波動 / < 50: 建議 pause 大量工作 workflow
#
# ⚠️ healthPercent 已失效（2026-08-17 實測）
#   舊語意是 15-account pool 的剩餘容量、6.67% 一階、< 20% 代表接近耗盡。
#   現在恆為 0：三次採樣皆 0，同期 serviceStability 99-100、所有 /v1/messages 全 200。
#   轉正式營運後應該已不再維護此欄位。顯示保留供觀察，但不再當判斷依據，
#   ccp-bruce-watch 與 /bruce-workflow-monitor 的 health gate 都已預設關閉。
#
# Usage:
#   ccp-bruce-status              # human-readable snapshot
#   ccp-bruce-status --json       # merged raw JSON ({usage, pool})
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

  local base="https://api.bruceai.net"
  local usage pool
  if ! usage=$(curl -fsS -m 10 \
    -H "Authorization: Bearer $BRUCE_API_KEY" \
    "$base/v1/usage"); then
    echo "ccp-bruce-status: /v1/usage request failed" >&2
    return 1
  fi
  if ! pool=$(curl -fsS -m 10 \
    -H "Authorization: Bearer $BRUCE_API_KEY" \
    "$base/v1/pool/status"); then
    echo "ccp-bruce-status: /v1/pool/status request failed" >&2
    return 1
  fi

  if [[ "$raw" == 1 ]]; then
    jq -n --argjson usage "$usage" --argjson pool "$pool" '{usage: $usage, pool: $pool}'
    return
  fi

  jq -nr \
    --argjson usage "$usage" \
    --argjson pool "$pool" \
    '
    (21) as $perUsd
    | ($usage.used // 0) as $u
    | ($usage.total // 0) as $t
    | ($usage.remaining // $usage.balance // 0) as $r
    | ($pool.healthPercent // null) as $h
    | ($pool.serviceStabilityPercent // null) as $s
    | (if $t > 0 then "\($r / $t * 1000 | round / 10)%" else "n/a" end) as $pctStr
    | "[ccp-bruce-status]\n"
      + "credits used=\($u * 100 | round / 100) / total=\($t * 100 | round / 100)   remaining=\($r * 100 | round / 100) (\($pctStr))   ≈ US$\($r / $perUsd * 100 | round / 100) left   [21 credits = US$1]\n"
      + "plan    \($usage.planName // "?")   active=\($usage.is_active // "?")\n"
      + "service serviceStabilityPercent=\($s // "?")%   (100=all-green; 門檻推測 ≥80 normal / 50-80 wobble / <50 unstable)\n"
      + "pool    healthPercent=\($h // "?")%   ⚠️ 此欄位 2026-08-17 起恆為 0、已不可用作判斷"
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
#   base_url = "https://api.bruceai.net/v1"
#   wire_api = "responses"
#   env_key = "BRUCE_API_KEY"
# Setup done 2026-06-19; base_url re-pointed at api.bruceai.net 2026-08-17.
# NOTE the Codex side DOES need the /v1 suffix — the Anthropic side (ccp-bruce)
# must NOT have it. Bruce documents them separately, and mixing them up 404s.
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
#   - Model routing is now per-id, NOT force-routed to gpt-5.5 as it was under the
#     internal-test proxy (re-probed 2026-08-17). Pick explicitly with
#     `-c model=gpt-5.6-sol`, or in the Codex TUI via /model. Supported ids:
#     gpt-5.6-sol / -terra / -luna / gpt-5.5 / gpt-5.4 / gpt-5.4-mini.
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
      _cc_vendor_claude "$@"
    else
      _cc_vendor_claude --model sonnet "$@"
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
    _cc_vendor_claude --disallowed-tools WebSearch "$@"
  )
}

# ===== CLIProxyAPI relay, all-GPT slot mapping (cross-generation) =====
# Recipe from OpenAI Codex lead Tibo Sottiaux (x.com/thsottiaux/status/2076119366647894371,
# 2026-07-12) plus community fixes from the same thread. Tier mapping per OpenAI's
# official positioning (Astra=flagship, Luna=fast/cheap):
#   FABLE→gpt-6-astra  OPUS/SONNET/HAIKU→gpt-5.6-luna(max)
# Terra dropped from the mapping 2026-08-17 (only the flagship and Luna justify their price).
# Flagship seat moved 5.6-Sol→6-Astra on 2026-09-05; the cheap subagent fleet stays on
# 5.6-Luna deliberately — Astra bills 2.5x Sol, so promoting the fleet would multiply the
# largest consumer. Note this makes the mapping cross-generation, not one model family.
# Context pinned to 1M since 2026-08-17, when OpenAI opened the 1.05M window to
# ChatGPT accounts; measured backend cap is 922,000 (see the probe notes at the
# CLAUDE_CODE_MAX_CONTEXT_TOKENS export below). Both overridable.
# Per-call override:
#   ANTHROPIC_MODEL='gpt-6-astra(high)' ccp-gpt        # effort suffix works
#   CLAUDE_CODE_SUBAGENT_MODEL=gpt-6-astra ccp-gpt     # explicitly override routing

# Which Codex account will actually serve this session. The relay silently falls
# back to the next auth when the preferred one dies (2026-07-25: personal Pro token
# was invalidated server-side and 8 days of traffic went to the work team account
# unnoticed) — so surface it at launch instead of after the fact.
ccp-gpt-whoami() {
  local mgmt_json
  mgmt_json=$(
    source ~/.cli-proxy-api/keys.env 2>/dev/null
    curl -s --max-time 5 -H "Authorization: Bearer ${CLIPROXY_MGMT_KEY}" \
      "${CLIPROXY_BASE_URL:-http://127.0.0.1:8317}/v0/management/auth-files"
  )
  if [[ -z "$mgmt_json" ]]; then
    print -P "%F{yellow}[ccp-gpt] 無法查詢帳號狀態（管理 API 沒回應）%f" >&2
    return 1
  fi

  local rows
  rows=$(printf '%s' "$mgmt_json" | jq -r '
    [.files[] | select(.provider == "codex")]
    | sort_by([-(.priority // 0), .name])
    | .[]
    | (.recent_requests // [])[-6:] as $win
    | [ .email,
        (.id_token.plan_type // "?"),
        ((.priority // 0) | tostring),
        ((.disabled // false) | tostring),
        (($win | map(.success) | add // 0) | tostring),
        (($win | map(.failed)  | add // 0) | tostring),
        ((.success // 0) | tostring),
        ((.failed  // 0) | tostring),
        ((.modtime // "") | .[0:16])
      ] | @tsv') 2>/dev/null

  if [[ -z "$rows" ]]; then
    print -P "%F{yellow}[ccp-gpt] 管理 API 沒回報任何 codex 帳號%f" >&2
    return 1
  fi

  local -a broken=() idle=() ok_list=()
  local serving="" serving_note="" serving_rs=-1 serving_email=""
  local fallback="" fallback_email="" fallback_note="" any_usable=""
  local email plan prio disabled rs rf cs cf modtime health

  while IFS=$'\t' read -r email plan prio disabled rs rf cs cf modtime; do
    if [[ "$disabled" == "true" ]]; then
      health=disabled
    elif (( rf > 0 && rf >= rs )); then
      health=down
    elif (( rs > 0 )); then
      health=ok
    else
      health=idle
    fi

    case "$health" in
      ok)
        any_usable=1
        ok_list+=("${rs}|${email}|${email} (${plan}, priority ${prio}) — 最近一小時 ${rs} 成功 / ${rf} 失敗")
        ;;
      idle)
        any_usable=1
        idle+=("${email}|${email} (${plan}, priority ${prio}) — 無近期流量、健康未知；憑證更新於 ${modtime}")
        if [[ -z "$fallback" ]]; then
          fallback="${email} (${plan})"
          fallback_email="$email"
          fallback_note="無近期流量、健康未知（依 priority ${prio} + 檔名排序推測）"
        fi
        ;;
      down|disabled)
        broken+=("${email} (${plan}, priority ${prio}) — 最近 ${rf} 失敗 / ${rs} 成功；憑證更新於 ${modtime}")
        ;;
    esac
  done <<< "$rows"

  local entry rec
  for entry in "${ok_list[@]}"; do
    rec="${entry%%|*}"
    if (( rec > serving_rs )); then
      serving_rs=$rec
      serving_email="${${entry#*|}%%|*}"
      serving="${entry##*|}"
    fi
  done

  if [[ -n "$serving" ]]; then
    print -P "%F{green}[ccp-gpt] 服務中：${serving}%f" >&2
  elif [[ -n "$fallback" ]]; then
    print -P "%F{yellow}[ccp-gpt] 預計使用：${fallback}%f  — ${fallback_note}" >&2
  fi

  for entry in "${ok_list[@]}"; do
    [[ "${${entry#*|}%%|*}" == "$serving_email" ]] && continue
    print -P "[ccp-gpt] 備援健康：${entry##*|}" >&2
  done

  local shown_fallback=""
  [[ -z "$serving" && -n "$fallback" ]] && shown_fallback="$fallback_email"
  for entry in "${idle[@]}"; do
    [[ "${entry%%|*}" == "$shown_fallback" ]] && continue
    print -P "[ccp-gpt] 備援待命：${entry#*|}" >&2
  done

  if (( ${#broken[@]} > 0 )); then
    for entry in "${broken[@]}"; do
      print -P "%F{red}[ccp-gpt] ⚠️  ${entry}%f" >&2
    done
    print -P "%F{yellow}          priority 高的帳號壞掉時 relay 仍每次先試它、失敗才退回上面那個%f" >&2
    print -P "%F{yellow}          重新登入：~/.cli-proxy-api/bin/cli-proxy-api --config ~/.cli-proxy-api/config.yaml --codex-login%f" >&2
    print -P "%F{yellow}          細節排查：ccp-gpt-whoami / tail -f ~/.cli-proxy-api/logs/main.log%f" >&2
  fi

  local f
  for f in ~/.cli-proxy-api/codex-*.json(N); do
    jq -e 'has("priority")' "$f" >/dev/null 2>&1 && continue
    print -P "%F{yellow}[ccp-gpt] ${f:t} 沒有 priority 欄位（--codex-login 重登會清掉它，視為 0）%f" >&2
    print -P "%F{yellow}          下次重登請用 ccp-gpt-relogin（會自動補回）%f" >&2
  done

  if [[ -z "$any_usable" ]]; then
    print -P "%F{red}[ccp-gpt] 所有 codex 帳號都不可用，這次會直接失敗%f" >&2
    return 1
  fi
  return 0
}

# `--codex-login` builds a fresh auth object and persists only its in-memory
# metadata (sdk/auth/filestore.go:103), so the file's `priority` key is dropped —
# silently demoting the very account the re-login was meant to restore. There is
# no config-level priority for OAuth auths (only for API-key providers), so the
# value has to be put back into the file. Keyed by email, not filename: filenames
# may carry a hash prefix that changes between logins.
ccp-relay-priority-snapshot() {
  local f
  for f in ${CCP_RELAY_AUTH_DIR:-$HOME/.cli-proxy-api}/codex-*.json(N); do
    jq -r 'select(has("priority") and has("email")) | "\(.email)\t\(.priority)"' "$f" 2>/dev/null
  done
}

ccp-relay-priority-apply() {
  local email prio f tmp applied=0
  while IFS=$'\t' read -r email prio; do
    [[ -z "$email" || -z "$prio" ]] && continue
    for f in ${CCP_RELAY_AUTH_DIR:-$HOME/.cli-proxy-api}/codex-*.json(N); do
      jq -e --arg e "$email" '.email == $e' "$f" >/dev/null 2>&1 || continue
      jq -e --argjson p "$prio" '.priority == $p' "$f" >/dev/null 2>&1 && continue
      tmp="${f}.tmp.$$"
      if jq --argjson p "$prio" '.priority = $p' "$f" > "$tmp" 2>/dev/null; then
        chmod 600 "$tmp" && mv "$tmp" "$f"
        print -P "%F{green}[ccp-relay] priority ${prio} 已補回 ${email} (${f:t})%f" >&2
        applied=1
      else
        rm -f "$tmp"
        print -P "%F{red}[ccp-relay] 寫入失敗：${f:t}%f" >&2
      fi
    done
  done
  (( applied )) || print -P "[ccp-relay] priority 無需變更" >&2
  return 0
}

ccp-gpt-relogin() {
  local bin=${CCP_RELAY_AUTH_DIR:-$HOME/.cli-proxy-api}/bin/cli-proxy-api
  if [[ ! -x "$bin" ]]; then
    print -P "%F{red}[ccp-gpt] 找不到可執行檔 ${bin}%f" >&2
    return 1
  fi

  local snapshot
  snapshot=$(ccp-relay-priority-snapshot)
  if [[ -n "$snapshot" ]]; then
    print -P "[ccp-gpt] 登入前記下的 priority：" >&2
    print -r -- "$snapshot" | sed 's/^/  /' >&2
  else
    print -P "%F{yellow}[ccp-gpt] 現有 codex 憑證都沒有 priority 欄位，登入後沒東西可補%f" >&2
  fi

  "$bin" --config "${CCP_RELAY_AUTH_DIR:-$HOME/.cli-proxy-api}/config.yaml" --codex-login "$@" || return

  [[ -n "$snapshot" ]] && print -r -- "$snapshot" | ccp-relay-priority-apply
  sleep 2
  ccp-gpt-whoami
}

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
  ccp-gpt-whoami
  (
    source ~/.cli-proxy-api/keys.env
    unset ANTHROPIC_API_KEY  # relay auth goes through AUTH_TOKEN (Bearer)
    export CC_VENDOR=gpt
    export ANTHROPIC_BASE_URL=$CLIPROXY_BASE_URL
    export ANTHROPIC_AUTH_TOKEN=$CLIPROXY_KEY_CC
    export ANTHROPIC_MODEL=${ANTHROPIC_MODEL:-gpt-6-astra}
    export ANTHROPIC_DEFAULT_FABLE_MODEL=${ANTHROPIC_DEFAULT_FABLE_MODEL:-gpt-6-astra}
    export ANTHROPIC_DEFAULT_OPUS_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL:-gpt-5.6-luna(max)}"
    # OPUS/SONNET/HAIKU land on Luna at pinned max effort. Terra is retired
    # from the mapping: in practice only Sol and Luna earn their price, and Terra sat in
    # the middle being neither. The `(model)(effort)` suffix is parsed by the relay and
    # overrides whatever effort CC sends — verified by request-log A/B: CC sent
    # `output_config {"effort":"low"}` with model `gpt-5.6-luna(max)`, relay forwarded
    # `reasoning {"effort":"max"}` upstream (2/2 runs). That is why per-agent effort in
    # ~/.claude/agents/routed-*.md stays untouched: the suffix wins locally without
    # touching the cross-vendor routing policy.
    export ANTHROPIC_DEFAULT_SONNET_MODEL="${ANTHROPIC_DEFAULT_SONNET_MODEL:-gpt-5.6-luna(max)}"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-gpt-5.6-luna(max)}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION=${ANTHROPIC_CUSTOM_MODEL_OPTION:-gpt-6-astra-fast}
    export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME=${ANTHROPIC_CUSTOM_MODEL_OPTION_NAME:-GPT-6\ Astra\ Fast}
    export ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION=${ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION:-Priority\ tier\ for\ the\ main\ agent}
    export CLAUDE_CODE_ALWAYS_ENABLE_EFFORT=${CLAUDE_CODE_ALWAYS_ENABLE_EFFORT:-1}
    export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=${CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY:-3}
    # OpenAI opened the 1M window to ChatGPT-account Codex on 2026-08-17 (Tibo,
    # x.com/thsottiaux/status/2089082893804896524 plus the follow-up "just flipped the
    # switch"). Re-probed the relay the same day by binary search: 921,504 accepted /
    # ~921,998 rejected, so the backend ceiling is 922,000 = the documented 1,050,000
    # window minus the fixed 128k output reserve (max_tokens=64 on the probe did not
    # move it). terra and luna both cleared 492,719; their own ceilings are unprobed.
    # Codex metadata still reports 272000 and stays untrustworthy.
    # Value below matches Tibo's recommended Codex config rather than the 922,000
    # ceiling: usable space is identical either way (compaction governs at 867,000),
    # the difference is only where CC's local wall lands — 977,000 here, i.e. above the
    # backend ceiling, so a >55k single-turn injection past the compaction line gets
    # sent and refused rather than blocked locally. Relay refusals read "Your input
    # exceeds the context window of this model.", which CC does not recognise as a
    # too-long error, so there is no retry ladder — recovery is a manual /compact.
    # Set this to 940000 to move the local wall under the ceiling and close that gap.
    # Also drives the statusline's context_window_size (/context reports
    # AUTO_COMPACT_WINDOW instead).
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1000000}
    # Compact fires at min(window, max_context) - min(max_output, 20k) - 13k = 867,000,
    # leaving 55,000 to the backend ceiling. CC only measures at turn boundaries, so it
    # always fires above the nominal line: worst overshoot across 44 real auto-compacts
    # was 21,415, which lands at 888,415 — clear of 922,000. The residual exposure is a
    # single turn injecting more than 55,000 at once (3 concurrent tool calls at the
    # 25,000 MCP cap would reach 75,000).
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-900000}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    # Stream idle watchdog: CC aborts a turn with "Stream idle timeout - no chunks
    # received" when the response stream stays silent for this long. Third-party
    # endpoints floor at max(env, 300000) (CC 2.1.241 NQS/Gza), so the default is 5 min;
    # sol at xhigh can sit in reasoning longer than that before its first byte and gets
    # misread as a dead connection (2 sol sessions in 2026-07 jsonl). 10 min borrowed from
    # remora-cc v0.1.18. Only cost: a genuinely dead stream waits 10 min instead of 5.
    export CLAUDE_STREAM_IDLE_TIMEOUT_MS=${CLAUDE_STREAM_IDLE_TIMEOUT_MS:-600000}
    export CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS=${CLAUDE_BYTE_STREAM_IDLE_TIMEOUT_MS:-600000}
    # Single-shot injection caps: oversized MCP output spills to a temp file, oversized
    # bash output truncates with a [KB removed] marker. These bound the overshoot past
    # the compaction line, which is what keeps the run clear of the 922,000 ceiling.
    export MAX_MCP_OUTPUT_TOKENS=${MAX_MCP_OUTPUT_TOKENS:-25000}
    export BASH_MAX_OUTPUT_LENGTH=${BASH_MAX_OUTPUT_LENGTH:-30000}
    # Tibo's alias sets false outright; GPT models' deferred-tool handling unverified.
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-false}
    # Subagent propagation is the --append-subagent-system-prompt FLAG's job, not the
    # env var's. Probed on 2.1.239 (2026-08-22, marker ZQX7741 in the system prompt,
    # routed-mech subagent asked to echo it back): with only
    # CLAUDE_CODE_ENABLE_APPEND_SUBAGENT_PROMPT=1 the subagent answered NONE while the
    # main session answered ZQX7741, i.e. the env var alone is inert — it is the gate,
    # not the carrier. Re-run with the flag and the same subagent answered ZQX7741.
    # The flag is hidden from --help (@internal in the binary) and its own help string
    # says "only works with --print". Confirmed: the same marker probe run against an
    # INTERACTIVE ccp-gpt returned NONE, with the subagent's recorded prompt verified
    # clean (69 chars, no marker, no rule text). So the flag covers headless only and
    # the IMPORTANT clause in the injection below is what covers interactive — that
    # clause is load-bearing, not decorative: in a probe that explicitly ordered the
    # main session NOT to pass the rules along, it pasted all 434 characters into the
    # subagent prompt anyway.
    # WebSearch: same unprobed relay translation path as ccp-relay (docs/caveats.md §13b).
    # Skill(claude-api): unblocked 2026-08-25 (trial claude-api-skill-unblock, review
    # 2026-09-01). The 2026-07-14 "Prompt is too long" (session c83482eb) came from an
    # older CC that injected ~800KB in one shot; CC 2.1.243 loads it progressively and a
    # headless probe on this launcher measured 52,879 → 71,875 input tokens (~19k per
    # invoke). Still trigger-happy on any Claude/LLM mention — if the trial shows several
    # invokes per session, isolate it behind a claude-api-lookup agent instead of re-blocking.
    # --model flag beats settings.json "model" (user pins claude-fable-5[1m] there,
    # which otherwise silently overrides ANTHROPIC_MODEL and mis-routes on the relay).
    # --append-system-prompt: two harness-usage rules this vendor gets wrong by default,
    # measured across 27 gpt-5.6-sol sessions (2026-08-22). (1) Polling: Claude-family
    # sessions dispatched 170 agents across 9 large sessions and called TaskOutput 4 times
    # total; gpt-5.6-sol runs sit at 1.0-3.5 polls per dispatch — session 9638d4b9 spent
    # 6.9h of a 40h span blocked on 149 TaskOutput calls (106 at timeout>=5min) against
    # 96 dispatches, while opus-4-6 session 16f5bfe6 polled once against 90. (2) Path
    # switching: same session, a permit packet missing one blank line was answered by
    # leaving CC for a headless `claude -p` run, which cost two classifier timeouts,
    # $2.28, and 0 critics started before the model concluded in-session dispatch was
    # right all along. Lives in the system prompt layer, so compaction reuses it verbatim
    # (docs/en/prompt-caching: compaction replaces message history, reuses system prompt);
    # ~/.claude/hooks/gpt-convergence-reminder.sh carries the same rules on the
    # SessionStart(compact) path for GPT sessions this launcher did not start.
    local _rules="背景工作等待：Agent 與背景 Bash 完成時，harness 會自動送 task-notification 回來喚醒 session，不需要主動確認。派工後直接進行下一件不相依的工作，不要用 TaskOutput block=true 站著等結果；只有在沒有其他可做的事、且必須拿到該結果才能繼續時才查一次，查完仍未完成就回去做別的，不要連續輪詢。撞錯先修根因：遇到格式、參數、路徑、空行這類小失敗，先判斷根因是否三行內可修，可修就直接修，不要因為一個小錯改走另一條執行路徑（改跑 headless claude -p、換一套工具鏈、繞去別的入口）——換路會帶進一整組新的失敗模式，而原始根因仍未解決；確實需要換路時，先說明為什麼根因不可修，再換。人類專屬點交還上限：撞到只有使用者能做或能拍板的事（sudo／GUI 操作／互動式 auth／憑證設定／系統升級，或範圍・權威・對外行為・風險的拍板），同一點最多嘗試 2 次，用盡即交還、不得換路硬撐。交還內容自包含（讀的人沒有你的對話與檔案）：脈絡一句／每個選項附一句後果／建議＋理由一句；能標假設續跑的先列「我假設 1…N」續跑，不能的就收工。"
    _cc_vendor_claude --effort xhigh --model "$ANTHROPIC_MODEL" \
      --disallowed-tools 'WebSearch' \
      --append-system-prompt "${_rules}IMPORTANT: 派 Task subagent 或 workflow agent 時，把上面三條逐字放進它們的 prompt。互動模式下 subagent 不會繼承本注入，只有 --print 模式才會。" \
      --append-subagent-system-prompt "$_rules" \
      "$@"
  )
}

ccp-gpt-fast() {
  (
    export ANTHROPIC_DEFAULT_OPUS_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL:-gpt-6-astra}"
    if [[ -n "${ANTHROPIC_CUSTOM_HEADERS:-}" ]]; then
      export ANTHROPIC_CUSTOM_HEADERS="${ANTHROPIC_CUSTOM_HEADERS}"$'\n'"X-CCP-Fast: 1"
    else
      export ANTHROPIC_CUSTOM_HEADERS="X-CCP-Fast: 1"
    fi
    ccp-gpt "$@"
  )
}

ccp-gpt-smart() {
  (
    local custom_headers
    custom_headers="$(print -r -- "${ANTHROPIC_CUSTOM_HEADERS:-}" | /usr/bin/grep -vFx -- 'X-CCP-Fast: 1')"
    if [[ -n "$custom_headers" ]]; then
      export ANTHROPIC_CUSTOM_HEADERS="$custom_headers"
    else
      unset ANTHROPIC_CUSTOM_HEADERS
    fi
    ANTHROPIC_MODEL=gpt-6-astra \
    ANTHROPIC_DEFAULT_FABLE_MODEL=gpt-6-astra \
    ANTHROPIC_DEFAULT_OPUS_MODEL=gpt-6-astra \
    ANTHROPIC_DEFAULT_SONNET_MODEL=gpt-6-astra \
    ANTHROPIC_DEFAULT_HAIKU_MODEL=gpt-6-astra \
    CLAUDE_CODE_SUBAGENT_MODEL=gpt-6-astra \
      ccp-gpt "$@"
  )
}

# Roll back to the pre-Astra flagship without editing ccp-gpt. Every slot in
# ccp-gpt reads ${VAR:-default}, so presetting them here restores the exact
# configuration that shipped before 2026-09-05 — same delegation pattern as
# ccp-gpt-smart. The fleet slots (OPUS/SONNET/HAIKU→luna) never moved during the
# Astra promotion, so they are deliberately absent here.
# For the pre-Astra fast tier: ANTHROPIC_DEFAULT_OPUS_MODEL=gpt-5.6-sol ccp-gpt-fast
ccp-sol() {
  (
    ANTHROPIC_MODEL=gpt-5.6-sol \
    ANTHROPIC_DEFAULT_FABLE_MODEL=gpt-5.6-sol \
    ANTHROPIC_CUSTOM_MODEL_OPTION=gpt-5.6-sol-fast \
    ANTHROPIC_CUSTOM_MODEL_OPTION_NAME='GPT-5.6 Sol Fast' \
      ccp-gpt "$@"
  )
}

# ===== CLIProxyAPI relay, Gemini via Antigravity OAuth (qwe70301 AI Pro) =====
# Split into two entry points because the Pro and Flash tiers draw on the same
# subscription quota at very different rates — keeping them separate makes the
# choice explicit at launch instead of buried in a slot table.
#
# Effort control (2026-08-07 probe, 3 rounds, stable):
#   Model-name suffix WORKS — 'gemini-pro-agent(high)' and '(xhigh)' reliably
#   produce thinking blocks (1532-1602 / 1320-1452 chars); bare name and '(low)'
#   produce none (0/0/0). Parsed by CLIProxyAPI's reasoningEffortFromSuffix.
#   CC's own effort selector does NOT work — output_config.effort={low,medium,
#   high,xhigh} all yield 0 thinking chars; the relay strips reasoning effort for
#   models with no thinking levels in its registry. So CLAUDE_CODE_ALWAYS_ENABLE_EFFORT
#   is deliberately left off here: the picker would render but change nothing.
#   high vs xhigh showed no consistent gap — Antigravity looks binary (on/off).
#
# Context window: 1,048,576 hard cap, stated verbatim by the upstream reject
# ("exceeds the maximum number of tokens allowed 1048576") and confirmed by probe
# (1,045,010 accepted / above it rejected). Same ceiling on Pro and Flash. That is
# still above the 922k Codex ceiling (2026-08-17), so Skill(claude-api) is NOT blocked here.
#
# Per-call override:
#   ANTHROPIC_MODEL='gemini-pro-agent(xhigh)' ccp-gemini-pro
#   ANTHROPIC_MODEL=gemini-3.1-pro-low ccp-gemini-pro   # cheaper Pro brain

# Shared pre-flight: relay liveness + Antigravity credential visibility. Every
# Gemini model hangs off a single OAuth account (unlike ccp-gpt's two Codex
# accounts), so surface which one is carrying the session before launch.
_ccp-gemini-preflight() {
  local caller=$1
  if [[ ! -f ~/.cli-proxy-api/keys.env ]]; then
    echo "$caller: ~/.cli-proxy-api/keys.env not found. See cliproxyapi-setup/CLAUDE.md" >&2
    return 1
  fi
  if ! /usr/bin/nc -z 127.0.0.1 8317 2>/dev/null; then
    echo "[$caller] relay not listening, kickstarting launchd service..." >&2
    launchctl kickstart "gui/$UID/com.philip.cli-proxy-api" 2>/dev/null
    local i=0
    while (( i < 50 )); do
      /usr/bin/nc -z 127.0.0.1 8317 2>/dev/null && break
      sleep 0.1; ((i++))
    done
    if (( i >= 50 )); then
      print -P "%F{red}[$caller] relay did not become ready in 5s — check ~/.cli-proxy-api/logs/%f" >&2
      return 1
    fi
  fi

  local -a auths=(${HOME}/.cli-proxy-api/antigravity-*.json(N))
  if (( ${#auths} == 0 )); then
    print -P "%F{red}[$caller] 找不到 Antigravity 憑證 — Gemini 全線不可用%f" >&2
    print -P "%F{red}          重登：~/.cli-proxy-api/bin/cli-proxy-api --config ~/.cli-proxy-api/config.yaml --antigravity-login%f" >&2
    return 1
  fi

  if command -v jq >/dev/null 2>&1; then
    local email disabled expired
    email=$(jq -r '.email // "?"'     "${auths[1]}" 2>/dev/null)
    disabled=$(jq -r '.disabled // false' "${auths[1]}" 2>/dev/null)
    expired=$(jq -r '.expired // "?"'  "${auths[1]}" 2>/dev/null)
    if [[ "$disabled" == "true" ]]; then
      print -P "%F{red}[$caller] Antigravity 帳號 $email 被停用中 — 這次會直接失敗%f" >&2
      return 1
    fi
    print -P "%F{green}[$caller] 服務中：$email%f（憑證到期 ${expired}，relay 常駐時會自動續）" >&2
  fi
  return 0
}

# Pro tier — Gemini 3.1 Pro High. Thinking on by default via the (high) suffix.
ccp-gemini-pro() {
  _ccp-gemini-preflight ccp-gemini-pro || return 1
  (
    source ~/.cli-proxy-api/keys.env
    unset ANTHROPIC_API_KEY  # relay auth goes through AUTH_TOKEN (Bearer)
    export CC_VENDOR=gemini-pro
    export ANTHROPIC_BASE_URL=$CLIPROXY_BASE_URL
    export ANTHROPIC_AUTH_TOKEN=$CLIPROXY_KEY_CC
    export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-gemini-pro-agent(high)}"
    export ANTHROPIC_DEFAULT_FABLE_MODEL="${ANTHROPIC_DEFAULT_FABLE_MODEL:-gemini-pro-agent(high)}"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL:-gemini-pro-agent(high)}"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="${ANTHROPIC_DEFAULT_SONNET_MODEL:-gemini-pro-agent}"
    # HAIKU slot stays on Flash: background summarisation does not need Pro quota.
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-gemini-3.5-flash-low}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION="${ANTHROPIC_CUSTOM_MODEL_OPTION:-gemini-3.1-pro-low}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="${ANTHROPIC_CUSTOM_MODEL_OPTION_NAME:-Gemini 3.1 Pro Low}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION="${ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION:-Cheaper Pro brain, thinking off}"
    export CLAUDE_CODE_SUBAGENT_MODEL="${CLAUDE_CODE_SUBAGENT_MODEL:-gemini-pro-agent}"
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1048576}
    # Same 22k gap ccp-gpt leaves for compact overshoot; no Gemini overshoot
    # sample exists yet, so this is borrowed rather than measured.
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-1026000}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    # WebSearch: same unprobed relay translation path as ccp-relay / ccp-gpt
    # (docs/caveats.md §13b). Unlike ccp-gpt, Skill(claude-api) stays allowed —
    # its ~200k-token injection fits the 1M window.
    _cc_vendor_claude --model "$ANTHROPIC_MODEL" --disallowed-tools WebSearch "$@"
  )
}

# Flash tier — same 1M window, a fraction of the quota burn. Thinking off by
# default; append (high) to any slot to turn it on.
ccp-gemini-flash() {
  _ccp-gemini-preflight ccp-gemini-flash || return 1
  (
    source ~/.cli-proxy-api/keys.env
    unset ANTHROPIC_API_KEY
    export CC_VENDOR=gemini-flash
    export ANTHROPIC_BASE_URL=$CLIPROXY_BASE_URL
    export ANTHROPIC_AUTH_TOKEN=$CLIPROXY_KEY_CC
    export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-gemini-3.7-flash-high}"
    export ANTHROPIC_DEFAULT_FABLE_MODEL="${ANTHROPIC_DEFAULT_FABLE_MODEL:-gemini-3.7-flash-high}"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL:-gemini-3.7-flash-high}"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="${ANTHROPIC_DEFAULT_SONNET_MODEL:-gemini-3.7-flash-high}"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="${ANTHROPIC_DEFAULT_HAIKU_MODEL:-gemini-3.7-flash-high}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION="${ANTHROPIC_CUSTOM_MODEL_OPTION:-gemini-3.7-flash-high(high)}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="${ANTHROPIC_CUSTOM_MODEL_OPTION_NAME:-Gemini 3.7 Flash Thinking}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION="${ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION:-Same Flash model with reasoning turned on}"
    export CLAUDE_CODE_SUBAGENT_MODEL="${CLAUDE_CODE_SUBAGENT_MODEL:-gemini-3.7-flash-high}"
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1048576}
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-1026000}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    _cc_vendor_claude --model "$ANTHROPIC_MODEL" --disallowed-tools WebSearch "$@"
  )
}

ccp-free-whoami() {
  local caller="${1:-ccp-free}"
  local accounts_file="${CCP_FREE_ACCOUNTS_FILE:-$HOME/.cline2api/.cline-accounts.json}"
  local request_log_file="${CCP_FREE_REQUEST_LOG_FILE:-$HOME/.cline2api/.cline-request-logs.json}"
  local config_file="${CCP_FREE_CONFIG_FILE:-$HOME/.cli-proxy-api/config.yaml}"
  local litellm_config_file="${CCP_FREE_LITELLM_CONFIG_FILE:-$HOME/Desktop/projects/local-llm-gateway/config/litellm.config.yaml}"
  local agentrouter_config_file="${CCP_FREE_AGENTROUTER_CONFIG_FILE:-$HOME/.local/share/litellm-agentrouter/config/agentrouter.config.yaml}"
  local litellm_log_file="${CCP_FREE_LITELLM_LOG_FILE:-$HOME/.local/state/litellm/calls-$(date +%F).jsonl}"
  local curl_bin="${CCP_FREE_CURL_BIN:-/usr/bin/curl}"
  local bai_liveliness_url="${CCP_FREE_BAI_LIVELINESS_URL:-http://127.0.0.1:8000/health/liveliness}"
  local agentrouter_liveliness_url="${CCP_FREE_AGENTROUTER_LIVELINESS_URL:-http://127.0.0.1:8002/health/liveliness}"
  local now="${CCP_FREE_NOW:-$(date '+%Y-%m-%dT%H:%M:%S')}"
  local since="${CCP_FREE_SINCE:-$(date -v-1H '+%Y-%m-%dT%H:%M:%S')}"
  local route_states=$'unknown\tabsent\t\t'

  if [[ -r "$config_file" ]]; then
    route_states=$(awk '
      function route_label(value) {
        if (value == "cline-free-glm") return "Cline GLM"
        if (value == "bai-glm") return "B.AI GLM"
        if (value == "agentrouter-glm") return "AgentRouter GLM"
        if (value == "cline-free-ds") return "Cline DeepSeek"
        if (value == "freellmapi") return "FreeLLMAPI"
        return value
      }
      function add_owner(owner_priority, owner_label, i) {
        i = owner_count
        while (i > 0 && owner_priorities[i] < owner_priority) {
          owner_priorities[i + 1] = owner_priorities[i]
          owner_labels[i + 1] = owner_labels[i]
          i--
        }
        owner_priorities[i + 1] = owner_priority
        owner_labels[i + 1] = owner_label
        owner_count++
      }
      function commit() {
        if (name == "freellmapi") freel = disabled ? "disabled" : (has_free ? "enabled" : "missing-free")
        if (!disabled && has_free) {
          free_count++
          add_owner(priority, route_label(name))
        }
      }
      BEGIN { name = ""; disabled = 0; has_free = 0; priority = 0; free_count = 0; free_route = ""; owner_count = 0; freel = "absent" }
      /^  - name:/ {
        commit()
        line = $0
        sub(/^.*name:[[:space:]]*"?/, "", line)
        sub(/"?[[:space:]]*$/, "", line)
        name = line
        disabled = 0
        has_free = 0
        priority = 0
        next
      }
      name != "" && /^[[:space:]]+priority:/ {
        line = $0
        sub(/^.*priority:[[:space:]]*/, "", line)
        priority = line + 0
      }
      name != "" && /^[[:space:]]+disabled:[[:space:]]+true/ { disabled = 1 }
      name != "" && /^[[:space:]]+alias:[[:space:]]*"?free"?[[:space:]]*$/ { has_free = 1 }
      END {
        commit()
        free_route = ""
        next_fallback = ""
        for (i = 1; i <= owner_count; i++) {
          free_route = free_route (free_route == "" ? "" : " → ") owner_labels[i]
          if (next_fallback == "" && owner_labels[i] != "Cline GLM") next_fallback = owner_labels[i]
        }
        print (free_count > 0 ? "enabled" : "disabled") "\t" freel "\t" free_route "\t" next_fallback
      }
    ' "$config_file" 2>/dev/null)
  fi

  local free_route_state freellmapi_state free_route_chain next_fallback
  IFS=$'\t' read -r free_route_state freellmapi_state free_route_chain next_fallback <<< "$route_states"
  if [[ "$free_route_state" != "enabled" ]]; then
    if [[ "$freellmapi_state" == "enabled" ]]; then
      print -P "%F{yellow}[$caller] 預計切換：FreeLLMAPI — 目前 free route 沒有 active alias=free owner%f" >&2
    else
      print -P "%F{red}[$caller] ⚠️  免費池 route 目前停用%f" >&2
    fi
    [[ "$freellmapi_state" == "disabled" ]] && print -P "[$caller] FreeLLMAPI：已停用，不在目前路由" >&2
    print -P "%F{yellow}          細節排查：ccp-free-whoami / tail -f ~/.cline2api/service.log%f" >&2
    return 0
  fi

  print -P "[$caller] free(max) route（config）：${free_route_chain}（上游健康未知）" >&2

  local bai_deployments='unknown' agentrouter_deployments='unknown'
  if [[ -r "$litellm_config_file" ]]; then
    bai_deployments=$(awk '$1 == "-" && $2 == "model_name:" && $3 == "bai-glm" { count++ } END { print count + 0 }' "$litellm_config_file" 2>/dev/null)
  fi
  if [[ -r "$agentrouter_config_file" ]]; then
    agentrouter_deployments=$(awk '$1 == "-" && $2 == "model_name:" && $3 == "agentrouter-glm" { count++ } END { print count + 0 }' "$agentrouter_config_file" 2>/dev/null)
  fi

  local bai_gateway='down' agentrouter_gateway='down'
  "$curl_bin" -fsS --max-time 1 -o /dev/null "$bai_liveliness_url" >/dev/null 2>&1 && bai_gateway='up'
  "$curl_bin" -fsS --max-time 1 -o /dev/null "$agentrouter_liveliness_url" >/dev/null 2>&1 && agentrouter_gateway='up'

  local bai_observed_status='unknown' bai_observed_ts=''
  local agentrouter_observed_status='unknown' agentrouter_observed_ts=''
  local litellm_summary=''
  if [[ -r "$litellm_log_file" ]]; then
    litellm_summary=$(jq -sr '
      def latest($group; $prefix):
        [.[]
          | select(
              ((.metadata.model_group // "") == $group)
              or (((.api_base // "") | startswith($prefix))))]
        | sort_by(.end_ts // .ts // "")
        | last // {};
      (latest("bai-glm"; "https://api.b.ai/v1")) as $bai
      | (latest("agentrouter-glm"; "https://agentrouter.org/v1")) as $agentrouter
      | [
          ($bai.status // "unknown"),
          ($bai.end_ts // $bai.ts // ""),
          ($agentrouter.status // "unknown"),
          ($agentrouter.end_ts // $agentrouter.ts // "")
        ]
      | join("|")
    ' "$litellm_log_file" 2>/dev/null) || litellm_summary=''
  fi
  if [[ -n "$litellm_summary" ]]; then
    IFS='|' read -r bai_observed_status bai_observed_ts agentrouter_observed_status agentrouter_observed_ts <<< "$litellm_summary"
  fi

  local bai_observed='unknown' agentrouter_observed='unknown'
  [[ -n "$bai_observed_ts" ]] && bai_observed="${bai_observed_status} ${bai_observed_ts}"
  [[ -n "$agentrouter_observed_ts" ]] && agentrouter_observed="${agentrouter_observed_status} ${agentrouter_observed_ts}"
  local bai_line='' agentrouter_line=''
  if [[ "$free_route_chain" == *"B.AI GLM"* ]]; then
    bai_line="[$caller] B.AI GLM：gateway ${bai_gateway}；${bai_deployments} deployments；最近 ${bai_observed}；quota unknown"
  fi
  if [[ "$free_route_chain" == *"AgentRouter GLM"* ]]; then
    agentrouter_line="[$caller] AgentRouter GLM：gateway ${agentrouter_gateway}；${agentrouter_deployments} deployments；最近 ${agentrouter_observed}；quota／cooldown unknown"
  fi

  local summary
  summary=$(jq -nr \
    --slurpfile state "$accounts_file" \
    --slurpfile requests "$request_log_file" \
    --arg now "$now" \
    --arg since "$since" '
      def accounts: ($state[0].accounts // []);
      def active_accounts:
        [accounts[] | select((.status // "") == "active")];
      def available($model):
        [active_accounts[]
          | select((((.modelCooldowns // {})[$model] // "")[0:19]) as $until
            | ($until == "" or $until <= $now))];
      def normalize_model:
        sub("\\([^()]*\\)$"; "");
      def normalized_requests:
        (($requests[0] // [])
          | map(. + {normalized_model: ((.model // "") | normalize_model)})
          | map(select(
              ((.finishedAt // "")[0:19] >= $since)
              and (.normalized_model == "z-ai/glm-5.3-flash" or .normalized_model == "deepseek/deepseek-v4-flash"))));
      def recent_for($model):
        (normalized_requests
          | map(select(.normalized_model == $model))
          | sort_by(.finishedAt)
          | last // {});
      (normalized_requests | sort_by(.finishedAt) | last // {}) as $recent
      | (recent_for("z-ai/glm-5.3-flash")) as $glm_recent
      | (recent_for("deepseek/deepseek-v4-flash")) as $ds_recent
      | [
          (active_accounts | length),
          (available("z-ai/glm-5.3-flash") | length),
          (available("deepseek/deepseek-v4-flash") | length),
          ($recent.normalized_model // ""),
          (if ($recent | has("completed")) then ($recent.completed | tostring) else "" end),
          (if ($glm_recent | has("completed")) then ($glm_recent.completed | tostring) else "" end),
          ($glm_recent.finishedAt // ""),
          (if ($ds_recent | has("completed")) then ($ds_recent.completed | tostring) else "" end),
          ($ds_recent.finishedAt // "")
        ]
      | join("|")
    ' 2>/dev/null) || {
    print -P "%F{yellow}[$caller] 無法查詢免費池狀態（invalid cline2api status data）%f" >&2
    [[ -n "$bai_line" ]] && print -r -- "$bai_line" >&2
    [[ -n "$agentrouter_line" ]] && print -r -- "$agentrouter_line" >&2
    return 0
  }

  local account_total glm_available ds_available recent_model recent_completed
  local glm_recent_completed glm_recent_ts ds_recent_completed ds_recent_ts
  IFS='|' read -r account_total glm_available ds_available recent_model recent_completed glm_recent_completed glm_recent_ts ds_recent_completed ds_recent_ts <<< "$summary"
  local glm_observed='unknown' ds_observed='unknown'
  if [[ -n "$glm_recent_ts" ]]; then
    [[ "$glm_recent_completed" == "true" ]] && glm_observed="success ${glm_recent_ts}" || glm_observed="failure ${glm_recent_ts}"
  fi
  if [[ -n "$ds_recent_ts" ]]; then
    [[ "$ds_recent_completed" == "true" ]] && ds_observed="success ${ds_recent_ts}" || ds_observed="failure ${ds_recent_ts}"
  fi
  local recent_failed=0
  if [[ "$recent_completed" == "false" ]]; then
    recent_failed=1
    if [[ "$recent_model" == "z-ai/glm-5.3-flash" ]]; then
      print -P "%F{yellow}[$caller] ⚠️  最近請求失敗：GLM — ${glm_recent_ts:-unknown}%f" >&2
    elif [[ "$recent_model" == "deepseek/deepseek-v4-flash" ]]; then
      print -P "%F{yellow}[$caller] ⚠️  最近請求失敗：DeepSeek — ${ds_recent_ts:-unknown}%f" >&2
    fi
  fi

  local primary_glm=0
  if [[ "$recent_completed" == "true" && "$recent_model" == "z-ai/glm-5.3-flash" ]] && (( glm_available > 0 )); then
    primary_glm=1
    print -P "%F{green}[$caller] 服務中：GLM 帳號池（free(max)）— ${glm_available}/${account_total} 帳號可用；最近 ${glm_observed}%f" >&2
  elif [[ "$recent_completed" == "true" && "$recent_model" == "deepseek/deepseek-v4-flash" ]] && (( ds_available > 0 )); then
    print -P "%F{green}[$caller] 服務中：DeepSeek fallback（free(max)）— 最近 ${ds_observed}%f" >&2
  elif (( glm_available > 0 )); then
    primary_glm=1
    if (( recent_failed )); then
      print -P "%F{yellow}[$caller] 預計使用：GLM 帳號池（free(max)）— 近期失敗後仍有 ${glm_available}/${account_total} 帳號可用%f" >&2
    else
      print -P "%F{yellow}[$caller] 預計使用：GLM 帳號池（free(max)）— 無近期流量，${glm_available}/${account_total} 帳號可用%f" >&2
    fi
  elif [[ -n "$next_fallback" && "$next_fallback" != "Cline DeepSeek" ]]; then
    print -P "%F{yellow}[$caller] 預計切換：${next_fallback}（上游健康未知）— Cline GLM 帳號池目前不可用%f" >&2
  elif (( ds_available > 0 )); then
    print -P "%F{yellow}[$caller] 預計切換：DeepSeek — GLM 帳號池目前不可用%f" >&2
  else
    print -P "%F{red}[$caller] ⚠️  免費池目前沒有可用來源%f" >&2
  fi

  [[ -n "$bai_line" ]] && print -r -- "$bai_line" >&2
  [[ -n "$agentrouter_line" ]] && print -r -- "$agentrouter_line" >&2

  if (( primary_glm )); then
    if (( ds_available > 0 )); then
      print -P "[$caller] 備援待命：DeepSeek — ${ds_available}/${account_total} 帳號可用；最近 ${ds_observed}" >&2
    else
      print -P "%F{yellow}[$caller] ⚠️  DeepSeek 備援目前不可用%f" >&2
    fi
  fi

  if (( account_total > glm_available )); then
    print -P "%F{yellow}[$caller] ⚠️  GLM 帳號池：${glm_available}/${account_total} 可用，其餘 cooldown／daily limit%f" >&2
  fi

  if [[ "$freellmapi_state" == "disabled" ]]; then
    print -P "[$caller] FreeLLMAPI：已停用，不在目前路由" >&2
  elif [[ "$freellmapi_state" == "enabled" ]]; then
    print -P "%F{yellow}[$caller] FreeLLMAPI：已設定，健康未知%f" >&2
  fi

  if (( recent_failed || glm_available == 0 || ds_available == 0 )); then
    print -P "%F{yellow}          細節排查：ccp-free-whoami / tail -f ~/.cline2api/service.log%f" >&2
  fi
  return 0
}

ccp-free() {
  local nc_bin="${CCP_FREE_NC_BIN:-/usr/bin/nc}"
  local launchctl_bin="${CCP_FREE_LAUNCHCTL_BIN:-/usr/bin/launchctl}"
  local sleep_bin="${CCP_FREE_SLEEP_BIN:-/bin/sleep}"
  local keys_file="${CCP_FREE_KEYS_FILE:-$HOME/.cli-proxy-api/keys.env}"
  local claude_bin="${CCP_FREE_CLAUDE_BIN:-${CC_CLAUDE_BIN:-claude}}"
  local relay_service='com.philip.cli-proxy-api'

  if [[ ! -f "$keys_file" ]]; then
    print -P "%F{red}[ccp-free] keys file is missing: $keys_file%f" >&2
    return 1
  fi

  if ! "$nc_bin" -z 127.0.0.1 8317 2>/dev/null; then
    echo "[ccp-free] relay not listening, kickstarting launchd service..." >&2
    "$launchctl_bin" kickstart "gui/$UID/$relay_service" >/dev/null 2>&1
    local i=0
    while (( i < 50 )); do
      "$nc_bin" -z 127.0.0.1 8317 2>/dev/null && break
      "$sleep_bin" 0.1
      ((i++))
    done
    if (( i >= 50 )); then
      print -P "%F{red}[ccp-free] relay did not become ready in 5s — check ~/.cli-proxy-api/logs/%f" >&2
      return 1
    fi
  fi
  (
    source "$keys_file"
    if [[ -z "${CLIPROXY_BASE_URL-}" || -z "${CLIPROXY_KEY_CC-}" ]]; then
      print -P "%F{red}[ccp-free] keys file must define CLIPROXY_BASE_URL and CLIPROXY_KEY_CC%f" >&2
      exit 1
    fi
    ccp-free-whoami ccp-free
    unset ANTHROPIC_API_KEY ANTHROPIC_FALLBACK_MODEL CLAUDE_CODE_FALLBACK_MODEL DISABLE_COMPACT
    export CC_VENDOR=free
    export ANTHROPIC_BASE_URL=$CLIPROXY_BASE_URL
    export ANTHROPIC_AUTH_TOKEN=$CLIPROXY_KEY_CC
    export ANTHROPIC_MODEL="${ANTHROPIC_MODEL:-free(max)}"
    export ANTHROPIC_DEFAULT_FABLE_MODEL='free(max)'
    export ANTHROPIC_DEFAULT_OPUS_MODEL='free(max)'
    export ANTHROPIC_DEFAULT_SONNET_MODEL='free(max)'
    export ANTHROPIC_DEFAULT_HAIKU_MODEL='free(max)'
    export ANTHROPIC_CUSTOM_MODEL_OPTION="${ANTHROPIC_CUSTOM_MODEL_OPTION:-free(max)}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="${ANTHROPIC_CUSTOM_MODEL_OPTION_NAME:-Free chain (Cline GLM → B.AI GLM → AgentRouter GLM → Cline DeepSeek)}"
    export ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION="${ANTHROPIC_CUSTOM_MODEL_OPTION_DESCRIPTION:-Cline GLM first; B.AI GLM next; AgentRouter GLM next; Cline DeepSeek last}"
    export CLAUDE_CODE_SUBAGENT_MODEL='free(max)'
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-1048576}
    export CLAUDE_CODE_AUTO_COMPACT_WINDOW=${CLAUDE_CODE_AUTO_COMPACT_WINDOW:-1000000}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    command "$claude_bin" --model "$ANTHROPIC_MODEL" --disallowed-tools WebSearch "$@"
  )
}

ccp-mix-gpt() {
  local nc_bin="${CCP_FREE_NC_BIN:-/usr/bin/nc}"
  local launchctl_bin="${CCP_FREE_LAUNCHCTL_BIN:-/usr/bin/launchctl}"
  local sleep_bin="${CCP_FREE_SLEEP_BIN:-/bin/sleep}"
  local keys_file="${CCP_FREE_KEYS_FILE:-$HOME/.cli-proxy-api/keys.env}"
  local claude_bin="${CCP_FREE_CLAUDE_BIN:-${CC_CLAUDE_BIN:-claude}}"
  local relay_service='com.philip.cli-proxy-api'

  if [[ ! -f "$keys_file" ]]; then
    print -P "%F{red}[ccp-mix-gpt] keys file is missing: $keys_file%f" >&2
    return 1
  fi

  if ! "$nc_bin" -z 127.0.0.1 8317 2>/dev/null; then
    echo "[ccp-mix-gpt] relay not listening, kickstarting launchd service..." >&2
    "$launchctl_bin" kickstart "gui/$UID/$relay_service" >/dev/null 2>&1
    local i=0
    while (( i < 50 )); do
      "$nc_bin" -z 127.0.0.1 8317 2>/dev/null && break
      "$sleep_bin" 0.1
      ((i++))
    done
    if (( i >= 50 )); then
      print -P "%F{red}[ccp-mix-gpt] relay did not become ready in 5s — check ~/.cli-proxy-api/logs/%f" >&2
      return 1
    fi
  fi
  (
    source "$keys_file"
    if [[ -z "${CLIPROXY_BASE_URL-}" || -z "${CLIPROXY_KEY_CC-}" ]]; then
      print -P "%F{red}[ccp-mix-gpt] keys file must define CLIPROXY_BASE_URL and CLIPROXY_KEY_CC%f" >&2
      exit 1
    fi
    local main_model="${ANTHROPIC_MODEL:-gpt-6-astra}"
    local main_label="$main_model"
    [[ "$main_model" == "gpt-6-astra" ]] && main_label="GPT-6 Astra"
    print -P "%F{green}[ccp-mix-gpt] Main：${main_label}%f" >&2
    ccp-free-whoami ccp-mix-gpt
    unset ANTHROPIC_API_KEY ANTHROPIC_FALLBACK_MODEL CLAUDE_CODE_FALLBACK_MODEL DISABLE_COMPACT
    if [[ "$main_model" == *[Gg][Pp][Tt]* ]]; then
      export CC_VENDOR=mix-gpt
    else
      export CC_VENDOR=mix
    fi
    export ANTHROPIC_BASE_URL=$CLIPROXY_BASE_URL
    export ANTHROPIC_AUTH_TOKEN=$CLIPROXY_KEY_CC
    export ANTHROPIC_MODEL="$main_model"
    export ANTHROPIC_DEFAULT_FABLE_MODEL='gpt-6-astra'
    export ANTHROPIC_DEFAULT_OPUS_MODEL='free(max)'
    export ANTHROPIC_DEFAULT_SONNET_MODEL='free(max)'
    export ANTHROPIC_DEFAULT_HAIKU_MODEL='free(max)'
    export CLAUDE_CODE_SUBAGENT_MODEL='free(max)'
    export CLAUDE_CODE_MAX_CONTEXT_TOKENS=${CLAUDE_CODE_MAX_CONTEXT_TOKENS:-480000}
    export API_TIMEOUT_MS=${API_TIMEOUT_MS:-3000000}
    export ENABLE_TOOL_SEARCH=${ENABLE_TOOL_SEARCH:-auto}
    export CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY=${CLAUDE_CODE_MAX_TOOL_USE_CONCURRENCY:-3}
    command "$claude_bin" --model "$ANTHROPIC_MODEL" --disallowed-tools WebSearch "$@"
  )
}

# ===== Helper: list available functions =====
ccp-list() {
  cat <<EOF
Available cc-vendor-bridge functions:

  ccp-deepseek      → DeepSeek V4-Pro / V4-Flash
  ccp-deepseek-flash → DeepSeek V4-Flash (all model slots forced)
  ccp-deepseek-pro   → DeepSeek V4-Pro (all model slots forced)
  ccp-glm           → Zhipu GLM-5.1 / 4.7-Flash (z.ai intl)
  ccp-mimo          → Xiaomi MiMo V2.5-Pro Token Plan (Singapore subscription)
  ccp-mimo-payg     → Xiaomi MiMo V2.5-Pro (intl PAYG)
  ccp-bruce         → BRUCEAI gateway api.bruceai.net, prepaid credits, GPT-5.6 slot mapping
                      (OPUS+FABLE→sol / SONNET+HAIKU→luna, --effort high, 272K window)
                      Context pinned at the 272K billing cliff: past it the whole request
                      is rebilled at 2x input / 1.5x output. Override: ANTHROPIC_MODEL=... /
                      CCP_BRUCE_EFFORT=max
  ccp-local         → Rapid-MLX local (auto-detect model via /v1/models on :8002, Apple Silicon, zero cost)
                      Override: LOCAL_MODEL=... / RAPID_MLX_LOCAL_URL=...
                      Needs vllm_mlx tool-content-flatten patch for Qwen3.6 strict template (see local-model-bench FINDINGS §8.6)
  ccp-free          → CLIProxyAPI free(max) chain: Cline GLM → B.AI GLM → AgentRouter GLM → Cline DeepSeek (:8317)
  ccp-relay         → CLIProxyAPI self-hosted relay :8317 (default gpt-5.5 via Codex team OAuth;
                      HAIKU slot→ds-flash free pool; claude-sonnet-4-6 / gemini-pro-agent via Antigravity)
                      Override: ANTHROPIC_MODEL=<any relay model> ccp-relay; WebSearch disabled until probed
  ccp-gpt           → CLIProxyAPI relay, cross-gen slot mapping (FABLE→astra / OPUS+SONNET+HAIKU→luna(max),
                      Astra effort xhigh / Luna effort pinned by suffix / subagent routing preserved), Tibo-recipe env vars (effort on,
                      concurrency 3, 1M context, tool search off)
  ccp-mix-gpt       → Mixed-tier mapping: FABLE+main→gpt-6-astra, OPUS/SONNET/HAIKU+subagents→free(max)
                      (= same free chain: Cline GLM → B.AI GLM → AgentRouter GLM → Cline DeepSeek, :8317)
                      480K context window (shared free-chain ceiling)
  ccp-gpt-fast      → Same routing and context as ccp-gpt, except Opus defaults to gpt-6-astra;
                      priority service tier for all Codex requests
  ccp-gpt-smart     → All model slots forced to gpt-6-astra on the Standard service tier
  ccp-sol           → Pre-Astra rollback: ccp-gpt routing with FABLE+main on gpt-5.6-sol
                      and the picker option on sol-fast (fleet slots unchanged)
  ccp-gpt-whoami    → Which Codex account actually serves ccp-gpt + which ones are dead
                      (runs automatically as a ccp-gpt pre-flight; call standalone to re-check)
  ccp-gpt-relogin   → Re-auth a Codex account AND restore the priority that --codex-login
                      strips (upstream PR #3843, unmerged). Use instead of raw --codex-login.
  ccp-relay-priority-snapshot / -apply
                    → The snapshot/restore halves, usable standalone if priority went missing
  /model picker      → Choose GPT-6 Astra Fast and press s for this session only; routed subagents stay Standard

  ccp-gemini-pro    → CLIProxyAPI relay, Gemini 3.1 Pro High via Antigravity OAuth
                      (OPUS/FABLE→gemini-pro-agent(high) / SONNET→gemini-pro-agent /
                      HAIKU→gemini-3.5-flash-low), 1,048,576 context, thinking on
  ccp-gemini-flash  → Same relay and 1M context, all slots on Gemini 3.7 Flash;
                      thinking off by default, /model picker offers the thinking variant
                      Effort: use the model-name suffix, NOT CC's effort picker —
                      ANTHROPIC_MODEL='gemini-pro-agent(xhigh)' ccp-gemini-pro
                      (CC's output_config.effort is stripped by the relay for Gemini)

  ccp-resume        → 互動 picker 選 prior session resume，自動 dispatch 對應 vendor
                      (workaround caveat 11: 跨 vendor resume 會炸 thinking signature)

  ccp-bruce-status  → Bruce snapshot：預付額度餘額 (/v1/usage) + service stability
                      額度換算 21 credits = US\$1；(--json 印合併原始)
                      ⚠️ 舊的 /v1/usage/quota 已壞（空 body / 500），已改讀 /v1/usage
  ccp-bruce-watch   → Bruce 長期守護 watcher (serviceStabilityPercent 單 metric threshold
                      觸發，jsonl log 落檔，macOS notification)
                      ⚠️ healthPercent 2026-08-17 起恆為 0、gate 已預設關閉；
                      要重啟用：--critical-below 20 之類明確給值

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
    echo "[ccp-resume] resuming via selected Claude Code binary (model=$model)"
    ANTHROPIC_MODEL="$model" _cc_vendor_claude --resume "$fullsid"
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
