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

ccp-deepseek-rescue() {
  ccp-deepseek -p --dangerously-skip-permissions "$@"
}

ccp-kimi-rescue() {
  ccp-kimi -p --dangerously-skip-permissions "$@"
}

ccp-kimi-cn-rescue() {
  ccp-kimi-cn -p --dangerously-skip-permissions "$@"
}

ccp-glm-rescue() {
  ccp-glm -p --dangerously-skip-permissions "$@"
}

ccp-glm-cn-rescue() {
  ccp-glm-cn -p --dangerously-skip-permissions "$@"
}

ccp-qwen-rescue() {
  ccp-qwen -p --dangerously-skip-permissions "$@"
}

ccp-qwen-coding-rescue() {
  ccp-qwen-coding -p --dangerously-skip-permissions "$@"
}

ccp-rescue-list() {
  cat <<'EOF'
Available cc-vendor-bridge Path 1 sidecar functions:

  ccp-deepseek-rescue      → DeepSeek V4-Pro headless agent
  ccp-kimi-rescue          → Kimi K2.5 headless (intl)
  ccp-kimi-cn-rescue       → Kimi K2.5 headless (大陸)
  ccp-glm-rescue           → GLM-4.7 headless (z.ai intl)
  ccp-glm-cn-rescue        → GLM-4.7 headless (bigmodel 大陸)
  ccp-qwen-rescue          → Qwen3-Max headless (Singapore)
  ccp-qwen-coding-rescue   → Qwen Coding Plan headless

Each runs `claude -p --dangerously-skip-permissions` with vendor env.
Pass the task as argument; final assistant message goes to stdout.

Equivalent to codex-rescue pattern for non-Anthropic vendors.

WARNING: --dangerously-skip-permissions allows all tool calls without
prompting. Only use for trusted task descriptions in your own repos.
Override per-call by passing different flags after the task string.
EOF
}
