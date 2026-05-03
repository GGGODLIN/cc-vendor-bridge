# Path 1 — Sidecar Pattern (Planned)

CC stays on Claude as orchestrator. Specific sub-tasks are offloaded to other vendor CLIs/APIs via Bash wrapper or MCP. Like [`codex:codex-rescue`](https://github.com/anthropics/codex-rescue) does for OpenAI Codex.

**Status: not started.** This doc captures the design ahead of implementation so we know what we're building when we get to Stage 3.

## When you'd want this vs Path 0

- **Path 0** — 整段 session 用其他 vendor model（throwaway exploration、跑 cheap test、用 1M context model 處理長檔）
- **Path 1** — 主 session 仍用 Claude，但**特定 task** 想找 second opinion / 特殊能力（例如 Qwen 的 1M context 摘要、Kimi K2.6 的 SWE-Pro 強項、DeepSeek V4-Pro 75% off cheap fallback）

Path 1 keeps Claude orchestrating + ecosystem intact; Path 0 swaps the orchestrator entirely.

## Reference: how `codex-rescue` does it

`codex` CLI has `codex exec --json` mode → one-shot run, structured event JSON to stdout, exit code signals success/failure. The `codex-rescue` plugin wraps this so CC can call `codex exec --json "..."` from a Bash subagent.

Pattern: `parent agent (Claude) → subagent dispatch → Bash → external CLI --json → parse stdout → return to parent`.

## Per-vendor delegation tier

Verified 2026-05-03:

| Vendor | Tier | Mechanism | Verified |
|---|---|---|---|
| **Qwen-Code** | 1 (drop-in) | `qwen -p "..." -o json --auth-type openai --openai-api-key $KEY` | ✅ v0.15.6 (2026-04-30 push); `--bare` flag like codex skip-auto-discovery; `--json-fd` / `--json-file` 雙輸出 |
| **Kimi-CLI** | 2 (一次性 setup) | `kimi --print -p "..." --output-format=stream-json` | ✅ v1.41.0 (2026-04-30); JSONL 輸出 + exit code 0/1/75; 但要先 `/login` 互動式設 API key |
| **DeepSeek** | 3 (curl + jq) | `curl /v1/chat/completions` + `jq` | OpenAI-compat endpoint，無官方 CLI，5 行 bash wrapper 即可 |
| **GLM (z.ai)** | 3 | `curl https://api.z.ai/api/paas/v4/chat/completions` + `jq` | OpenAI-compat |
| **DashScope** | 3 | `curl` 或借 qwen-code 當 wrapper | 無獨立 dashscope CLI |
| **MiniMax MMX-CLI** | 1.5 | `mmx text chat --message "..."` | 官方 MIT；agent-first 設計；JSON 輸出 flag 不在 public docs sample，需安裝後驗證 |
| **TRAE Agent** | — | — | ❌ Skip — 2026-02-05 last commit (3 個月停滯) + 不是 ByteDance 模型專屬 CLI（generic agent runner 吃 OpenAI/Anthropic key） |

⚠️ **MiniMax-MCP 官方 server 不能用作 text delegation**——只暴露 multimodal tools (TTS / image / video / music / voice / vision)，沒 chat tool。

## 設計：CC plugin scaffold

```
plugin/
├── plugin.json                # CC plugin manifest
├── agents/
│   ├── deepseek-rescue.md     # subagent (description + tool restrictions)
│   ├── kimi-rescue.md
│   ├── glm-rescue.md
│   └── qwen-rescue.md
├── commands/
│   ├── deepseek.md            # /deepseek slash command
│   ├── kimi.md
│   ├── glm.md
│   └── qwen.md
└── lib/
    ├── deepseek-call.sh       # bash wrapper：curl + jq parse
    ├── kimi-call.sh           # 包 kimi-cli `--print --output-format=stream-json`
    ├── glm-call.sh            # 同 deepseek，不同 endpoint
    └── qwen-call.sh           # 包 qwen-code `-p ... -o json`
```

每支 wrapper 50–150 行 bash。整包預估 300–600 行 code。

## Agent definition 模板

```markdown
---
name: deepseek-rescue
description: Offload a specific coding task to DeepSeek V4-Pro. Use when (a) need 1M context, (b) need cheap throwaway analysis, (c) Claude is stuck and want a second opinion. NOT for tasks requiring CLAUDE.md adherence — DeepSeek may not honor user constraints as faithfully as Claude.
tools: Bash, Read
---

You are a thin wrapper around DeepSeek V4-Pro. Your job is to:

1. Take the task description from the parent agent
2. Call `lib/deepseek-call.sh "<task>"`
3. Parse JSON response
4. Return findings to parent

Do NOT do the task yourself. You are a relay.
```

## Slash command 模板

```markdown
---
description: Offload current task to DeepSeek V4-Pro for second opinion
---

Read the user's most recent message. Dispatch a `deepseek-rescue` subagent with the task and any relevant context. Format the subagent's response as a "Second opinion from DeepSeek" block.
```

## 實作優先順序

1. **Qwen-rescue first** — qwen-code CLI 最成熟，--output-format json 直接可用，Tier 1 drop-in 風險最低
2. **DeepSeek-rescue second** — Tier 3 curl wrapper，5 行 bash，但要驗證 streaming JSON parse 穩定
3. **Kimi-rescue third** — 要先處理 `/login` 互動 setup，最複雜
4. **GLM-rescue last** — 跟 DeepSeek 同模式，可參考前者；如果 Coding Plan 訂閱才訂

## 開放設計問題

- **要不要每家做完整 plugin，還是先做 1 個共用 scaffold（`vendor-rescue` agent，按參數選 vendor）？** 後者 code 量小但 less specific
- **Qwen-rescue 要走 qwen-code CLI 還是直接 curl？** CLI 較成熟但需要先 `npm install -g`；curl 無依賴但要自己處理 streaming
- **Plugin 要走 CC plugin marketplace 標準 (`.claude/plugins/`)，還是輕量手動 install？**
