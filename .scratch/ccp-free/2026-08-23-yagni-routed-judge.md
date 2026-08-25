## 三句入口
- 這輪在審值不值得做：值得先做隔離、可還原、只打 NVIDIA 的 live probe，不值得先建完整免費 provider 基礎設施。（唯一來源：[packet](file:///Users/linhancheng/Desktop/projects/cc-vendor-bridge/.scratch/ccp-free/2026-08-23-yagni-packet.md)）
- 太早的部分：launchd 常駐生命週期、搬移 key、未來多 provider，以及完整測試與快照矩陣。
- 現在只需決定：先驗證 isolated FCC、正常 `claude`、真實 NIM prompt 與 no-fallback 是否成立。

## 一頁最簡方案
1. 在獨立 project、venv 與固定 upstream commit 中安裝 FCC，不使用 all-in-one installer。
2. 建立獨立 runtime home、loopback port、private token，只設定 NVIDIA NIM。
3. 以 runtime-only、user-only 的方式注入既有 NIM key，不輸出、不寫入 repo；缺 key 就停止。
4. 讓 `ccp-free` health-check 並啟動自己的 FCC process，限時等待；失敗就輸出診斷並停止。
5. 使用正常安裝的 `claude` binary，透過 process-local endpoint、auth、free-route 與 gateway-discovery env 連線，不提供任何 paid fallback。
6. 驗證 authenticated `/v1/models`、catalog model 的真實 prompt、錯誤 token 拒絕、既有 route 未變更；記錄日期、provider、model 與結果，保留 cleanup/restore 路徑。

## 分母
- verdict: `未定價`
- evidence: packet 只有需求與風險的質性描述，沒有過去發生次數、每次損失或使用頻率。

## 逐條表

| # | 條目 | 來源類 | verdict | 一句理由 |
|---|---|---|---|---|
| US-01 | 提供獨立 `ccp-free` command | user | keep | 使用者直接選定此路線；沒有獨立入口就無法刻意進入免費路線。 |
| US-02 | 以 FCC 作為 endpoint、由 upstream 維護 provider 整合 | user | demote-v2 | 這是價值假設而非維護收益證據；v1 先證明 FCC route 可用即可。 |
| US-03 | 只允許明確免費來源 | user | keep | 使用者直接支持；移除後可能靜默消耗 paid 或 subscription-backed route。 |
| US-04 | 重用既有 NIM key 且不暴露 | user（引文不直對應） | demote-v2 | packet 只有「驗證可用性」，沒有直接支持重用或搬移 key；先用 runtime-only 注入即可。 |
| US-05 | 真實 NVIDIA request 成功後才算 usable | user | keep | 使用者直接要求 live validation；catalog 或 config 存在不等於 provider 活著。 |
| US-06 | FCC runtime 與既有 runtime 隔離 | inferred | keep | 若砍掉，重啟、改 config 或移除 trial 可能碰到既有 CLIProxyAPI。 |
| US-07 | 保留正常 Claude Code config、skills、hooks、agents、sessions、credentials | inferred | keep | 使用正常 `claude` 加 process-local env 已是最小解。 |
| US-08 | loopback binding 與 private bearer token | evidence | keep | 這是防止區網消耗 quota 的最低邊界。 |
| US-09 | command 自動啟動或恢復自己的 server | evidence | keep | 直接由 wrapper 啟動 process 即可，不需要 launchd。 |
| US-10 | 啟動失敗時診斷並停止，不 fallback | inferred | keep | 若砍掉，失敗可能落到 Anthropic 或既有 endpoint。 |
| US-11 | 初始安裝固定 exact upstream commit | evidence | keep | 固定 commit 保留 trial 可重現性。 |
| US-12 | 提供完整 restore path | evidence | keep | trial 仍需明確清理 credential、process 與檔案。 |
| US-13 | 後續 provider 透過 FCC config 擴充且 command 不變 | inferred | kill | 第一版明確只有 NVIDIA，現在沒有具體損失。 |
| US-14 | 記錄目前 provider 與最後 live verification | inferred | keep | 一筆日期、model、結果的紀錄成本很低。 |
| US-15 | 既有 cc-vendor-bridge tests 維持綠燈 | evidence | keep | 這是防止新增 route 破壞既有 mapping 的低成本 gate。 |
| ID-01 | 獨立 setup project 與 venv | inferred | keep | 避免污染全域 uv/python 環境。 |
| ID-02 | pin exact FCC commit，不裝 mutable `main.zip` | evidence | keep | 保持安裝版本可重現。 |
| ID-03 | 不使用 upstream all-in-one installer | evidence | keep | 避免安裝無關 agent 與 desktop integration。 |
| ID-04 | dedicated runtime home | inferred | keep | 避免 `.fcc`、auth、logs、artifacts 與正常 home 重疊。 |
| ID-05 | loopback、dedicated port、proxy auth token | evidence | keep | 避免 port collision 與區網未授權使用。 |
| ID-06 | dedicated launchd service 管理 FCC lifecycle | evidence | kill | 沒有 v1 必須常駐的需求；wrapper-owned process 已足夠。 |
| ID-07 | health-check、kickstart dedicated service、bounded wait、failure abort | evidence | demote-v2 | 保留 health-check、bounded wait、abort；改成直接啟動 isolated process。 |
| ID-08 | 使用正常 `claude` binary，不用 `fcc-claude` | evidence | keep | 避免 FCC launcher 移除 env 並改變 Claude Code 行為。 |
| ID-09 | free marker、gateway discovery，其他行為維持不變 | inferred | keep | env 變更小，並可由 live test 驗證。 |
| ID-10 | 初始只接 NVIDIA，選 catalog 中且真實 prompt 成功的 model | user | keep | 符合真實可用性要求。 |
| ID-11 | 讀取既有 NIM key 並直接複製到 FCC config | user（引文不直對應） | demote-v2 | 複製 key 增加 secret surface，runtime-only 注入可完成同一驗證。 |
| ID-12 | secret runtime files user-only 且離開 git repo | inferred | keep | 避免 key 或 token 被其他使用者或 git tracking 讀取。 |
| ID-13 | 不含 CLIProxyAPI、Codex、Anthropic 或 paid fallback | user | keep | 這是免費路線邊界。 |
| ID-14 | 分離 provider inventory 與 provider health | user | keep | config 不能代替 live probe。 |
| ID-15 | safe-trial snapshot、七日 review、dry-run restore | evidence | keep | trial 需要可還原邊界，不得自動升級成永久基礎設施。 |
| ID-16 | NVIDIA route 通過 acceptance 後停止，其他 provider 延後 | inferred | keep | 有效限制第一版 scope。 |

## 超出最簡版

| 條目 | spec 多做什麼 | 具體收益是否成立 | 建議 |
|---|---|---|---|
| US-02 | 把 FCC 持續 upstream 維護當成 v1 驗收 | 部分成立，但沒有頻率或成本分母 | 將維護收益降為 v2 假設 |
| US-04 / ID-11 | 把既有 key 複製進 FCC config | runtime-only 注入也能完成真實 prompt，且少一個 secret copy surface | demote-v2 |
| US-13 | 先設計未來 provider 擴充 | 未定價；第一版只有 NVIDIA | kill |
| ID-06 / ID-07 | launchd label、service lifecycle 與 kickstart | v1 未證明需要常駐 | 移除 launchd，保留 bounded health-check |
| Testing Decisions | 完整 fake wrapper、server auth、secret-handling 測試矩陣 | 核心安全與 live probe 要測，完整 harness 可延後 | 先做 focused smoke tests |
| Safe-trial延伸驗證 | Stage 0 Docker、完整 snapshot diff、byte-for-byte unchanged、restore-target audit | restore path 必須保留，但完整矩陣不是核心可用性證據 | v2 再補完整回歸矩陣 |

## 最終建議

`縮成最簡版`——先保留隔離、真實 NVIDIA prompt、no-fallback 與 restore；launchd、完整測試矩陣與多 provider 擴充等有實際需求後再升回。
