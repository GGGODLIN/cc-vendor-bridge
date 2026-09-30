# 01 — 手動查看即時映射表

**What to build:** 使用者執行 `ccp-list` 後，看見當下完整非直連模型映射表與兩條免費池順序；指定入口時把該入口置頂，清楚標示是查詢預覽而非已啟動。

**Blocked by:** None — can start immediately

**Status:** completed — Inline 補審的降出項已核對並記錄，待兩票合併驗證

**Needs:** None — a worker can check every item unaided。以隔離版本表、relay／下游設定與假啟動器驗證，不需要真實模型憑證或推理請求。

**Validation method:** 先寫 CLI 外部輸出的失敗測試，使用隔離資料驗證映射、同一 shell 的版本更新、候選排序、錯誤顯示與敏感值排除。確認項於兩票程式寫完後合併驗證；每票的 RED→GREEN 測試不等待該合併批次。

**Evidence required:** CLI 輸出樣本、RED／GREEN 命令與結果、來源改動後的新輸出、缺檔／壞格式診斷、credential canary 未出現在輸出的斷言。

**TDD:** required

**TDD seam:** `ccp-list` 的 stdout／stderr 與 exit status。

- [x] 手動查詢顯示所有 spec 定義的非直連入口，含主 session、Fable、Opus、Sonnet、Haiku；原廠直連與管理 helper 不列。— Source: Story 1、4 — Confirmation
- [x] 指定一個支援入口時，該入口列排第一且只標記一次「▶ 查詢入口」；其他列仍為各自的預設。— Source: Story 1 — Confirmation
- [x] 同一 shell 內第一次查詢後修改隔離 GPT 版本表，不重新 source，第二次查詢讀到新的型號。— Source: Story 5 — Failure: F1 — Confirmation
- [x] 改動隔離 relay priority／disabled 後，下次查詢顯示新順序且沒有停用候選；`free` 與 `free-smart` 分開產生。— Source: Story 5 — Failure: F5 — Confirmation
- [x] 缺省 priority、排序同分與沒有 active 候選的輸入有可觀察且穩定的結果，不把空候選寫成「可用」。— Source: Story 5、7 — Failure: F6 — Confirmation
- [x] relay／版本資料缺檔、半寫、null 或錯誤型別時明報來源與未知，不回放舊資料或捏造已解析結果。— Source: Story 7 — Failure: F2、F4 — Confirmation
- [x] 可解析的下游模型名稱與 source 相符；無法解析時保留設定名稱並標示終點未解析，不猜測實際模型或權重。— Source: Story 5、7 — Failure: F3 — Confirmation
- [x] 該功能只讀取顯示所需資料，不送模型推理請求、不啟停服務、不顯示 key／token／敏感 header；假的 credential canary 不出現在 stdout／stderr。— Source: Story 1、7 — Confirmation
- [x] 表格與實際啟動模型使用同一份槽位來源；不新增第二份手動維護的版本、槽位字串或免費池清單。— Source: Story 1、5 — Failure: F5 — Confirmation
- [x] 不改現有各入口的模型選擇、強制固定／覆寫規則、Fast header 或既有 subagent 路由政策；不覆蓋動工前已有變更。— Source: Story 3、6 — Confirmation

## Approval

使用者已確認兩票的粒度、阻塞關係與 TDD 決策：在 main 提出的兩票清單後回覆「可以」。`ticket-breakdown-user-approved`。

## Verification Log

- RED：CLI 驗收批次在缺少映射表、指定入口置頂與來源錯誤回報時出現斷言失敗；只讀與不洩漏既存條件原先即成立。
- GREEN：首次批次只有一條斷言失敗，其餘案例通過；該斷言把標題「未探測上游可用性」誤讀為可用宣稱。依空候選不得寫成可用的 spec，將斷言限定至池狀態列；局部重跑通過。沒有修改產品行為，也沒有擴掃其他測試。
- 驗證配方：以隔離版本表、relay 與下游 YAML 執行真正 `ccp-list`；替代 HOME、目前 session 的模型 env 與候選排序均不成為其他列的來源。預覽執行真正 wrapper 的 env 決策，於服務／憑證前置檢查前進入唯讀模式，不啟動 CC。
- 收據目前保存於本次 session 的暫存目錄；合併驗證後更新持久收據指針。
- Inline 票級 YAGNI 補審已取得 verdict；coverage 的 missing／extra 都為空。判官要求降出的兩個 helper 經 baseline 比對完全未變，故不當成本票新增項；spec 與第 02 票是已批准的規劃資料，不納本票程式交件，亦不刪除原始驗收來源。沒有新增功能被要求砍除。
- Runner 未將另一 repo 的分流 helper 納入 packet；其唯讀預覽由 main 的實際 CLI 驗收批次與當前設定全表讀回另行覆蓋，不把這部分說成判官已審。
- Acceptance-miss — 未知下游未標未解析、provider 缺 models 誤當空池：以新 CLI fixture 重現後最小修正，局部測試通過；沒有加入模型探針或另外重跑整輪 review。
- 完整非推理套件初次只有舊靜態說明斷言失敗；按新表格契約修正後單檔重跑通過。review 修正後只重跑受影響的模型表、啟動表、GPT routing 與 free wrapper，四個命令皆 exit 0；其他未改動的成功驗證保留。
