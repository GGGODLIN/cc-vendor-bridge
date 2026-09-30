# 02 — 互動啟動自動顯示全表

**What to build:** 使用者互動啟動各支援的 CC 入口時，啟動器顯示第 01 票的完整表格，把本次入口置頂並顯示這次設定；print／非互動模式維持原輸出。

**Blocked by:** 01 — 手動查看即時映射表

**Status:** completed — 本地契約與補審降出項已核對，待 Git 共寫授權及實作後收尾

**Needs:** None — a worker can check every item unaided。使用隔離終端、假的服務檢查與只捕捉參數／模型環境的假 CC，不啟動真實模型 session。

**Validation method:** 在偽終端與非互動 subprocess 執行真正入口，檢查表格順序、marker、模型覆寫與假 CC 捕捉值；核對原 stdout／參數。程式完成後批次確認手動與啟動路徑，相關既有回歸測試只跑一次，區分既存失敗。

**Evidence required:** 各支援入口的偽終端輸出、假 CC 捕捉的模型環境與 argv、print／非互動原 stdout 比對、渲染失敗仍啟動的 exit status、合併驗證與局部回歸測試收據。

**TDD:** required

**TDD seam:** 已安裝入口在終端／print／非互動模式的可觀察輸出，以及傳給假 CC 的環境與參數。

- [x] 每個 spec 定義的支援入口在互動啟動時顯示同張完整表格，本次入口置頂且只標記一次「▶ 本次啟動」；委派給另一 wrapper 不產生重複表格。— Source: Story 2 — Failure: F5 — Confirmation
- [x] 本次列顯示最終模型環境及明示 model 參數；與假 CC 讀回的值相符。其他列不受本次 session 環境污染。— Source: Story 3 — Failure: F5 — Confirmation
- [x] 在同一 shell 改動隔離版本表後再啟動，表格與假 CC 同時讀到新型號；不出現只更新表格卻仍啟動舊模型的落差。— Source: Story 3、5 — Failure: F1 — Confirmation
- [x] 表尾顯示當次讀到的 `free`／`free-smart` 候選順序，不因此送推理請求或新增服務狀態輪詢。— Source: Story 5 — Confirmation
- [x] `-p`／`--print`、機器可讀輸出、非互動輸入與模型服務／MCP 子命令均不自動插入表格；原 stdout 保持原樣。— Source: Story 6 — Failure: F6 — Confirmation
- [x] 所有原啟動參數與模型、Fast header、明設 subagent model 保持不變；對照隔離既有啟動器讀回，不為顯示功能更換模型。— Source: Story 3、6 — Confirmation
- [x] 顯示資料缺檔、解析失敗或渲染器不可用時，只回報診斷並仍啟動假 CC；不把診斷混進原 stdout，不擅自改模型。— Source: Story 6、7 — Failure: F4 — Confirmation
- [x] `cc-luna`／`cc-free` 的共用顯示與 ccp 系列使用同一來源，支援入口沒有漏接，原廠直連仍不印。— Source: Story 2、4 — Failure: F5 — Confirmation
- [x] 表格、未知來源診斷與啟動錯誤中均沒有假的 key／token canary；不讀取與顯示無關的帳號憑證。— Source: Story 7 — Confirmation
- [x] 合併驗證產生手動全表、本次入口置頂、覆寫、版本與候選更新、腳本模式原樣輸出等收據；與未做的真實推理／計費驗證分開回報。— Source: Story 1、2、3、5、6 — Contract

## Approval

使用者已確認兩票的粒度、阻塞關係與 TDD 決策：在 main 提出的兩票清單後回覆「可以」。`ticket-breakdown-user-approved`。

## Verification Log

- RED：真啟動器接假 CC 的偽終端驗收先觀察到缺少整張啟動表、入口置頂、model 覆寫顯示及同一 shell 的版本同步；print／非互動等既存保護行為維持通過。
- GREEN：第二票的驗收批次通過，逐一啟動已批准的入口，確認完整表只顯示一次、當前入口置頂、假 CC 只啟動一次；CLI 參數與模型／Fast 設定保持原樣。另以窄終端驗證入口名稱不被拆碎。
- 原資料來源修正：GPT 版本在每次最外層入口重讀，巢狀 wrapper 共用該次版本值；顯示使用已送給 CC 的 env 與明示 model 參數，其他列使用乾淨預設。啟動後的 `/model` 切換與上游權重不在本次驗證範圍。
- 未解析 Cline 虛擬 model 保留原名並明示終點未解析；有獨立 RED→GREEN CLI 收據，未猜權重也未新增模型探針。
- 動工前 GPT routing 測試直接讀取真實版本表時已有版本斷言失敗；改用隔離 fixture 固定測試輸入，並把已替換的靜態說明斷言改為新表格契約。未改真實版本表或動工前 GPT smart 路由政策。
- 票級補審已核對：降出未變的既有 helper、規劃來源與 README 附帶說明，不刪除已批准契約；兩 repo 的跨入口證據由 main 的實際啟動驗收覆蓋。
- Acceptance-miss — 不完整版本表沿用舊 Sol 但更新新 Luna：以同一 shell 的部分更新重現。改為驗證完整版本後原子更新；失敗時不混版，保留原完整啟動設定並把表格來源標未知。局部 RED→GREEN 與相關回歸通過。
- 持久收據已保存於本機 receipts，包含原始紅綠、最初全套結果、失敗項單檔修正與四個受影響測試的最新結果。真實推理／帳號健康／計費仍未驗。
- 正確性審查的已重現功能缺陷都做最小修正，未重新開完整 review；獨立 task-verifier 與 Git 權限收尾仍在處理，尚未宣稱發布。
