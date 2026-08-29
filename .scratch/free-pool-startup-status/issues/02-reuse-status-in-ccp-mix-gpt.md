# 02 — 接入 ccp-mix-gpt 並完成整體確認

**What to build:** 呼叫 `ccp-mix-gpt` 時先顯示 GPT main route，再以 caller-specific prefix 重用 Ticket 01 的免費池摘要，讓 mixed routing 在啟動前可讀且與 `ccp-free` 不漂移。

**Blocked by:** 01 — 讓 ccp-free 顯示免費池啟動摘要

**Status:** completed

**Needs:** Ticket 01 的共用診斷與 fixture；本機 CLIProxyAPI／cline2api 可供最後的 read-only status smoke，Claude binary 以 no-op 替代，不需送 inference request。

**TDD:** required

**TDD seam:** 呼叫 `ccp-mix-gpt`，捕捉 fake Claude binary 執行前的 stderr 與 wrapper environment

- [x] `ccp-mix-gpt` 啟動前顯示 GPT main route，文字與實際 `gpt-5.6-sol` mapping 一致。
- [x] 免費池行使用 `[ccp-mix-gpt]` prefix，且與 `ccp-free` 共用同一分類與格式邏輯。
- [x] 每次 wrapper 啟動只查一次免費池狀態，不送 inference request、不改 session affinity。
- [x] 狀態診斷失敗不阻擋 GPT main session，也不改 fallback/model/context env。
- [x] **Confirmation:** 用 no-op Claude binary 執行兩個 wrapper 的真實 local-state smoke，兩者都產生摘要並正常結束。
- [x] **Confirmation:** healthy output 簡短；warning-only recovery lines 只在 degraded／failed fixture 出現。
- [x] **Confirmation:** stdout／stderr 不含 provider key、client key、management key、prompt、completion 或 raw response body。
- [x] **Confirmation:** 既有 wrapper contract tests 與 caller argument passthrough 全部通過。

## Verification Log

- TDD RED：`ccp-mix-gpt` fixture 保留 model env，但缺少 GPT main route 與 caller-prefixed free-pool summary，test exit `1`。
- TDD GREEN：成功 preflight 後印 `Main：GPT-5.6 Sol`，再以 `ccp-mix-gpt` caller prefix 呼叫共用 status 診斷；fixture exit `0`。
- 共用性：同一 status function 服務兩個 wrappers；mixed fixture 驗證 Main 行與免費池 `服務中` 行各出現一次。
- Failure behavior：移除 status data 後仍保留 GPT main env、呼叫 fake Claude 並正常結束。
- Live read-only smoke：no-op Claude 下先顯示 GPT main，再顯示與 `ccp-free` 相同的 GLM／DeepSeek／FreeLLMAPI 狀態。
- Secret boundary：mixed output 不含 client key 或 account email。
- Review fixed：Main 摘要改用實際 effective `ANTHROPIC_MODEL`；預設值顯示 `GPT-5.6 Sol`，caller override 則顯示並傳遞實際 model，不再固定誤報。
