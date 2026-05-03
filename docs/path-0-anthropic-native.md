# Path 0 — Vendor-native Anthropic Endpoint

Set `ANTHROPIC_BASE_URL` to a vendor's official Anthropic-format gateway. CC sees a normal Anthropic API, vendor handles the translation server-side. **No router, no proxy, no extra dependency.**

Verified 2026-05-03 across 4 major Chinese vendors. **All 4 ship official endpoints.**

## Endpoint matrix

| Vendor | Region | Endpoint | Notes |
|---|---|---|---|
| **DeepSeek** | 全球（單一） | `https://api.deepseek.com/anthropic` | 唯一無 region 區隔的 vendor |
| **Moonshot Kimi** | 國際 (PAYG) | `https://api.moonshot.ai/anthropic` | |
| **Moonshot Kimi** | 大陸 (PAYG) | `https://api.moonshot.cn/anthropic` | API key 不可跨區 |
| **Moonshot Kimi** | 訂閱 (Kimi Code) | `https://api.kimi.com/coding/` | ⚠️ 結尾斜線官方寫進 doc，不要拿掉 |
| **Zhipu GLM** | 國際 (z.ai) | `https://api.z.ai/api/anthropic` | |
| **Zhipu GLM** | 大陸 (bigmodel) | `https://open.bigmodel.cn/api/anthropic` | |
| **Alibaba Qwen** | 國際 (Singapore) | `https://dashscope-intl.aliyuncs.com/apps/anthropic` | |
| **Alibaba Qwen** | 大陸 | `https://dashscope.aliyuncs.com/apps/anthropic` | |
| **Alibaba Qwen** | Coding Plan 訂閱 | `https://coding-intl.dashscope.aliyuncs.com/apps/anthropic` | 獨立 quota pool |

⚠️ Qwen legacy endpoint 陷阱：避免 `claude-code-proxy` 舊路徑，會強迫使用 `qwen3-coder-plus` 不管你 `ANTHROPIC_MODEL` 怎麼設。**用上表的 `/apps/anthropic`**。

## Env var pattern 各家差異

每家設計風格不同，**不能一份 setup 複製貼上跨家用**。

### DeepSeek — 8 個 env var（最完整）

```bash
export ANTHROPIC_BASE_URL=https://api.deepseek.com/anthropic
export ANTHROPIC_AUTH_TOKEN=$DEEPSEEK_API_KEY
export ANTHROPIC_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_OPUS_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_SONNET_MODEL=deepseek-v4-pro
export ANTHROPIC_DEFAULT_HAIKU_MODEL=deepseek-v4-flash
export CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash
export CLAUDE_CODE_EFFORT_LEVEL=max
```

**獨家 env var**：`CLAUDE_CODE_SUBAGENT_MODEL`（直接解 CCR 的子 agent 路由破口）+ `CLAUDE_CODE_EFFORT_LEVEL=max`（推理深度旋鈕）。

支援 model：`deepseek-v4-pro`（主），`deepseek-v4-flash`（cheap tier）。

[Source — api-docs.deepseek.com](https://api-docs.deepseek.com/zh-cn/quick_start/agent_integrations/claude_code)

### Kimi — 簡單，1 個 model

```bash
export ANTHROPIC_BASE_URL=https://api.moonshot.ai/anthropic
export ANTHROPIC_AUTH_TOKEN=$MOONSHOT_API_KEY
export ANTHROPIC_MODEL=kimi-k2.5
```

文件**沒**講 OPUS/SONNET/HAIKU mapping，整 session 用同一支 model。Fallback 可選 `kimi-k2`（較慢）。

訂閱版 (Kimi Code) endpoint 不同，且文件沒釘 model 名。

[Source — platform.kimi.ai](https://platform.kimi.ai/docs/guide/agent-support) / [Kimi Code 訂閱版](https://www.kimi.com/code/docs/en/third-party-tools/other-coding-agents.html)

### GLM — 三段 tier mapping，無主 ANTHROPIC_MODEL

```bash
export ANTHROPIC_BASE_URL=https://api.z.ai/api/anthropic
export ANTHROPIC_AUTH_TOKEN=$ZAI_API_KEY
export ANTHROPIC_DEFAULT_OPUS_MODEL=GLM-4.7
export ANTHROPIC_DEFAULT_SONNET_MODEL=GLM-4.7
export ANTHROPIC_DEFAULT_HAIKU_MODEL=GLM-4.5-Air
export API_TIMEOUT_MS=3000000
```

CC 自動按 task 種類挑 OPUS/SONNET/HAIKU slot。官方建議 `API_TIMEOUT_MS=3000000` 拉長 timeout。

支援 model：`GLM-5.1`（Coding Plan flagship）/ `GLM-5-Turbo` / `GLM-4.7` / `GLM-4.5-Air`。

⚠️ **訂閱戶 server-side model mapping**：訂閱戶就算寫 `claude-sonnet-4` 字面，server 也會 map 到 GLM 模型。pay-as-you-go 戶才需明寫 GLM model 名。
⚠️ **Premium model 配額倍率**：Coding Plan 內 GLM-5.1 / GLM-5-Turbo 以 **3× peak / 2× off-peak** 扣配額（限期 1× off-peak 到 6 月）。

[Source — docs.z.ai](https://docs.z.ai/scenario-example/develop-tools/claude) / [docs.bigmodel.cn](https://docs.bigmodel.cn/cn/guide/develop/claude)

### Qwen — 單一 model，最多選項

```bash
export ANTHROPIC_BASE_URL=https://dashscope-intl.aliyuncs.com/apps/anthropic
export ANTHROPIC_AUTH_TOKEN=$DASHSCOPE_INTL_API_KEY
export ANTHROPIC_MODEL=qwen3-max
```

支援 model 涵蓋最廣：

- **Max:** `qwen3-max` / `qwen3-max-2026-01-23` / `qwen3-max-preview`
- **Plus:** `qwen3.5-plus` / `qwen3.5-plus-2026-02-15` / `qwen-plus` / `qwen-plus-latest`
- **Flash:** `qwen3.5-flash` / `qwen3.5-flash-2026-02-23` / `qwen-flash`
- **Coder:** `qwen3-coder-next` / `qwen3-coder-plus` / `qwen3-coder-flash`
- **VL（視覺）:** `qwen3-vl-plus` / `qwen3-vl-flash` / `qwen-vl-max`
- **Turbo / 開源:** `qwen-turbo` / `qwen3.5-397b-a17b` / `qwen3.5-120b-a10b` / `qwen3.5-27b` / `qwen3.5-35b-a3b`

⚠️ **Extended thinking 限制**：只 Max 系列支援，Coder + VL 不行。
⚠️ **Region 鎖定**：Singapore key 只能配 `dashscope-intl`，CN key 只能配 `dashscope`。
⚠️ **Coding Plan endpoint 獨立**：`coding-intl.dashscope.aliyuncs.com` 是另一個 quota pool，subscription 計費。

[Source — alibabacloud.com](https://www.alibabacloud.com/help/en/model-studio/claude-code) / [help.aliyun.com](https://help.aliyun.com/zh/model-studio/claude-code) / [Coding Plan](https://www.alibabacloud.com/help/en/model-studio/claude-code-coding-plan)

## 工作機制

CC binary 啟動時 read env，建好 HTTP client 連 `ANTHROPIC_BASE_URL`，整個 session 都打那個端點。

**重要**：env var **必須 CC 啟動前**就設好。CC 啟動後 session 內：

- ✅ `/model` 可在當前 base URL 內切不同 model（例如 Anthropic 端點上 Opus ↔ Sonnet）
- ❌ `/model` **不能跨 vendor**（base URL 已固定）

要切就 `Ctrl-D` 退出，重開另一個 ccp-* function。

## 跟 CLAUDE_CONFIG_DIR 多帳號 setup 共存

CN 模型走 per-token billing 不吃 Pro/Max quota，所以**不需要切 config dir**：

```
$ claude              # 主帳號 (philip Pro plan)
$ ccp-deepseek        # DeepSeek session, philip 帳號完全不動
$ ccp-glm             # GLM session, 也獨立
```

CC 內部 session log 仍寫到原本的 `~/.claude/projects/...`，statusline 用量看板顯示的是 Anthropic 那邊；CN 模型用量在各 vendor dashboard 看，不歸 CC quota 管。
