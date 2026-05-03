# Caveats — Verify Before Trusting

Vendor docs don't list these. Reality may differ from advertised capability. **Test before relying.**

## Test plan (Stage 2)

For each Path 0 vendor, verify these 5 dimensions. All claims of "✅ verified" require evidence (sample request/response, log line, or screenshot).

### 1. Prompt cache (`cache_control`)

**Why it matters:** LiteLLM-based routers silently strip `cache_control` markers → CC token bill goes 4–10× higher than intended. CCR has the same bug ([LiteLLM #26625](https://github.com/BerriAI/litellm/issues/26625)).

**Test:**
- Send same large CLAUDE.md context twice in quick succession
- Check vendor dashboard for cache_read tokens
- If cache_write > 0 but cache_read still 0 on round 2 → cache broken

**Vendor status:**
- DeepSeek: `cache hit = 1/10 cost` documented but mechanism不明 (auto vs explicit `cache_control`)
- Kimi K2.6: "auto context cache" + cache hit price ¥1.10 vs miss ¥6.50 → 自動，不需 `cache_control`?
- GLM: 81% off cache hit price documented，但不明是否 honor Anthropic `cache_control` block
- Qwen: 沒明確講 cache 機制

### 2. Extended thinking (`thinking` block)

**Why it matters:** CC 在 plan mode / 複雜任務會送 thinking block。如果 vendor 不支援，會 error 或回 garbage。

**Test:**
- 在 ccp-* session 開啟 plan mode
- 觀察是否有 thinking block 出現
- 拿一個複雜 multi-step task 測 thinking 內容是否合理

**Vendor status:**
- Qwen: ⚠️ **只 Max 系列支援，Coder + VL 不行**（已從官方 doc 確認）
- DeepSeek: V4-Pro 自帶 reasoning，不確定怎麼對應 Anthropic `thinking` schema
- Kimi: doc 提到 "thinking toggle"，未細述
- GLM: 未明確

### 3. MCP tool schema

**Why它 matters:** CC 載入 MCP server 後送 tool schema 給 model。CCR 對 64-char 工具名 reject ([CCR #1348](https://github.com/musistudio/claude-code-router/issues/1348))，nested schema 也常出問題。

**Test:**
- 開 ccp-* session 後 mount 你既有的 MCP servers (filesystem / context7 / chrome-devtools etc.)
- 試呼叫一個工具名超過 50 字元的（例如 `mcp__claude-in-chrome__tabs_context_mcp`）
- 觀察是否成功

### 4. CLAUDE.md adherence

**Why它 matters:** 你 CLAUDE.md 強制繁體中文回覆 + 反晶晶體 + 多項紀律。Claude 對 system prompt 的 adherence 比其他 model 強。

**Test:**
- ccp-* 開新 session
- 問一個正常 coding question
- 觀察：(a) 回覆語言是否繁中 (b) 是否塞英文晶晶體 (c) 程式碼風格是否符合你 rules
- 跑 same question 在 default `claude` 比較

### 5. Subagent dispatch

**Why它 matters:** CC subagent 透過 Task tool 派出，需要 model 認得 subagent dispatch protocol。CCR 子 agent 不自動轉 model ([CCR #670](https://github.com/musistudio/claude-code-router/issues/670))。

**Test:**
- ccp-* session 跑一個會觸發 Task tool 的 prompt（例如「並行查 X 跟 Y」）
- 觀察是否成功 dispatch subagent
- 觀察 subagent 用的是哪個 model（DeepSeek 有 `CLAUDE_CODE_SUBAGENT_MODEL` 環境變數，其他家未明）

**Vendor status:**
- DeepSeek: ✅ **官方提供 `CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash`** 專屬 env var
- Kimi: 未明
- GLM: 未明
- Qwen: 未明

## 推薦實測順序

1. **DeepSeek 先**（user 有 $1.85 餘額 + 5/31 前 75% off + 唯一給 SUBAGENT_MODEL 環境變數 = 最低風險）
2. **Qwen 第二**（Anthropic-native + qwen-code CLI 雙路徑可比較）
3. **Kimi 第三**
4. **GLM 第四**（要訂閱才有 Coding Plan，PAYG 也可測）

## 實測結果（待填）

### DeepSeek

**Tested:** 2026-05-03 via direct curl to `https://api.deepseek.com/anthropic/v1/messages` (Bearer auth, anthropic-version: 2023-06-01, model: deepseek-v4-pro)

- [x] **1. Prompt cache** — ✅ **WORKS, auto cache, no write fee**
  - Round 1 (3413 input tokens, system has `cache_control: ephemeral`): `cache_creation_input_tokens: 0`, `cache_read_input_tokens: 0`
  - Round 2 (same payload): `input_tokens: 85`, `cache_read_input_tokens: 3328` → **97.5% cache hit**
  - DeepSeek does NOT charge cache_creation (vs Anthropic 1.25× write fee). Auto cache mechanism, but `cache_control` markers are NOT silently stripped (unlike CCR/LiteLLM #26625).
  - Cross-request cache leakage observed: subsequent unrelated request hit 128 cache tokens from earlier session — suggests aggressive auto-detect. Privacy implication minimal (per-account cache namespace assumed).

- [x] **2. Extended thinking** — ✅ **WORKS, native `thinking` block schema**
  - All test responses returned `content[0].type = "thinking"` with full `thinking` text and `signature`
  - V4-Pro reasoning chain auto-surfaces as Anthropic-format thinking block
  - No errors, no schema mismatch

- [x] **3. MCP tool schema (64-char name)** — ✅ **WORKS, accepts even 65-char names**
  - Tested 53-char name `mcp__claude_in_chrome_long_namespace_test__do_a_thing_2` → tool_use emitted with full name preserved
  - Tested 65-char name (over Anthropic spec limit) `mcp__claude_in_chrome_devtools_long_namespace_test__do_a_thing_xx` → also accepted, full round-trip works, input correctly populated
  - More permissive than CCR (#1348 rejects 64-char)
  - **CC client-side validation may still reject >64 chars** — needs CC-level confirmation

- [x] **4. CLAUDE.md adherence** — ✅ **WORKS, actively applies rules**
  - System prompt with 反晶晶體 + 繁中 + 程式碼風格規則
  - Final text fully traditional Chinese: 「useState 是 React Hook，賦予函數組件內部狀態，回傳當前值與更新函式」
  - Thinking block shows model **actively reasoning about rule application**: 「不要晶晶體。所以不用『useState 是一個 hook，可以讓 functional component 有 state』之類的，要用『useState 是 React Hook，賦予函數組件狀態』」
  - Technical term decision correct (useState/Hook stay English; functional component → 函數組件)
  - Code sample: no comments (符合「生成程式碼時不要有註解」)
  - `??` vs `||` rule not exercised in this test (sample didn't need fallback operator)

- [x] **5. Subagent dispatch (Task tool emit)** — ✅ **WORKS at schema level**
  - With Task tool schema in `tools[]`, prompt asking for parallel dispatch
  - Result: `stop_reason: "tool_use"`, `content_types: [thinking, tool_use, tool_use]` — 2 parallel Task calls emitted
  - Both calls had complete `description`, `prompt`, `subagent_type` filled correctly
  - **Pending CC-level**: whether `CLAUDE_CODE_SUBAGENT_MODEL=deepseek-v4-flash` env var actually routes subagent context to V4-Flash (CC client-side behavior, not vendor)

**Pending CC-level confirmation** (run via `ccp-deepseek` after exit current session):
- Real MCP server mount → tool round-trip
- Subagent execution actually uses V4-Flash (check via `/model` or token usage delta)
- Plan mode UX behavior (does CC see thinking block correctly)

### Kimi
- [ ] 1. Prompt cache:
- [ ] 2. Extended thinking:
- [ ] 3. MCP tool schema:
- [ ] 4. CLAUDE.md adherence:
- [ ] 5. Subagent dispatch:

### GLM
- [ ] 1. Prompt cache:
- [ ] 2. Extended thinking:
- [ ] 3. MCP tool schema:
- [ ] 4. CLAUDE.md adherence:
- [ ] 5. Subagent dispatch:

### Qwen
- [ ] 1. Prompt cache:
- [ ] 2. Extended thinking:
- [ ] 3. MCP tool schema:
- [ ] 4. CLAUDE.md adherence:
- [ ] 5. Subagent dispatch:
