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
└── pricing-snapshot.md            # vendor pricing (per-vendor LAST_VERIFIED inside)

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

## 即時模型映射表

重新載入 shell 函式後，可手動查看完整非直連映射：

```bash
ccp-list
ccp-list ccp-sol
```

第二個指令仍顯示整張表，但將查詢入口置頂。互動啟動時，支援的 ccp 入口及 `cc-luna`／`cc-free` 會先顯示同張表，標記「▶ 本次啟動」；print 與非互動模式不自動插入表格。

資料直接取自啟動器的唯讀預覽、共用 GPT 版本表與現行免費池設定，不另維護槽位字串。表格描述設定值，不代表上游健康、quota 或實際模型權重已驗證；缺資料時顯示未知。啟動後的 `/model` 切換不會持續更新這張啟動表。

顯示程式使用 Python 的 Rich 與 PyYAML。顯示失敗只回報診斷，不更改既有模型選擇。已開啟的 shell 需重新 source 啟動器，或開啟新的 shell，才會載入新函式。

局部驗證配方：

```bash
python3 tests/test_model_map.py
python3 tests/test_launch_model_map.py
```

測試以隔離版本／relay 設定、偽終端和假 CC 程式觀察實際啟動器輸出，不呼叫真實模型或啟停服務。

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

Pricing + benchmark data: per-vendor `LAST_VERIFIED` table inside [`docs/pricing-snapshot.md`](docs/pricing-snapshot.md). Rule: any row > 30 days from `LAST_VERIFIED` MUST be re-verified before being cited in a decision (learned 2026-06-19 after DeepSeek $1.50/$4.50 misquote, real number $0.435/$0.87).

## Inspiration

- [`codex:codex-rescue`](https://github.com/anthropics/codex-rescue) — sidecar pattern for offloading to OpenAI Codex
- DeepSeek's official Claude Code integration doc — surfaced 2026-05-03

## License

MIT (planned). Personal project — no warranty, no support commitment.
