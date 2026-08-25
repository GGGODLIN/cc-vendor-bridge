# ccp-free YAGNI Review Packet

## Spec

## Problem Statement

使用者已有 `ccp-gpt` 與 `ccp-relay`，但兩者服務訂閱或既有中繼站路線。使用者希望另外取得一個只承載免費模型來源的 `ccp-free` 入口，不把不穩定的免費池混進主要路線，也不再自行承擔每一家免費 provider 的整合維護。

Free Claude Code 已提供免費 provider 的 catalog、Anthropic-compatible endpoint、model routing 與相容性維護，但其預設 installer、設定目錄、網路綁定與 Claude launcher 可能影響既有環境。因此導入時必須隔離安裝、設定、port、credential 與 process，並以真實請求驗證 NVIDIA NIM key 和至少一個模型可用。

## Solution

建立獨立的 `ccp-free` 路線：以隔離安裝的 Free Claude Code server 作為免費來源轉接站，由 `ccp-free` wrapper 把既有 Claude Code session 指向該端點。

Free Claude Code 使用獨立 runtime home、設定、auth token、port 與 launchd service。初始 provider 只接 NVIDIA NIM，安全複用現有 CLIProxyAPI 裡的 NVIDIA NIM key，但不輸出、不 commit，也不讀取或搬移其他 provider credential。完成安裝後必須以 `/v1/models` 與真實 prompt 驗證可用性；驗證失敗時保持既有 `ccp-gpt`、`ccp-relay` 與 CLIProxyAPI 完全不變。

## User Stories

1. As a 使用者, I want a `ccp-free` command, so that I can deliberately enter a free-model route without changing how `ccp-gpt` or `ccp-relay` works. [user: "可以，就走這個ccp-free的路線"]
2. As a 使用者, I want `ccp-free` to use Free Claude Code as its endpoint, so that provider integration maintenance is mostly handled upstream instead of being maintained manually in CLIProxyAPI. [user: "所以FCC對我來說最高的作用應該是有持續維護？"]
3. As a 使用者, I want this route to contain only explicitly free sources, so that a request cannot silently consume my paid or subscription-backed routes. [user: "如果我的需求明確要搞一個免費token的端點"]
4. As a 使用者, I want the existing NVIDIA NIM key reused without exposing it, so that I can validate the route without creating another credential first. [user: "a，當然要驗證可用性"]
5. As a 使用者, I want a real NVIDIA request to succeed before the route is called usable, so that a provider merely remaining in config is not mistaken for a live source. [user: "a，當然要驗證可用性"]
6. As a 使用者, I want the Free Claude Code runtime isolated from my current CLIProxyAPI runtime, so that trial installation, restart, config changes, or removal cannot interrupt existing model routes. [inferred]
7. As a 使用者, I want `ccp-free` to preserve my normal Claude Code config, skills, hooks, agents, sessions, and credentials, so that the free route changes only the model endpoint for that process. [inferred]
8. As a 使用者, I want the server bound only to loopback and protected by a private bearer token, so that other devices on the network cannot consume my provider quota. [evidence: FCC settings.py defaults inspected on 2026-08-23]
9. As a 使用者, I want `ccp-free` to start or recover its own server when needed, so that using the command does not require a separate manual startup ritual. [evidence: existing ccp-relay health-check and launchd convention]
10. As a 使用者, I want startup failure to produce a direct diagnostic and stop before launching Claude Code, so that the command never silently falls back to Anthropic or another existing endpoint. [inferred]
11. As a 使用者, I want the initial installation pinned to an exact upstream commit, so that the safe-trial result is reproducible and cannot change when upstream `main` moves. [evidence: FCC installer main.zip behavior inspected on 2026-08-23]
12. As a 使用者, I want a complete restore path, so that I can remove the trial and return global config and services to the before snapshot. [evidence: safe-trial workflow requirement]
13. As a 使用者, I want later free providers added through the isolated FCC configuration, so that `ccp-free` remains one stable command while its source pool evolves. [inferred]
14. As a 使用者, I want the route documented with its current provider and last live-verification result, so that stale inventory is not presented as healthy capacity. [inferred]
15. As a 使用者, I want existing cc-vendor-bridge tests to remain green, so that adding the route does not regress model mapping or credential-priority behavior elsewhere. [evidence: existing zsh wrapper tests]

## Implementation Decisions

- Free Claude Code SHALL be installed into an independent setup project and virtual environment rather than the global uv tool directory. [inferred]
- The trial SHALL pin the exact Free Claude Code commit selected at trial start; it SHALL NOT install mutable `main.zip`. [evidence: FCC installer main.zip behavior inspected on 2026-08-23]
- The upstream all-in-one installer SHALL NOT be used because it can install or verify unrelated coding agents and create desktop integration. Only the Free Claude Code package and server dependencies SHALL be installed. [evidence: FCC install.sh inspected on 2026-08-23]
- The FCC server SHALL run with a dedicated runtime home so its `.fcc` config, auth state, logs, and generated artifacts cannot overlap the normal user home or CLIProxyAPI runtime. [inferred]
- The service SHALL bind to `127.0.0.1` on a dedicated port and SHALL enable proxy authentication with a generated private token. [evidence: FCC network and auth defaults inspected on 2026-08-23]
- A dedicated launchd service SHALL own the FCC server lifecycle, following the existing `ccp-relay` convention while using a distinct label, runtime home, port, logs, and executable. [evidence: existing ccp-relay launchd and health-check convention]
- The `ccp-free` wrapper SHALL health-check the dedicated port, kickstart only the dedicated FCC service when unavailable, wait for readiness with a fixed upper bound, and abort with a diagnostic if readiness fails. [evidence: existing ccp-relay wrapper seam]
- The wrapper SHALL invoke the normal installed `claude` binary with process-local endpoint and auth environment variables. It SHALL NOT invoke `fcc-claude`, because that launcher removes existing `ANTHROPIC_*` values, fixes the compaction window, and disables several Claude Code behaviors. [evidence: FCC claude_env.py inspected on 2026-08-23]
- The wrapper SHALL mark the session as the free route, enable FCC gateway model discovery, and keep context, effort, tool, hook, agent, and skill behavior unchanged unless a live compatibility test proves an override is required. [inferred]
- Initial provider configuration SHALL contain NVIDIA NIM only. It SHALL select a model returned by the provider catalog and proven by a live prompt instead of trusting a stale model ID. [user: "a，當然要驗證可用性"]
- The existing NVIDIA NIM key SHALL be read from the current CLIProxyAPI credential source and copied directly into the isolated FCC config without printing it. No other credential SHALL be copied. [user: "a，當然要驗證可用性"]
- Secret-bearing runtime files SHALL use user-only permissions and SHALL remain outside every git repository. [inferred]
- `ccp-free` SHALL NOT include CLIProxyAPI, Codex OAuth, Antigravity, Anthropic subscription, or any paid provider as a fallback. [user: "如果我的需求明確要搞一個免費token的端點"]
- Provider inventory and provider health SHALL be represented separately: configuration proves only that a route exists; a dated live probe proves that it worked. [user: "沒有的話，我現在要自己去驗證我串的NVIDIA有沒有活著對嗎"]
- Installation and first execution SHALL run inside safe-trial snapshots, with a seven-day review entry and a dry-run restore script. [evidence: safe-trial workflow requirement]
- The implementation SHALL stop after the isolated NVIDIA-backed route passes acceptance tests; adding more providers belongs to later iterations. [inferred]

## Testing Decisions

- The highest behavioral seam is `ccp-free` as observed by a caller: invoking it must start the isolated endpoint when necessary and launch Claude Code with the expected process-local endpoint, auth, route marker, and gateway-discovery environment.
- Wrapper tests will replace `claude`, port checks, and launchd calls with controlled fakes. Tests will assert the launched command and environment without contacting real services.
- Server tests will start the isolated FCC process and verify loopback binding, authenticated `/v1/models`, rejection without the bearer token, and isolation from the CLIProxyAPI port.
- The provider acceptance test will first obtain the FCC model catalog, choose the configured NVIDIA model, send a minimal real prompt, and require a non-empty successful response. A catalog-only result is insufficient.
- Secret-handling verification will assert that no tracked file or test output contains the copied NVIDIA key or generated proxy token, and that runtime credential files have user-only permissions.
- Safe-trial verification will compare before and after snapshots, confirm restore coverage, record the Stage 0 Docker result, and add the required seven-day review entry.
- Regression testing will run the existing cc-vendor-bridge wrapper and credential-priority tests, plus the new focused `ccp-free` test.
- Isolation verification will prove the existing CLIProxyAPI launchd service remains running on its original port and that existing `ccp-gpt` and `ccp-relay` definitions are byte-for-byte unchanged outside the intended additive help-list insertion.
- Restore verification will first run the generated restore script in dry-run mode and confirm it targets only trial-created artifacts.

## Out of Scope

- Replacing CLIProxyAPI, `ccp-gpt`, `ccp-relay`, or any existing provider route.
- Importing Codex, Antigravity, Anthropic, Gemini, OpenRouter, or other paid/subscription credentials into FCC.
- Building cost-aware or quota-aware dynamic routing.
- Adding multiple free providers in the first iteration.
- Enabling FCC Discord, Telegram, voice, desktop tray, Codex, Pi, OpenCode, Cline, Hermes, DeepSeek Harness, Grok Build, or Muse Code integrations.
- Publishing the endpoint outside localhost.
- Treating FCC README token totals as guaranteed capacity.
- Automatically promoting the trial into permanent infrastructure before the seven-day review.

## Further Notes

The initial route proves only that Free Claude Code can safely coexist with the current stack and that the reused NVIDIA credential can complete a real request. It does not prove that NVIDIA remains permanently free or reliable. Every provider added later needs its own dated live probe and explicit classification as free, subscription-backed, paid, or local.

The implementation should follow the existing `ccp-relay` lifecycle shape where that shape remains valid, but it must not inherit CLIProxyAPI credentials, ports, model mappings, or management behavior beyond the explicitly approved NVIDIA key reuse.

## 使用者原話引文附錄

- 可以，就走這個ccp-free的路線
- 所以FCC對我來說最高的作用應該是有持續維護？
- 如果我的需求明確要搞一個免費token的端點
- a，當然要驗證可用性
- 沒有的話，我現在要自己去驗證我串的NVIDIA有沒有活著對嗎

## Review Rubric

你是 YAGNI reviewer。預設答案是「不做」，舉證責任在 spec，不在砍方。不要外查，也不要讀本 packet 以外的檔案。

逐條檢查全部 User Stories 與 Implementation Decisions，不得抽樣：

1. 來源追溯
- `user`：使用者原話，核對下方引文附錄。
- `evidence`：量測或已查證事實，指出 spec 寫的資料來源。
- `inferred`：模型推導。逐條回答「砍掉會發生什麼具體損失？」答不出就判 `demote-v2` 或 `kill`。

2. 分母檢查
- spec 是否回答問題過去實際發生幾次、每次損失多少？
- 沒有就標 `未定價`。未定價問題的方案以最簡版為上限。

3. 簡單版舉證
- 先寫一頁內可執行的最簡方案。
- 逐條列出 spec 超出最簡版的部分。
- 每個超出部分都要說明具體收益；不能只用完整性、未來可能或最佳實務辯護。

固定輸出：

## 三句入口
- 這輪在審值不值得做：<一句>
- 太早的部分：<一句>
- 現在只需決定：<一句>

## 一頁最簡方案
<最簡可驗證方案>

## 分母
- verdict: `已定價` 或 `未定價`
- evidence: <一句>

## 逐條表
| # | 條目 | 來源類 | verdict | 一句理由 |
|---|---|---|---|---|

`verdict` 只能是 `keep`、`demote-v2`、`kill`。表必須覆蓋每一條 User Story 與每一條 Implementation Decision。

## 超出最簡版
| 條目 | spec 多做什麼 | 具體收益是否成立 | 建議 |
|---|---|---|---|

## 最終建議
只選一個：`照原 spec`、`縮成最簡版`、`不做`。附一句理由。
