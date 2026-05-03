# Stage 2 Playbook — Onboarding a new vendor

How to verify a Path 0 vendor is production-ready for CC. Use this when adding Kimi / GLM / Qwen / future vendors.

## Pre-requisites

1. Vendor account + API key
2. Add key to `~/.zsh_secrets` (template in `shell/secrets.example`)
3. `shell/ccp-functions.sh` already has the `ccp-<vendor>` function with `CC_VENDOR=<name>` marker
4. `~/.zshrc` sources `~/.zsh_secrets` and `shell/ccp-functions.sh`

## Phase 1 — curl-level smoke test (5–10 min)

Don't open a CC session yet. First verify the vendor's anthropic endpoint accepts Anthropic-format requests at the protocol layer. This isolates vendor-side bugs from CC client-side caveats.

### Test 1: basic auth + thinking schema

```bash
zsh -c '
source ~/.zsh_secrets
curl -sS -w "\nHTTP %{http_code}\n" -X POST <VENDOR_BASE_URL>/v1/messages \
  -H "Authorization: Bearer $<VENDOR_KEY_ENV>" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d "{\"model\":\"<MODEL_ID>\",\"max_tokens\":30,\"messages\":[{\"role\":\"user\",\"content\":\"reply in 5 words\"}]}"
'
```

Pass criteria:
- HTTP 200
- Response has `content[].type === "thinking"` (caveat 2 — extended thinking schema works) — only if vendor model supports reasoning
- Response has `usage.cache_read_input_tokens` field (cache schema present, even if value is 0)

If HTTP 401: key wrong format. Check vendor doc — some use `x-api-key`, most use `Authorization: Bearer`.

### Test 2: prompt cache (caveat 1)

Send same large system prompt twice with `cache_control: ephemeral`. Round 2 should show `cache_read_input_tokens > 0`.

```bash
SYSTEM_TEXT=$(cat docs/path-0-anthropic-native.md docs/caveats.md)
PAYLOAD=$(jq -n --arg sys "$SYSTEM_TEXT" '{
  model: "<MODEL_ID>",
  max_tokens: 30,
  system: [{type: "text", text: $sys, cache_control: {type: "ephemeral"}}],
  messages: [{role: "user", content: "summarize in 5 words"}]
}')
# Round 1: expect cache_read=0
# Round 2 (same payload): expect cache_read > input_tokens × 0.9
```

Pass criteria:
- Round 2 `cache_read_input_tokens` > 0 (cache works at all)
- Bonus: `cache_creation_input_tokens` = 0 means free auto-cache (DeepSeek case)

If Round 2 still 0: vendor strips `cache_control` markers (LiteLLM-style bug) — token bill goes 4-10× planned.

### Test 3: MCP tool schema (caveat 3)

Send a request with a 60+ char tool name to verify the vendor doesn't reject Anthropic-spec MCP names.

```bash
curl ... -d '{
  "tools": [{
    "name": "mcp__some__namespace_long_test__do_thing",
    "description": "test",
    "input_schema": {"type":"object","properties":{}}
  }],
  "messages": [{"role":"user","content":"call the tool"}]
}'
```

Pass criteria: tool_use emitted with full name preserved (no truncation, no reject).

### Test 4: CLAUDE.md adherence (caveat 4)

Send a request with system prompt containing CLAUDE.md rules + ask a coding question. Check final text language + style.

```bash
PAYLOAD='{
  "model": "<MODEL_ID>",
  "max_tokens": 1500,
  "system": "你回應使用繁體中文。反晶晶體：能翻成中文的英文詞就翻。生成程式碼時不要有註解。使用 ?? 而非 ||。生成 console.log 時用 JSON.stringify()。",
  "messages": [{"role": "user", "content": "用 80 字內解釋 React useState 是什麼，並給範例。"}]
}'
```

Pass criteria:
- Final text 100% 繁中 (no mixed English noise)
- Code sample obeys `??` over `||`, `JSON.stringify`, no comments
- Bonus: thinking block shows model **reasoning about the rules** (active application vs passive parroting)

### Test 5: subagent dispatch schema (caveat 5)

Send a request with `Task` tool schema asking for parallel dispatch.

```bash
PAYLOAD='{
  "tools": [{"name":"Task","description":"...","input_schema":{...}}],
  "messages": [{"role":"user","content":"Dispatch TWO Task calls in parallel: ..."}]
}'
```

Pass criteria:
- `stop_reason: "tool_use"`
- `content_types`: `[thinking, tool_use, tool_use]` (2 parallel Task calls)
- Each call has complete `description`, `prompt`, `subagent_type`

### Test 6: tool_choice incompat (caveat 9 — DeepSeek-specific?)

Reproduce caveat 8 to check if vendor accepts specific tool_choice. **Do this for every new vendor** — it's the kind of incompat that no doc warns about.

```bash
curl ... -d '{
  "tools": [{"name":"ping","description":"x","input_schema":{...}}],
  "tool_choice": {"type": "tool", "name": "ping"},
  "messages": [{"role":"user","content":"call ping"}]
}'
```

Pass criteria:
- HTTP 200, model emits ping tool_use

Fail mode (DeepSeek pattern): HTTP 400 "deepseek-reasoner does not support this tool_choice" — vendor backend rejects specific tool name forcing. Fix: deploy proxy at `proxy/server.ts` (clone DeepSeek pattern, change `TARGET` URL).

If multiple vendors all fail this same way → consider a per-vendor proxy daemon, each on different port (9091 for DeepSeek, 9092 for Kimi, etc.).

## Phase 2 — real CC session (15 min)

Open `ccp-<vendor>` and run a representative task. Verify integration-level concerns curl can't catch.

### Test prompt (composite — covers caveats 3, 4, 5, 6, 7)

```
請依序做、每步附證據與觀察：
1. 用 filesystem MCP 列 ~/Desktop/projects/cc-vendor-bridge/docs/ 內檔名+大小
2. 並行派 2 個 general-purpose Task subagent：
   (a) 查 Bun.serve 的 streaming pass-through 行為
   (b) 查 launchd KeepAlive 設定
   兩個都回來才繼續
3. 用繁中 80 字內總結 step 1+2
4. Print 一個 JS console.log 範例（用 JSON.stringify、不寫註解、用 ?? 不用 ||）
5. 跟我講第 2 步的 subagent 用什麼 model
```

After session ends, analyze the jsonl from main session in:

```
~/.claude/projects/-Users-linhancheng-Desktop-projects-cc-vendor-bridge/<session-id>.jsonl
```

And subagent jsonls in:

```
~/.claude/projects/.../subagents/agent-*.jsonl
```

### Analysis queries (jq one-liners)

```bash
JSONL=<path>

# Caveat 1 — cache hits per turn
jq -c 'select(.type=="assistant") | .message.usage' "$JSONL"

# Caveat 6 — ToolSearch defer triggered?
jq -rc 'select(.type=="assistant") | .message.content[]? | select(.type=="tool_use" and .name=="ToolSearch") | .input.query' "$JSONL"

# Caveat 5b — actual subagent model
SUBAGENT_DIR=~/.claude/projects/<path>/<session-id>/subagents/
for f in "$SUBAGENT_DIR"*.jsonl; do
  jq -r 'select(.type=="assistant") | .message.model' "$f" | sort -u
done

# Hook errors (should be 0)
jq -c 'select(.type=="attachment" and (.attachment.type | contains("error")))' "$JSONL" | wc -l
```

### Pass criteria

- Hook errors = 0 (CC_VENDOR marker working, node 24+ no dyld issues)
- ToolSearch defer triggered before deferred tool calls (caveat 7 fix from `ENABLE_TOOL_SEARCH=auto`)
- Subagent model = `<vendor>-<small-tier>` if vendor has `CLAUDE_CODE_SUBAGENT_MODEL`, else same as main model
- Final text passes CLAUDE.md adherence
- No memory file written without explicit user request

## Phase 3 — known caveats to check per vendor

### Likely shared across vendors
- ⚠️ **caveat 6** (CC 200K context window fallback) — affects all third-party. Workaround: `DISABLE_COMPACT=1 + CLAUDE_CODE_MAX_CONTEXT_TOKENS=<size>` paired
- ⚠️ **caveat 7** (ToolSearch defer disabled for non-Anthropic) — affects all third-party. Fix: `ENABLE_TOOL_SEARCH=auto` (already in ccp-functions.sh)
- ⚠️ **caveat 8** (stop hook nudges vendor model) — affects all third-party. Fix: `CC_VENDOR=<name>` env + hook Defense 0

### Possibly vendor-specific (test each)
- 🔬 **caveat 9** (`tool_choice: {type:tool, name:X}` reject) — confirmed DeepSeek; unknown for others
- 🔬 **caveat 10** (vendor self-describe hallucinate about CC config) — likely shared but severity varies

## Lessons from DeepSeek (2026-05-03)

What surprised us positive:
- DS V4-Pro `cache_control` honored, no LiteLLM-style strip
- DS auto-cache no `cache_creation` fee (saves 1.25× write penalty)
- DS accepts 65-char tool names (more permissive than CCR's 64-char limit)
- DS thinking block actively reasons about CLAUDE.md rule application

What needed fixing:
- `tool_choice: {type:tool, name:X}` → 400 error → fixed by `proxy/server.ts` rewriting to `{type:any}`
- Hook errors from node@16 + icu4c@78 mismatch → fixed by upgrading to node 22+ (nvm-managed has self-contained ICU)
- Stop hook prompts caused DS to write ephemeral state to memory file → fixed by CC_VENDOR marker + hook Defense 0

What's still a known limit:
- DS hallucinate about CC self-config (claims subagent uses V4-Pro when actually V4-Flash)
- ToolSearch defer non-deterministic in V4-Flash subagent (sometimes calls deferred tool first → InputValidationError → self-corrects)

## Per-vendor verdict template

```markdown
### <Vendor>

**Tested:** YYYY-MM-DD via curl + ccp-<vendor> session

#### curl-level
- [ ] 1. Prompt cache (cache_control honored / auto cache fee?)
- [ ] 2. Extended thinking (thinking block schema)
- [ ] 3. MCP tool schema (64-char + 65-char tolerance)
- [ ] 4. CLAUDE.md adherence (繁中 + 反晶晶體 + 程式碼風格)
- [ ] 5. Subagent dispatch schema (parallel Task tool emit)
- [ ] 9. tool_choice {type:tool, name:X} accepted? (proxy needed if no)

#### CC-level
- [ ] 5b. CLAUDE_CODE_SUBAGENT_MODEL routing (subagent jsonl model field)
- [ ] 6. Context window: statusline shows 1M? (DISABLE_COMPACT + MAX_CONTEXT_TOKENS paired)
- [ ] 7. ToolSearch defer triggered (main + subagent)
- [ ] 8. Stop hook silent for vendor session (CC_VENDOR marker + Defense 0)

#### Open issues found
- ...
```
