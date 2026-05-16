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

## CC client-side limitations（影響所有 non-first-party vendor）

這些不是 vendor 問題，是 CC binary 自己對 `ANTHROPIC_BASE_URL != api.anthropic.com` 的 fallback 行為。每個 ccp-* 都中槍。

### 6. Context window detection fallback (200K) → premature AutoCompact

**症狀：** 不論 vendor model 真實 context 多大，CC statusline 跟 `/context` 都顯示 200K，AutoCompact 在 ~187K（200K − 13K buffer）觸發。

**對 ccp-deepseek 的影響：** DeepSeek V4-Pro 真實 1M context，但 CC 認 200K → AutoCompact 在真實 context 的 ~18.7% 就觸發，浪費 81% headroom。

**Root cause：** CC `src/utils/model/modelCapabilities.ts:46-51` 的 `isModelCapabilitiesEligible()` gate：

```typescript
function isModelCapabilitiesEligible(): boolean {
  if (process.env.USER_TYPE !== 'ant') return false
  if (getAPIProvider() !== 'firstParty') return false
  if (!isFirstPartyAnthropicBaseUrl()) return false  // ← 所有 ccp-* fail here
  return true
}
```

base URL 不是 `api.anthropic.com` → `getModelCapability()` 回 `undefined` → `getContextWindowForModel()` fallback 到 `MODEL_CONTEXT_WINDOW_DEFAULT = 200_000`。

DeepSeek 文件的 `[1m]` suffix（`ANTHROPIC_MODEL=deepseek-v4-pro[1m]`）對 CC client 端**無效**，因為 first-party gate 在 model name parsing 之前就 short-circuit 了。`[1m]` 只是 DeepSeek server 端的 routing hint。

**各 vendor 真實 context vs CC 認知（fallback 都是 200K）：**

| Vendor model | 真實 context | CC 認知 | 實際可用比例 |
|---|---|---|---|
| DeepSeek V4-Pro | 1M | 200K | 18.7% |
| DeepSeek V4-Flash | 1M | 200K | 18.7% |
| Kimi K2.5 / K2.6 | 256K | 200K | 73% |
| GLM-4.7 / 5.1 | 200K | 200K | 100%（剛好對齊） |
| Qwen3-Max | 262K | 200K | 71% |
| Qwen3-Coder-Plus | 1M | 200K | 18.7% |
| Qwen3.5-Plus / Flash | 1M | 200K | 18.7% |

GLM 系列剛好對齊 200K 所以無感，其他全部受影響。

**反方向風險（vLLM / 自架）：** 同個 root cause 的反向案例——如果你的 vendor 實際是 256K 但 CC fallback 顯示 1M，AutoCompact 永遠不觸發，直接撞 vendor 端的 `context_length_exceeded` hard error。本 repo 列的 vendor 都不會踩這個。

**Workaround（已驗，2026-05-03 from CC v2.1.126 binary disasm）：**

CC 有 env var override，但**有 paired condition**：必須**同時**設 `DISABLE_COMPACT=1` 跟 `CLAUDE_CODE_MAX_CONTEXT_TOKENS=<size>`。

從 binary 反組譯到的判斷邏輯（function `B2`）：

```javascript
function B2(H, _) {
  if (yH(process.env.DISABLE_COMPACT) && process.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS) {
    let K = parseInt(process.env.CLAUDE_CODE_MAX_CONTEXT_TOKENS, 10);
    if (!isNaN(K) && K > 0) return K;   // ← 唯一 third-party override 路徑
  }
  if ($0(H)) return 1e6;                 // first-party model 1M check
  if (_?.includes(Vi) && Kd(H)) return 1e6;
  if ($EH(H)) return 1e6;
  let q = eB_(H);
  if (q !== null) return q;              // first-party capability lookup
  return pi6;                            // 200K fallback (MODEL_CONTEXT_WINDOW_DEFAULT)
}
```

**設計動機（推測）：** CC 的 contract 是「使用者宣告自己 context size + 自己負責 compact 時機」，避免單設 `CLAUDE_CODE_MAX_CONTEXT_TOKENS` 但 AutoCompact 還在用舊算法跑導致 unexpected 行為。

**對 ccp-deepseek 的影響：** 關掉 AutoCompact 反而正中下懷——deepseek 1M headroom 本來就不該過早 compact。需要時手動 `/compact` 即可。

**ccp-functions.sh 已套用（2026-05-03）：**
- `ccp-deepseek` → 已加 `DISABLE_COMPACT=1` + `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1000000`，statusline 待驗顯示 `0k/1000k`

**其他 workaround 候選（無效或不需要）：**

- **`CLAUDE_CODE_AUTO_COMPACT_WINDOW`** — binary 有此 symbol，未測語意，但既然 paired contract 已成立就不需要再追
- **`CLAUDE_AUTOCOMPACT_PCT_OVERRIDE`** — 已知被 `Math.min(0.835, X)` clamp，**只能往下不能往上**，無法解決過早觸發

**Tracking：** [anthropics/claude-code#46416](https://github.com/anthropics/claude-code/issues/46416) — OPEN。Issue OP 提的 workaround 是 `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1000000` 單設，但 OP 沒驗證；本 repo 從 binary disasm 補足真實條件（需 paired `DISABLE_COMPACT=1`）。

**驗證指令（未來 self / contributor）：**

```bash
# 開新 ccp-deepseek session 看 statusline 第三行
ccp-deepseek
# Context: [...] 0k/1000k → ✅ paired env var 生效
# Context: [...] 0k/200k  → ❌ 套錯了，回頭 grep CC binary 再 disasm 看 function B2 是否變了
```

驗證結果：
- [ ] DeepSeek statusline 顯示 1000k（待 user 開新 session 確認）
- [ ] AutoCompact 確實不觸發（需長 session 才能驗）

### 7. ToolSearch defer loading disabled for non-Anthropic backends

**症狀：** CC 對 `ANTHROPIC_BASE_URL != api.anthropic.com` 預設 disable ToolSearch deferred loading，所有 MCP tool schemas 一次塞進 context、吃 tokens。

**對 ccp-* 的影響：** mount 大量 MCP server（user 環境有 ~250 deferred tools）時 context overflow 早觸發。Subagent 也受影響——V4-Flash subagent 在 c7b3f805 session 觀察到 non-deterministic 行為：A 沒先 ToolSearch 直接 emit deferred tool → `InputValidationError` → self-correct → 加 turns；B 一開始就 ToolSearch first → 一次到位。

**Root cause：** CC client 對 non-firstParty BASE_URL 預設 conservative — 假設第三方 backend 不一定支援 ToolSearch protocol。

**Workaround：** `export ENABLE_TOOL_SEARCH=auto` 強制 enable defer loading 即使 BASE_URL 非 Anthropic。

**ccp-functions.sh 已套用（2026-05-03）：** 7 個 ccp-* function 全部加。

**驗證方式：**

```bash
# 對 jsonl grep ToolSearch tool_use with select: query
jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="ToolSearch") | .input.query' <session.jsonl>
# 應看到 'select:mcp__filesystem__list_directory,...' 之類，代表 model 主動 emit ToolSearch
```

### 8. Stop hook nudges vendor model → unwanted memory writes

**症狀：** CC stop hook (`~/.claude/hooks/checkpoint-judge.sh`) 觸發 checkpoint prompt 「告一段落？是 → 寫 memory；否 → 回 skip」。Anthropic Claude 被 trained 認得這個 protocol 正確 reply skip 或寫 essential memory；**第三方 vendor model 沒被 trained，行為 non-deterministic**——有時候誤把 hook 訊息當 user 指令而 emit Write tool 寫 ephemeral state 進 memory file。

**對 ccp-* 的影響：** 4ca5a3b3 session DS 把當下 task spec 寫進 `~/.claude/projects/.../memory/proxy-tool-choice.md`（屬 ephemeral，按 CLAUDE.md 規則不該寫 memory）。長期累積會污染 user 的 memory directory。

**Root cause：** Hook 不知道當前 session 是 vendor-backed。原本基於 `ANTHROPIC_BASE_URL` pattern 的判斷 leak: cc-vendor-bridge proxy URL 是 `http://127.0.0.1:9091` (localhost) → 看起來像 cc-i18n-proxy 那種轉到 Anthropic 上游的 proxy → hook allow checkpoint。

**Workaround：** `export CC_VENDOR=<name>` 在 ccp-* subshell 內當 explicit marker，hook 加 Defense 0：

```bash
# In ~/.claude/hooks/checkpoint-judge.sh
[[ -n "$CC_VENDOR" ]] && exit 0
```

**ccp-functions.sh 已套用（2026-05-03）：** 7 個 function 全部 `export CC_VENDOR=<vendor>`（deepseek/kimi/kimi-cn/glm/glm-cn/qwen/qwen-coding）。

**Trade-off：** vendor session 完全不被 stop hook nudge 寫 memory。但 user 主動 prompt「請寫 memory: X」時，vendor model 還是可以 emit Write tool 寫 memory file（hook 跟 Write tool 是獨立路徑）。**實質：「不被 passive nudge」vs「可主動 trigger」的取捨**，net positive 避免 ephemeral state 被誤寫。

**驗證方式：**

```bash
jq -c 'select(.type=="attachment" and .attachment.type=="hook_blocking_error") | .attachment.hookEvent' <session.jsonl>
# 對 ccp-* session 應該 0 行（Stop hook 完全沒 fire）
```

### 11. Cross-vendor `/resume` 炸 thinking signature

**症狀：** vendor session（ds / kimi / etc 有 native thinking schema 的）開的對話，切到 Anthropic-backed CC `/resume` 該 session，第一次 user prompt 後 API Error 400 `Invalid signature in thinking block`（2026-05-03 in opus session resuming ds bfb74923 觀察到）。

**Root cause：** `thinking` block 的 `signature` 欄位是 Anthropic API 的 cryptographic seal——server 用自己的 key 簽，client 後續送回 messages array 時 server verify 防 client 偽造 thinking 內容。Vendor（DeepSeek V4-Pro 等）有 native thinking schema (caveat 2)，但 signature 是 vendor 自己簽的，**Anthropic server 認不得**→ 400 reject 整個 messages array。

**影響範圍 matrix：**

| 從 → 到 | resume 結果 |
|---|---|
| vendor → Anthropic | ❌ thinking signature 不通用 |
| Anthropic → vendor | ⚠️ 可能 OK（vendor validation 通常較寬鬆），未測 |
| same vendor → same vendor | ✅ |
| Anthropic → Anthropic | ✅ |

**Workaround（按推薦度）：**

1. **不 resume，summary paste 重起**：最簡單。失去自動 context 但保險。
2. **`ccp-resume` wrapper**（✅ 已實作於 `shell/ccp-functions.sh`）：列 `~/.claude/projects/<hash>/*.jsonl`，fzf picker 顯示 mtime / model / sid / snippet，從 jsonl assistant message 抓 model name 映射 vendor，dispatch 對應 ccp-* function。$CC_VENDOR != target 時 warn + ask y/N。需要 `fzf` + `jq`。
3. **strip thinking block from jsonl**：`jq 'del(.message.content[] | select(.type == "thinking"))'` 改寫 jsonl 後 resume。失去 model reasoning context 但能保留對話。
4. **心理紀律 + statusline 顯示 CC_VENDOR**：cc-statusline 已 active；不 prevent 但 active session 能雙向 confirm 自己在哪。

**沒辦法做的事：** CC 內建 `/resume` picker UI 顯示文字純粹來自 first user message string content（已驗證 jsonl entry types），**無 vendor/model metadata 欄位**給 picker 用 → 改不了 picker 顯示文字（除非污染 user message 加 prefix，但會讓 model 把 prefix 當 instruction）。

**驗證方式：**

```bash
# 列 jsonl 是哪個 model 寫的
jq -rc 'select(.type=="assistant") | .message.model' <session.jsonl> | head -1
# claude-opus-4-7 → first-party；deepseek-v4-pro → vendor
```

## Vendor-side discovered issues (during Stage 2)

These are vendor backend bugs found during real testing, not test dimensions to verify. Likely vendor-specific — re-test for each new vendor.

### 9. DeepSeek: `tool_choice: {type:"tool", name:X}` rejected

**症狀：** DeepSeek anthropic endpoint 收到 `tool_choice: {type:"tool", name:X}` 時回 HTTP 400 `"deepseek-reasoner does not support this tool_choice"`。`auto` / `any` 都 OK，只有 specific tool 強制中。

**對 ccp-deepseek 的影響：** CC 內 server-side WebSearch / WebFetch / 某些 force-emit pattern 會送 specific tool_choice → 全失敗。c7b3f805 session subagent A 跑 web research 時 trial-and-error 45 turns 才 fall back curl Bash 拿到答案（vs subagent B 12 turns 因為剛好沒 trigger 此 path）。

**Reproducer (curl)：**

```bash
curl -X POST https://api.deepseek.com/anthropic/v1/messages \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "anthropic-version: 2023-06-01" -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-pro","max_tokens":30,"tools":[{"name":"ping","description":"x","input_schema":{"type":"object","properties":{}}}],"tool_choice":{"type":"tool","name":"ping"},"messages":[{"role":"user","content":"hi"}]}'
# → HTTP 400
```

**Workaround：** Thin Bun proxy `proxy/server.ts` rewrite `tool_choice: {type:tool, name:X}` → `{type:any}` 再 forward。launchd auto-start daemon。

**ccp-functions.sh `ccp-deepseek` 已 wired：** `ANTHROPIC_BASE_URL=http://127.0.0.1:9091` (proxy)，預啟動 health check via `nc -z 127.0.0.1 9091` + `launchctl kickstart` fallback。

**是否影響其他 vendor：** 未驗。每家 vendor 自己寫 anthropic translation layer，DS 中槍是因為他們 wire 到 deepseek-reasoner 模型而 reasoning 模型不接受 specific tool 強制（OpenAI-compat 的 reasoner 也常這樣）。其他 vendor 可能不中——加新 vendor 時用 [stage-2-playbook.md](./stage-2-playbook.md) Test 6 驗一次。

### 10. Vendor self-describe hallucinates about CC internal config

**症狀：** Vendor model 對 CC 自身配置（subagent routing / model used / env var effect / hook protocol）reasoning 出**邏輯合理但事實錯誤**的描述。

**Example (DeepSeek 在 c7b3f805 session)：**
- DS V4-Pro final answer claims：「subagent 使用 DeepSeek v4 Pro，因為 general-purpose agent 沒指定 model 所以繼承父層模型」
- Ground truth (subagent jsonl `agent-afc721d99946fd916.jsonl`)：`{"type":"assistant","message":{"model":"deepseek-v4-flash",...}}` — 實際走 V4-Flash，via `CLAUDE_CODE_SUBAGENT_MODEL` env var routing

**Root cause：** Vendor model 沒被 trained 在 CC internals（env var contract / hook protocol / subagent dispatch routing）。它從可見的 source code clue + Anthropic doc 自行 reasoning，但缺少 runtime context，結論可能跟 ground truth 違背。

**No fix — document only.**

**對 user 的指引：**
- Vendor model 對 CC config 的 self-describe **不可信**
- Ground truth 永遠從 jsonl log (`~/.claude/projects/.../<session>.jsonl` + `subagents/agent-*.jsonl`) 或 CC binary 反組譯拿
- 跟 vendor model 討論 CC behavior 時，verify with raw log evidence

**是否影響其他 vendor：** Likely all vendors 同 pattern（沒 train 在 CC 內部），just severity 跟 confidence 程度不同。Stage 2 onboard 時觀察各家 self-describe 質量。

## Proxy-side discovered issues

cc-vendor-bridge 自己的 `proxy/server.ts` 實作缺陷，非 vendor 也非 CC 端。任何新增的 per-vendor proxy daemon 都要回頭檢查同類問題。

### 12. proxy 把已解壓 body 配 `Content-Encoding: br` → CC `BrotliDecompressionError`

**症狀：** `ccp-deepseek`（或任何走 `proxy/server.ts` 的 vendor）跑一陣子後，CC 報 `API Error: BrotliDecompressionError fetching "http://127.0.0.1:9091/v1/messages?beta=true"`。proxy log 看似正常（`[proxy] POST /v1/messages → ...` 照印），upstream 也通。會「又壞了」是因為這是結構缺陷被環境引爆，不是偶發。

**Root cause：** `proxy/server.ts` 原本 `return resp;` 直接轉發 upstream `Response`。proxy 只 `headers.delete("host")`，把 client 的 `accept-encoding: br` 一起帶給 DeepSeek → DeepSeek 回 `Content-Encoding: br` + brotli 壓縮 body。**Bun 的 `fetch()` 串流 `resp.body` 時透明解壓 brotli，但 `resp.headers` 仍保留 upstream 的 `Content-Encoding: br`**。`return resp` = 把「已解壓明文 body」配「`Content-Encoding: br` header」一起送回 CC，CC（2.1.143 起 undici 嚴格驗證）拿明文去 brotli 解碼 → 炸。fetch-passthrough proxy 的經典陷阱：runtime 已透明解碼 body，header 卻還在宣稱壓縮。舊版 CC undici 容忍此 mismatch，2.1.143 後不容忍 → 結構缺陷被 CC 升版引爆。

**Reproducer (curl)：**

```bash
# --raw 關掉 curl 自動解碼，看 wire 真相
curl --raw -sS -D - -o /tmp/b.bin \
  -X POST "http://127.0.0.1:9091/v1/messages?beta=true" \
  -H "content-type: application/json" -H "authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "accept-encoding: br" -H "anthropic-version: 2023-06-01" \
  -d '{"model":"deepseek-v4-pro","max_tokens":5,"messages":[{"role":"user","content":"hi"}]}'
# 修前：header 有 Content-Encoding: br，但 body 是明文 JSON（brotli -d 解不開）
# 修後：無 Content-Encoding，body 明文 JSON 直接可讀
```

**Workaround（已修，commit `1502f55`）：** `proxy/server.ts` 不再 `return resp`，改重組 Response 並刪掉 `content-encoding` + `content-length`（body 已被 Bun 解碼，這兩個 header 已不描述實際 body）。SSE 串流路徑（CC 實際走的）已驗證不受影響。對應 caveat 9 — 同一支 proxy，加 tool_choice rewrite 的 daemon 自己也有此 footgun。

**對其他 vendor 的意義：** [stage-2-playbook.md](./stage-2-playbook.md) 提到的 per-vendor proxy（9092/9093…）只要是 fetch-passthrough 都會中同款。新 proxy 一律從一開始就 strip `content-encoding`/`content-length`，別等 `BrotliDecompressionError`。

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

**CC-level verified (2026-05-03 via ccp-deepseek sessions c7b3f805, f88c2681, 92a223af):**
- ✅ Real MCP round-trip: filesystem (c7b3f805) + context7 resolve-library-id / query-docs (92a223af)
- ✅ Subagent execution actually V4-Flash: `subagents/agent-*.jsonl` shows `"model":"deepseek-v4-flash"` (caveat 5b confirmed via `CLAUDE_CODE_SUBAGENT_MODEL` env routing)
- ✅ ToolSearch defer triggered: main V4-Pro emits `select:` queries before deferred tool calls (after `ENABLE_TOOL_SEARCH=auto` patch)
- ✅ Caveat 8 (tool_choice incompat) fix verified: f88c2681 ran web research subagents without 45-turn hell after proxy deployed
- ✅ Caveat 9 (vendor self-describe hallucinate): DS claimed "subagent uses V4-Pro" while ground truth was V4-Flash — confirmed limitation
- ✅ Hook errors zero in 92a223af: `CC_VENDOR=deepseek` triggers Defense 0 (no Stop hook fire); node 24 (nvm-managed, self-contained ICU) eliminates dyld errors

**Pending observation (long session):**
- AutoCompact 確實不觸發 (caveat 6 — 需 long-context session 跑到 187K+ 才能 confirm `DISABLE_COMPACT=1` 真的 disable)

### Kimi
- [ ] 1. Prompt cache:
- [ ] 2. Extended thinking:
- [ ] 3. MCP tool schema:
- [ ] 4. CLAUDE.md adherence:
- [ ] 5. Subagent dispatch:

### GLM
**Connected:** 2026-05-03, `ccp-glm` via `api.z.ai/api/anthropic`
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
