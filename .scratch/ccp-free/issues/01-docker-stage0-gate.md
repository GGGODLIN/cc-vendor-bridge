# 01 — Gate：在 Docker 引爆 FCC 安裝

**What to build:** 在不接觸真機設定的拋棄式容器內，驗證鎖定版本的 Free Claude Code package 能被取得、安裝與啟動，並留下是否准許進入真機 safe-trial 的明確結論。

**Blocked by:** None — can start immediately

**Status:** completed

**Needs:** 可執行 Linux container 的 Docker daemon、網路僅供第二輪依賴下載、已選定的 Free Claude Code commit。

**TDD:** waived

**TDD waiver:** `non-executable-artifact`

**TDD waiver approved:** `ticket-breakdown-user-approved`

- [x] 第一輪以停用網路的拋棄式容器執行 package 安裝或 build，記錄哪些步驟要求對外連線，以及是否出現安裝後對外存取、寫入工作目錄外或其他可疑行為。
- [x] 若第一輪只因合法 dependency 下載而失敗，第二輪使用可連網的全新拋棄式容器完成安裝與 server startup smoke test。
- [x] 確認未使用 upstream all-in-one installer，且沒有安裝無關 coding agents、桌面整合、voice 或 messaging extras。
- [x] 記錄 exact upstream commit 與 Stage 0 結論；只有 `PASS` 能解除 Ticket 02 的 blocker，`FAIL` 必須停止後續 tickets。

## Verification Log

- `PASS`：完整證據見 `../evidence/01-docker-stage0.md`。
- Minor：FCC startup 會由 `tiktoken` 取得公開 tokenizer cache；Ticket 02 必須記錄並隔離該外連。
- Ticket 02 必須覆寫 upstream 的 all-interface／auth-off 預設，強制 loopback 與 private bearer auth。
