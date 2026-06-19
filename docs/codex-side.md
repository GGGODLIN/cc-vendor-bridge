# Codex side: Path 0 OpenAI-mirror

Anthropic 側 `ccp-bruce` 的對位文件。這份 doc 講 Codex CLI 怎麼透過 OpenAI Responses 路徑接上同一個 Bruce 中轉站後端 — `ccp-*` 家族的 OpenAI 側鏡像軸。

Status 2026-06-19：Path 0 設置完成、smoke 待驗。

## Goal

把非 OpenAI vendor（目前 Bruce、未來可擴 deepseek-codex / glm-codex 等）插進 [Codex CLI](https://github.com/openai/codex)，**不破壞既有 ChatGPT Team OAuth 直連流程**。常態走 OpenAI 直連，撞額度時 per-invocation 切 vendor。

對比 cc-vendor-bridge 既有 Anthropic 側 framework：

| 維度 | Anthropic side (CC) | OpenAI side (Codex) |
|---|---|---|
| 主程式 | `claude` CLI | `codex` CLI |
| Wire protocol | Anthropic `/v1/messages` (SSE) | OpenAI Responses `/v1/responses` (SSE) |
| Path 0 swap 機制 | `ANTHROPIC_BASE_URL` env var | `~/.codex/config.toml` `[model_providers.<id>]` + `-c model_provider=<id>` 或 `CODEX_HOME` |
| Per-invocation 切換 | 不行（env var session-wide） | ✅ `-c model_provider=<id>` 單次 override |
| Wrapper 命名 | `ccp-<vendor>` | `codex-<vendor>` |

## 三條 review 流程並存（同 Bruce 後端）

| 命令 | 走哪 | 用什麼 prompt | 何時用 |
|---|---|---|---|
| `/pr-review <PR>` | plugin `runAppServerReview` | codex 內建 review subagent（OpenAI 調過的） | 平常，business OAuth 直連 OpenAI |
| `codex-bruce review --base main` | codex CLI native subcommand | **同一個** review subagent（不經 plugin 但跑同一份 prompt） | business OAuth 撞牆、想切 bruce 仍保 native review 品質 |
| `codex-bruce exec --output-schema schema.json -o out.json "<prompt>"` | codex CLI exec | 自定 prompt | 走 bruce 跑結構化派工（fan-out、決策閘、抽取分類） |

關鍵：`codex review` 子命令跟 plugin 的 `/codex:review` **走同一個 review subagent**（OpenAI 內部 tune 過、未公開），所以繞 plugin 不掉品質。

## Bruce 後端兩條 ingress 共存（2026-06-19 實證）

Bruce token proxy（`https://bruce-token-proxy-431026649525.asia-east1.run.app`）同時暴露兩條 client-facing endpoint：

| Ingress | Path | Wire | 給誰用 | Verified |
|---|---|---|---|---|
| Anthropic SSE | `https://<host>` + Anthropic `/v1/messages` | Anthropic | CC / Claude Code | 2026-06-18 via `ccp-bruce`（caveats.md §13） |
| OpenAI Responses | `https://<host>/v1` + `POST /v1/responses` | OpenAI Responses | Codex CLI | 2026-06-19 POST probe → 200 + resp_* id |

cc-vendor-bridge/docs/caveats.md §13 原本只描述 Anthropic ingress（"Anthropic SSE format, backed by OpenAI Responses (resp_* ids)"）— 這句話只是說**後端 backed by OpenAI Responses**，不排除 client-facing 也開 Responses path。2026-06-19 probe 實測確認雙 ingress。

後端對 gpt-5.5 model **自動注入 Codex CLI agentic system prompt**（OpenAI 後端行為，跟 Bruce proxy 無關）— 任何對 `gpt-5.5` 的 `/v1/responses` call 都會拿到「You are GPT-5.1 running in the Codex CLI...」為開頭的 instructions 欄位，意味著 Codex 派工的 calibration 不需要 user side 重做。

## 設置（已完成）

### 1. `~/.codex/config.toml` 加 provider block

```toml
[model_providers.bruce]
name = "Bruce"
base_url = "https://bruce-token-proxy-431026649525.asia-east1.run.app/v1"
wire_api = "responses"
env_key = "BRUCE_API_KEY"
```

**不動 default `model_provider`**（保持隱式 = 內建 `openai` provider，走 ChatGPT OAuth）。Backup 在 `~/.codex/config.toml.bak`。

### 2. `cc-vendor-bridge/shell/ccp-functions.sh` 加 wrapper

```bash
codex-bruce() {
  if [[ -z "$BRUCE_API_KEY" ]]; then
    echo "codex-bruce: BRUCE_API_KEY not set." >&2
    return 1
  fi
  codex -c model_provider=bruce "$@"
}
```

`~/.zshrc:116` 已 source ccp-functions.sh，重啟 shell（或 `exec zsh`）後自動可用。

### 3. `BRUCE_API_KEY` env

已經在 `~/.zsh_secrets` 配置，`~/.zshrc:115` 已 source。Codex CLI 透過 `env_key = "BRUCE_API_KEY"` 自動讀 env 發 `Authorization: Bearer <token>` header。

## Codex CLI 0.139 關鍵限制（必讀）

### a. `wire_api = "chat"` 已 hard-removed

Codex 0.139+ 只接受 `wire_api = "responses"`，`"chat"` 是 fatal config error。所有 pre-2026 的「set OPENAI_BASE_URL 接 OpenRouter / DeepSeek / GLM」教學全失效 — 必須 vendor 在 client-facing 暴露 Responses path 才能接。Bruce 已實證支援。

### b. `-c` flag 是頂層 OPTIONS

`codex [OPTIONS] <COMMAND>`，所以 `codex -c model_provider=bruce review --base main` 寫法對 — `-c` 影響所有子命令。`codex review -c model_provider=bruce --base main` 也對（review 子命令也接 `-c`），但 wrapper 統一在頂層 inject 比較乾淨。

### c. Plugin spawn 寫死 `["app-server"]` 不傳 args

Plugin（`~/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/lib/app-server.mjs:189`）spawn codex 時只傳 `["app-server"]`，**沒有任何 hook 讓外部 inject `-c` flag 或 args**。`env: this.options.env` default `undefined` → 繼承 CC main session 的 `process.env`，意味著唯一能影響 plugin 內 codex 的 surface 是 CC session 起來時的 env：

- `CODEX_HOME=~/.codex-bruce` 在 CC 啟動前設 → plugin 內 codex 全走 bruce（但需要重啟 CC、整個 session 都切）
- `BRUCE_API_KEY` 已在 env 但沒用 — 因為 plugin 內 codex 讀 default provider（= openai）不是 bruce

→ **codex-bruce wrapper 只影響 user 在 terminal 跑的 codex，影響不了 plugin 內 invoke**。這是 plugin 設計上的限制，不是 bug。

### d. `model_providers` 表只能 user-level

Codex 0.139 不讀 project-local `.codex/config.toml` 裡的 `model_providers` 區塊。`~/.codex/config.toml` 是唯一 surface。

### e. ChatGPT OAuth 跟 API-key 兩種 auth mode 互斥

Codex `codex login --with-api-key` 會主動 logout ChatGPT OAuth。我們用 `env_key = "BRUCE_API_KEY"` 路徑繞開了 `codex login` 整個機制 — bruce provider 在 invoke 時直接從 env 抓 key 發 Bearer，不動 `~/.codex/auth.json`。所以 ChatGPT OAuth bundle 不會被打掉。

## 平常用法

| 場景 | 命令 | 走哪 |
|---|---|---|
| 日常 review | `/pr-review <PR>` 或 `codex review --base main` | OpenAI 直連（ChatGPT OAuth） |
| Business OAuth 撞牆、要切 bruce 跑 review | `codex-bruce review --base main` | Bruce |
| 要 bruce 派工跑結構化任務 | `codex-bruce exec --skip-git-repo-check --output-schema s.json -o out.json "..." < /dev/null` | Bruce |
| 互動式跑 bruce | `codex-bruce` | Bruce |
| Plugin /pr-review 想強制切 bruce（罕用） | 需要重啟 CC + `CODEX_HOME=~/.codex-bruce claude` | Bruce |

## Caveat candidates（codex side specific）

跟 Anthropic side caveats.md §13 同 backend，但 wire 不同所以現象不同。先占位、實際跑過再補 evidence。

### CX-1. Codex 0.139 `wire_api = "chat"` 已 hard-removed

設 `wire_api = "chat"` → fatal config-load error。所有 pre-2026「set OPENAI_BASE_URL 接 X 第三方 model」教學失效。這條已在 §a。

### CX-2. Plugin 內 invoke 不受 `-c` 影響

Plugin spawn codex 寫死 `["app-server"]`，沒有 args inject hook。要切只能改 default provider 或換 `CODEX_HOME`。這條已在 §c。

### CX-3. `model = "gpt-5.5"` 在 Bruce 是 addressable，但 backend force-route 全部 model→gpt-5.5

Bruce 後端對任何送進來的 model id 都強制 route 到 gpt-5.5（跟 Anthropic side §13a / §13e 同性質）。意思是 `-c model="gpt-5.5"` 寫了跟沒寫一樣、`codex -c model=anything ...` 實際也跑 gpt-5.5。但寫顯式 `model = "gpt-5.5"` 在 config.toml 頂層 OK（codex CLI 不會 reject 沒出現在 Bruce 的 `/v1/models` 列表的 model id —— Bruce 的 `/v1/models` 404）。

### CX-4. gpt-5.5 真實 context cap ~256K（非 OpenAI 標稱 1.05M）

Anthropic side §13a 已實測 input_tokens ≥ 350K 拒絕。Codex side 走 Responses 同後端，應該同 cap。Codex 自家有 context window 概念但需 user 端設 — 長 reasoning 任務跑爆需要降到 256K。Codex 0.139 是否有對應的 client-side context budget config 待查。

### CX-5. `codex doctor` 會對 `<base_url>/models` 發 GET probe

Codex doctor 子命令對 provider 跑 reachability check via `GET <base_url>/models`。Bruce `/v1/models` 實測 404（caveats.md §13b 已記錄）。`codex doctor` 是否 fail-fast 還是 fail-soft 待跑一次看 — 404 應該不 block 真實 invoke（實際 invoke 是 POST /v1/responses 不是 GET /v1/models）。

### CX-6. `multi_agent_v2` regression #27339（潛在）

Codex 0.139 已知 `multi_agent_v2` 在 Windows 上 regression，root cause 是 backend 不支援 encrypted tool use。Bruce 是否中招未實測。Workaround 候選：

```toml
[features.multi_agent_v2]
enabled = false
```

### CX-7. Tool spec 容忍度（潛在）

Anthropic side §13b 實測 WebSearch / ToolSearch tool_reference 100% reject（OpenAI Responses translation proxy 的 schema validator 不認 Anthropic 私有 tool 格式）。Codex CLI 內建工具（`shell` / `apply_patch` / `spawn_agent` / `update_plan` 等）是 OpenAI native 格式，應該不踩這個雷，但要實測確認。

### CX-8. `experimental_bearer_token` field 行為未驗

`ModelProviderInfo` schema 有 `experimental_bearer_token` field，跟 `env_key` 看起來重複。差別 / 優先級 / token rotation 場景適用哪個待查。目前用 `env_key`。

### CX-9. VS Code / IDE 內嵌 Codex 不重讀 env

社群回報：IDE-embedded codex 不重讀 env vars，改 `BRUCE_API_KEY` 後必須完全關掉 IDE 才生效。Terminal 單跑沒這問題（每次 invoke 新 process 都讀 env）。

## Verify steps

### 即時 sanity check

```bash
# 1. Config 是否被 codex 正確 parse
codex doctor 2>&1 | head -20
# 應該看到 default provider = openai (built-in)、bruce 列在 configured providers

# 2. Wrapper 是否 load 進 zsh
zsh -ic 'type codex-bruce'
# codex-bruce is a shell function from ~/Desktop/projects/cc-vendor-bridge/shell/ccp-functions.sh

# 3. Per-invocation 切到 bruce 真的走 bruce？
zsh -ic 'codex-bruce exec --skip-git-repo-check "echo codex-bruce smoke" < /dev/null' 2>&1 | tail -20
# 應看到 resp_* id + 短回覆。jsonl 落在 ~/.codex/sessions/<date>/rollout-*.jsonl
```

### Review 品質 sanity（跑一次實際 PR）

```bash
# 任意小 PR
codex-bruce review --base main
# 跟 plugin /codex:review 輸出比對 — 應該都是同一份 review-output schema
# (verdict / summary / findings[severity/title/body/file/line_start/line_end/confidence/recommendation] / next_steps)
```

### Real-world dogfood checklist

- [ ] Business OAuth 一次正常 `/pr-review` 跑通（baseline 不動）
- [ ] Business OAuth 撞牆時切 `codex-bruce review --base main` 跑通
- [ ] Codex 內建工具（shell / apply_patch）在 bruce 跑通無 schema reject
- [ ] `codex doctor` 對 bruce provider 不 fail-fast block
- [ ] Long reasoning 任務確認 cap 在 ~256K input

## Reference

- `~/.codex/config.toml` — provider 配置位置
- `cc-vendor-bridge/shell/ccp-functions.sh` — `codex-bruce` function
- `cc-vendor-bridge/docs/caveats.md` §13 — Anthropic-side Bruce caveats（同 backend、不同 wire）
- `~/.claude/plugins/cache/openai-codex/codex/1.0.2/scripts/lib/app-server.mjs:189` — plugin spawn 寫死的位置（解釋為何 plugin 不受 `-c` 影響）
- Codex CLI source: `codex review --help` / `codex exec --help` 是權威 args spec
- 2026-06-19 POST probe: 200 + `resp_044e823c70925d58016a34dc15518c81918c5576043c75a807` 實證 Bruce `/v1/responses` ingress 可用
