# cc-vendor-bridge

Personal toolkit for plugging non-Anthropic LLM vendors into Claude Code CLI without giving up the CC ecosystem (skills, MCP, hooks, CLAUDE.md, subagents).

**Status:** Stage 2 — DeepSeek verified production-ready (2026-05-03). Kimi / GLM / Qwen pending vendor sign-up. Path 1 sidecar plugin not yet built.

See [`docs/stage-2-playbook.md`](docs/stage-2-playbook.md) for the per-vendor onboarding protocol.

## Three paths

| Path | What it does | Status |
|---|---|---|
| **Path 0 — Vendor-native Anthropic endpoint** | `ANTHROPIC_BASE_URL` env var swap; vendor exposes Anthropic-format API; CC unaware | ✅ Ready (4 vendors covered) |
| **Path 1 — Sidecar (CC offloads sub-task)** | CC stays on Claude; offloads specific tasks to other vendor via Bash wrapper or MCP, like `codex:codex-rescue` does for OpenAI | 📋 Planned |
| ~~Path 2 — Router (CCR / LiteLLM)~~ | ~~Community proxy translates Anthropic ↔ OpenAI~~ | ❌ Skipped — CCR maintainer退場 4 個月，LiteLLM CC compat 5 bug 全 OPEN |

## Why this exists

- Original DeepSeek doc surfaced 2026-05-03 — `ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic` works without any router/proxy
- All 4 major CN models (DeepSeek / Kimi / GLM / Qwen) ship official Anthropic-native endpoints
- Sidecar pattern (Path 1) lets CC offload one-shot tasks to other vendor CLIs (Qwen-Code, Kimi-CLI) without leaving Claude
- Per-token billing on these endpoints does NOT touch Anthropic Pro/Max quota

## Layout

```
docs/                              # research + design notes + Stage 2 protocol
├── path-0-anthropic-native.md     # 4-vendor endpoint reference
├── path-1-sidecar-design.md       # plugin pattern (planned)
├── caveats.md                     # 10 caveats catalogued; DeepSeek results
├── stage-2-playbook.md            # onboarding protocol for new vendors
└── pricing-snapshot-2026-05.md    # vendor pricing (stale-by 2026-08)

shell/
├── ccp-functions.sh               # 7 zsh functions (ccp-deepseek / kimi / glm / qwen variants)
└── secrets.example                # API key template (DO NOT commit real keys)

proxy/                             # caveat 9 fix — DeepSeek tool_choice rewriter
├── server.ts                      # Bun proxy on 127.0.0.1:9091
├── launchd.plist                  # macOS auto-start daemon
├── package.json                   # bun scripts
└── README.md                      # install + verify

plugin/                            # Path 1 sidecar (Stage 3, not started)
tests/                             # smoke tests for cache/thinking/subagent verification
```

## Quick start (Path 0 only)

```bash
# 1. Set up secrets
cp shell/secrets.example ~/.zsh_secrets
chmod 600 ~/.zsh_secrets
# edit ~/.zsh_secrets, fill in your API keys

# 2. Source functions
echo "[[ -f ~/.zsh_secrets ]] && source ~/.zsh_secrets" >> ~/.zshrc
echo "source $(pwd)/shell/ccp-functions.sh" >> ~/.zshrc
exec zsh

# 3. Use
ccp-deepseek    # opens CC pointed at DeepSeek
ccp-kimi        # opens CC pointed at Kimi
ccp-glm         # opens CC pointed at z.ai GLM
ccp-qwen        # opens CC pointed at Qwen / DashScope intl
```

Each function uses a subshell so env vars don't leak into your main shell. Your default `claude` command still hits Anthropic.

## Caveats — verify before relying on these

The vendor docs don't list these failure modes. 10 caveats catalogued so far:

**Vendor-side test dimensions (5 — verify per vendor):**
1. Prompt cache — `cache_control` honored or silently stripped?
2. Extended thinking — `thinking` block schema
3. MCP tool schema — 64-char name + nested schema
4. CLAUDE.md adherence — language + style rule following
5. Subagent dispatch — Task tool emit + per-vendor `*_SUBAGENT_MODEL` env var

**CC client-side limits (3 — affect all third-party vendors):**
6. Context window 200K fallback — fix via `DISABLE_COMPACT=1` + `CLAUDE_CODE_MAX_CONTEXT_TOKENS=<size>`
7. ToolSearch defer disabled — fix via `ENABLE_TOOL_SEARCH=auto`
8. Stop hook nudges vendor model → unwanted memory writes — fix via `CC_VENDOR` marker + hook Defense 0

**Vendor-side bugs found during Stage 2 (2 — vendor-specific):**
9. DeepSeek `tool_choice: {type:tool, name:X}` rejected — fix via `proxy/server.ts` rewrite to `{type:any}`
10. Vendor self-describe hallucinates about CC internal config — no fix, document only

See [`docs/caveats.md`](docs/caveats.md) for full test plan + DeepSeek verification results.

## Stale-by

Pricing + benchmark data: **2026-08-03**. CN models update monthly.

## Inspiration

- [`codex:codex-rescue`](https://github.com/anthropics/codex-rescue) — sidecar pattern for offloading to OpenAI Codex
- DeepSeek's official Claude Code integration doc — surfaced 2026-05-03

## License

MIT (planned). Personal project — no warranty, no support commitment.
