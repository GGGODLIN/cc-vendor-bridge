# 01 — 讓 ccp-free 顯示免費池啟動摘要

**What to build:** 呼叫 `ccp-free` 時，在 Claude Code 接管 terminal 前顯示短行免費池摘要，區分 observed service、configured intent、備援、degraded 與 failure；狀態查詢失敗時保留診斷但不得阻擋原本可用的 wrapper。

**Blocked by:** None — can start immediately

**Status:** completed

**Needs:** 現有 wrapper fixture 可提供 fake Claude binary、fake relay readiness 與可控制的免費池狀態資料；worker 不需真實 provider quota 或 secret。

**TDD:** required

**TDD seam:** 呼叫 `ccp-free`，捕捉 fake Claude binary 執行前的 stderr 與 wrapper exit behavior

- [x] 新增共用免費池 status 診斷，`ccp-free` 成功路徑在啟動 Claude 前恰好呼叫一次。
- [x] 有近期成功 evidence 時，以綠色 `服務中` 顯示 GLM account pool／`free(max)`。
- [x] 無近期流量時，以黃色 `預計使用` 顯示 configured route，並明寫健康未知。
- [x] DeepSeek 只描述為 GLM 整池不可用時的備援，不暗示 round-robin 或同 priority。
- [x] FreeLLMAPI route disabled 時只顯示停用資訊，不列為健康備援。
- [x] 部分 cooldown／daily limit、無 usable source、upstream failure 各有短警告；需要時附 `ccp-free-whoami` 與 local log 排查方式。
- [x] 狀態來源不可用時印一行黃色診斷，仍繼續呼叫 fake Claude 並保留原 wrapper exit behavior。
- [x] 正常輸出維持少量短行；不輸出 fixture key、auth token、prompt、completion 或 raw JSON body。
- [x] 現有 `free(max)` model slots、context、WebSearch、argument passthrough、relay kickstart 與 timeout contract 保持不變。

## Verification Log

- TDD RED：wrapper fixture 新增啟動摘要斷言後 exit `1`；缺少 `服務中`、`備援待命`、`FreeLLMAPI：已停用` 三行。
- TDD GREEN：新增共用 status 診斷並在 `ccp-free` 成功 preflight 後呼叫；同一 fixture exit `0`。
- Fixture variants：近期 GLM 成功、無近期流量、部分 GLM cooldown、GLM 整池不可用、全來源不可用、status data 缺失全部通過，且每條路徑仍呼叫 fake Claude。
- Secret boundary：fixture client key、management key 與 account email 均未出現在 startup output。
- Live read-only smoke：no-op Claude 下顯示 GLM `6/13` 可用、DeepSeek `3/6` 可用、FreeLLMAPI disabled；沒有送 inference request。
- Review fixed：帳號資格不再依賴 `modelStats`；近期成功必須與當前 availability 一致；只讀 GLM／DeepSeek 相關 request 並正規化 effort suffix；近期 failed request 會顯示；`cline-free-proxy` disabled／缺 `free` mapping 時不再宣稱服務中。
- Security review fixed：fixture 加入 refresh token、account ID、nested secret canaries，兩個 wrapper 都驗證不輸出。
- Review skipped：預設 status path 與 daemon runtime path 可能漂移屬推測；目前 launchd binary／cwd 都在 `~/.cline2api`，且已有 `CCP_FREE_ACCOUNTS_FILE`／`CCP_FREE_REQUEST_LOG_FILE` override，未擴大實作。
