#!/usr/bin/env zsh
# cc-vendor-bridge — Path 1 sidecar wrappers
#
# Each ccp-*-rescue function = Path 0 function + `claude -p` headless mode.
# Lets a vendor model run a full agent loop (Read/Write/Edit/Bash/MCP) and
# print the final assistant message to stdout. Equivalent to codex-rescue
# but for non-Anthropic vendors.
#
# Usage from main Claude session via Bash tool:
#   ccp-deepseek-rescue "讀 src/foo.ts 並重構成 async/await，跑 npm test"
#
# Setup (one-time):
#   Add to ~/.zshrc AFTER sourcing ccp-functions.sh:
#     source /path/to/cc-vendor-bridge/plugin/sidecar.sh
#
# Safety:
#   --dangerously-skip-permissions = no permission prompts (headless can't
#   show them). Acceptable when wrapper is called from your own main Claude
#   session in your own repos. Override per-call by passing different flags
#   in "$@" (e.g. --allowedTools Read,Bash).
#
# See docs/path-1-sidecar-design.md for full architecture rationale.

# =============================================================================
# Two flavours per vendor:
#   ccp-<vendor>-ask     → headless plain-text query, NO tool access.
#                          Use when you only need a text response (review,
#                          explanation, translation, opinion). Faster, safer.
#   ccp-<vendor>-rescue  → headless full agent loop with skip-permissions.
#                          Use when the task needs Read/Write/Edit/Bash/MCP
#                          (refactor, run tests, multi-file inspection).
#
# Decision tree for callers (incl. main Claude session dispatching via Bash):
#   • Pure text question → -ask
#   • Needs to touch files / run commands → -rescue
#   • Unsure → start with -ask, escalate to -rescue if the model says it
#     needs tool access.
# =============================================================================

# DeepSeek
ccp-deepseek-ask()    { ccp-deepseek -p "$@"; }
ccp-deepseek-rescue() { ccp-deepseek -p --dangerously-skip-permissions "$@"; }

# DISABLED: MOONSHOT_API_KEY not configured
# ccp-kimi-ask()    { ccp-kimi -p "$@"; }
# ccp-kimi-rescue() { ccp-kimi -p --dangerously-skip-permissions "$@"; }

# DISABLED: MOONSHOT_CN_API_KEY not configured
# ccp-kimi-cn-ask()    { ccp-kimi-cn -p "$@"; }
# ccp-kimi-cn-rescue() { ccp-kimi-cn -p --dangerously-skip-permissions "$@"; }

# GLM
ccp-glm-ask()    { ccp-glm -p "$@"; }
ccp-glm-rescue() { ccp-glm -p --dangerously-skip-permissions "$@"; }

# DISABLED: BIGMODEL_API_KEY not configured
# ccp-glm-cn-ask()    { ccp-glm-cn -p "$@"; }
# ccp-glm-cn-rescue() { ccp-glm-cn -p --dangerously-skip-permissions "$@"; }

# DISABLED: DASHSCOPE_INTL_API_KEY not configured
# ccp-qwen-ask()    { ccp-qwen -p "$@"; }
# ccp-qwen-rescue() { ccp-qwen -p --dangerously-skip-permissions "$@"; }

# DISABLED: QWEN_CODING_PLAN_KEY not configured
# ccp-qwen-coding-ask()    { ccp-qwen-coding -p "$@"; }
# ccp-qwen-coding-rescue() { ccp-qwen-coding -p --dangerously-skip-permissions "$@"; }

# MiMo
ccp-mimo-ask()         { ccp-mimo -p "$@"; }
ccp-mimo-rescue()      { ccp-mimo -p --dangerously-skip-permissions "$@"; }
ccp-mimo-payg-ask()    { ccp-mimo-payg -p "$@"; }
ccp-mimo-payg-rescue() { ccp-mimo-payg -p --dangerously-skip-permissions "$@"; }

ccp-rescue-list() {
  cat <<'EOF'
Available cc-vendor-bridge Path 1 sidecar functions:

  TEXT-ONLY QUERY (no tool access, faster, safer):
    ccp-deepseek-ask      → DeepSeek V4-Pro headless plain-text
    ccp-glm-ask           → GLM-5.1 headless plain-text (z.ai intl)
    ccp-mimo-ask          → MiMo V2.5-Pro headless plain-text (Token Plan)
    ccp-mimo-payg-ask     → MiMo V2.5-Pro headless plain-text (PAYG)

  FULL AGENT LOOP (Read/Write/Edit/Bash/MCP, skip-permissions):
    ccp-deepseek-rescue   → DeepSeek V4-Pro agent
    ccp-glm-rescue        → GLM-5.1 agent
    ccp-mimo-rescue       → MiMo V2.5-Pro agent (Token Plan)
    ccp-mimo-payg-rescue  → MiMo V2.5-Pro agent (PAYG)

  Disabled (API key not configured):
    ccp-kimi-* / ccp-kimi-cn-* / ccp-glm-cn-*
    ccp-qwen-* / ccp-qwen-coding-*

Decision tree:
  • Plain text question / review / opinion → use -ask
  • Needs to read/write files or run commands → use -rescue

Each runs `claude -p ...` with vendor env routed via cc-vendor-bridge proxy.
Pass the task as the first argument; final assistant message goes to stdout.

WARNING: -rescue uses --dangerously-skip-permissions. Only invoke for
trusted task descriptions in your own repos. -ask is safe by default.
EOF
}
