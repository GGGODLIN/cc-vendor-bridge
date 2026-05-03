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
#   etc.

# ===== DeepSeek V4-Pro =====
# Source: https://api-docs.deepseek.com/zh-cn/quick_start/agent_integrations/claude_code
ccp-deepseek() {
  if [[ -z "$DEEPSEEK_API_KEY" ]]; then
    echo "ccp-deepseek: DEEPSEEK_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
    export ANTHROPIC_AUTH_TOKEN=$DEEPSEEK_API_KEY
    export ANTHROPIC_MODEL=deepseek-v4-pro
    export ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro
    export ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
    export CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
    export CLAUDE_CODE_EFFORT_LEVEL=max
    export ENABLE_TOOL_SEARCH=auto
    claude "$@"
  )
}

# ===== Moonshot Kimi K2.5 (international PAYG) =====
# Source: https://platform.kimi.ai/docs/guide/agent-support
ccp-kimi() {
  if [[ -z "$MOONSHOT_API_KEY" ]]; then
    echo "ccp-kimi: MOONSHOT_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic
    export ANTHROPIC_AUTH_TOKEN=$MOONSHOT_API_KEY
    export ANTHROPIC_MODEL=kimi-k2.5
    export ENABLE_TOOL_SEARCH=auto
    claude "$@"
  )
}

# ===== Moonshot Kimi 大陸 PAYG =====
# Source: https://platform.kimi.com/docs/guide/agent-support
ccp-kimi-cn() {
  if [[ -z "$MOONSHOT_CN_API_KEY" ]]; then
    echo "ccp-kimi-cn: MOONSHOT_CN_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export ANTHROPIC_BASE_URL=https://api.moonshot.cn/anthropic
    export ANTHROPIC_AUTH_TOKEN=$MOONSHOT_CN_API_KEY
    export ANTHROPIC_MODEL=kimi-k2.5
    export ENABLE_TOOL_SEARCH=auto
    claude "$@"
  )
}

# ===== Zhipu GLM (z.ai international) =====
# Source: https://docs.z.ai/scenario-example/develop-tools/claude
ccp-glm() {
  if [[ -z "$ZAI_API_KEY" ]]; then
    echo "ccp-glm: ZAI_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
    export ANTHROPIC_AUTH_TOKEN=$ZAI_API_KEY
    export ANTHROPIC_DEFAULT_OPUS_MODEL=GLM-4.7
    export ANTHROPIC_DEFAULT_SONNET_MODEL=GLM-4.7
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=GLM-4.5-Air
    export API_TIMEOUT_MS=3000000
    export ENABLE_TOOL_SEARCH=auto
    claude "$@"
  )
}

# ===== Zhipu GLM 大陸 (bigmodel) =====
# Source: https://docs.bigmodel.cn/cn/guide/develop/claude
ccp-glm-cn() {
  if [[ -z "$BIGMODEL_API_KEY" ]]; then
    echo "ccp-glm-cn: BIGMODEL_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export ANTHROPIC_BASE_URL=https://open.bigmodel.cn/api/anthropic
    export ANTHROPIC_AUTH_TOKEN=$BIGMODEL_API_KEY
    export ANTHROPIC_DEFAULT_OPUS_MODEL=GLM-4.7
    export ANTHROPIC_DEFAULT_SONNET_MODEL=GLM-4.7
    export ANTHROPIC_DEFAULT_HAIKU_MODEL=GLM-4.5-Air
    export API_TIMEOUT_MS=3000000
    export ENABLE_TOOL_SEARCH=auto
    claude "$@"
  )
}

# ===== Alibaba Qwen Max (international Singapore PAYG) =====
# Source: https://www.alibabacloud.com/help/en/model-studio/claude-code
# Defaults to qwen3-max because thinking mode only works on Max series
ccp-qwen() {
  if [[ -z "$DASHSCOPE_INTL_API_KEY" ]]; then
    echo "ccp-qwen: DASHSCOPE_INTL_API_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/apps/anthropic
    export ANTHROPIC_AUTH_TOKEN=$DASHSCOPE_INTL_API_KEY
    export ANTHROPIC_MODEL=qwen3-max
    export ENABLE_TOOL_SEARCH=auto
    claude "$@"
  )
}

# ===== Alibaba Qwen Coding Plan (subscription, separate quota) =====
ccp-qwen-coding() {
  if [[ -z "$QWEN_CODING_PLAN_KEY" ]]; then
    echo "ccp-qwen-coding: QWEN_CODING_PLAN_KEY not set. See shell/secrets.example" >&2
    return 1
  fi
  (
    export ANTHROPIC_BASE_URL=https://coding-intl.dashscope.aliyuncs.com/apps/anthropic
    export ANTHROPIC_AUTH_TOKEN=$QWEN_CODING_PLAN_KEY
    export ANTHROPIC_MODEL=qwen3-coder-next
    export ENABLE_TOOL_SEARCH=auto
    claude "$@"
  )
}

# ===== Helper: list available functions =====
ccp-list() {
  cat <<EOF
Available cc-vendor-bridge functions:

  ccp-deepseek      → DeepSeek V4-Pro / V4-Flash
  ccp-kimi          → Moonshot Kimi K2.5 (intl PAYG)
  ccp-kimi-cn       → Moonshot Kimi K2.5 (大陸 PAYG)
  ccp-glm           → Zhipu GLM-4.7 / 4.5-Air (z.ai intl)
  ccp-glm-cn        → Zhipu GLM-4.7 / 4.5-Air (bigmodel CN)
  ccp-qwen          → Alibaba Qwen3-Max (Singapore intl PAYG)
  ccp-qwen-coding   → Alibaba Qwen Coding Plan (subscription)

Each opens a Claude Code session backed by that vendor.
Pass any args you'd pass to 'claude' (e.g. '-c', '/path/to/proj').

To switch mid-conversation: Ctrl-D to exit, then run a different ccp-* function.
EOF
}
