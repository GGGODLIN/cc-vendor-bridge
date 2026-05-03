# cc-vendor-bridge

Personal toolkit for plugging non-Anthropic LLM vendors into Claude Code CLI without giving up the CC ecosystem (skills, MCP, hooks, CLAUDE.md, subagents).

**Status:** Stage 1 — research + Path 0 zsh functions ready. Path 1 sidecar plugin not yet built.

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
docs/                              # research + design notes (Path 0 + Path 1)
├── path-0-anthropic-native.md     # 4-vendor endpoint reference
├── path-1-sidecar-design.md       # plugin pattern (planned)
├── caveats.md                     # what each vendor breaks (待實測)
└── pricing-snapshot-2026-05.md    # vendor pricing (stale-by 2026-08)

shell/
├── ccp-functions.sh               # 4 zsh functions: ccp-deepseek / ccp-kimi / ccp-glm / ccp-qwen
└── secrets.example                # API key template (DO NOT commit real keys)

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

The vendor docs don't list these failure modes. Real verification needed before treating any path as "done":

1. **Prompt cache** — does `cache_control` actually work, or get silently stripped?
2. **Extended thinking** — only Qwen Max series confirmed; others unknown
3. **MCP tool schema** — 64-char name limits, nested schemas
4. **Subagent dispatch** — only DeepSeek explicitly documents `CLAUDE_CODE_SUBAGENT_MODEL`
5. **CLAUDE.md adherence** — vs Claude on language constraints, hook responses

See `docs/caveats.md` for the test plan.

## Stale-by

Pricing + benchmark data: **2026-08-03**. CN models update monthly.

## Inspiration

- [`codex:codex-rescue`](https://github.com/anthropics/codex-rescue) — sidecar pattern for offloading to OpenAI Codex
- DeepSeek's official Claude Code integration doc — surfaced 2026-05-03

## License

MIT (planned). Personal project — no warranty, no support commitment.
