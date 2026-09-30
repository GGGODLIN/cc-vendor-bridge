# 即時映射表驗證紀錄

## 驗收範圍

手動 `ccp-list` 完整表、指定入口置頂、互動啟動全表、本次設定覆寫、同一 shell 的版本更新、免費池排序與停用過濾，以及 print／非互動輸出不插入表格。

測試使用隔離版本與候選設定、假 CC 程式與偽終端。沒有以測試通過推論真實模型品質、權重、quota 或計費。

## 枚舉與結果

非推理套件枚舉來源為模型入口 repo 的 `tests/*.zsh`、`tests/test_*.py`，另加分流 repo 的 `go test ./...`。共 9 個命令，初次 8 個通過；唯一失敗是原 `ccp-list` 固定說明文案的斷言，已按照批准的新表格契約改為驗證兩條實際候選列。該失敗命令局部重跑通過，其餘未改動的成功驗證保留，沒有重跑整套來製造新證據。

- 手動表的隔離驗收批次與來源更新測試通過。
- 啟動驗收批次通過；逐一執行已批准的入口，完整表只出現一次，本次入口列置頂，顯示過程不額外啟動 CC。
- 顯示錯誤回報不混入 CC stdout，假 CC 仍按原參數啟動。
- `free`／`free-smart` 順序由當次 YAML 產生；停用項不列，錯誤旗標型別回報未知，虛擬 Cline 名稱的終點未解析時不猜模型。
- 動工前的 GPT routing 原基線已因真實版本表不同而失敗；其測試輸入改為隔離 fixture，真實版本表與模型路由未因測試而改動。

本機執行收據保留在此 feature 的 receipts 目錄；該目錄由本機 Git exclude 排除，不發布含機器路徑的執行日誌。

## 可重用配方

在模型入口 repo 執行：

```bash
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_model_map.py
PYTHONDONTWRITEBYTECODE=1 python3 tests/test_launch_model_map.py
zsh tests/ccp-free-wrapper.test.zsh
zsh tests/ccp-gpt-routing-fast.zsh
```

前兩個命令驗證完整模型表與真正啟動器接假 CC 的輸出；後兩個命令是相關既有回歸契約。改動未涉及分流服務的路由程式，仍以 Go 套件測試確認既有保護未改變。

## 審查界線

- 票級 YAGNI 使用既有 Inline 補審入口；兩票的判官只要求將既有 helper、規劃來源與附帶操作文件降出該票的新增程式交件，不要求刪除已批准功能。
- 不將票級判官未收到的另一 repo 接線或未附的執行日誌說成判官已審。
- 正確性審查的已重現功能缺陷均已最小修正，且只跑受影響測試，沒有重開整輪 review。
- task-verifier 使用新的版本／候選與無憑證 HOME fixture，獨立公開 CLI probe 通過；其 PASS 僅指本地契約，不能推論實際模型品質或發布狀態。
- 增加舊 native 入口缺少預覽能力時拒絕執行的保護；模型表測試與互動入口的局部回歸通過。此檢查只辨識本次支援的入口版本，不宣稱任意帶 marker 的程式都安全。
- cc-split-proxy 的獨寫接線已 commit 並 fast-forward 進本地 main；沒有 remote。主 repo 的模型入口與 GPT 測試為共寫，治理索引另有 foreign staged，正常 self-closeout 尚不能提交；實作後審查與發布未完成。

## 未驗證

- 真實 Claude Code E2E 的 opt-in 測試未開啟。
- 真實 Codex 帳號健康；帳號路由測試使用隔離合成 claims。
- 上游推理、真正模型權重、額度、計費與實際 fallback 命中。
- 啟動後 `/model` 切換的持續追蹤。
