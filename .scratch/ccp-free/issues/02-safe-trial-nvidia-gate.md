# 02 — Gate：safe-trial 安裝並驗證 NVIDIA

**What to build:** 以 safe-trial 在真機建立完全隔離的 FCC runtime，只接入使用者已核准複用的 NVIDIA NIM key，並透過受保護的本機 endpoint 完成真實模型請求；此結果決定 `ccp-free` 是否值得繼續實作。

**Blocked by:** 01 — Gate：在 Docker 引爆 FCC 安裝

**Status:** completed

**Needs:** Stage 0 `PASS`、可讀取現有 CLIProxyAPI NVIDIA NIM key 的本機權限、可用網路、NVIDIA provider 可連線。

**TDD:** required

**TDD seam:** FCC 對 localhost 暴露的 authenticated HTTP endpoint

- [x] 先建立會因 endpoint 尚未存在而失敗的 HTTP smoke test，覆蓋未帶 token 被拒絕、帶 token取得 model catalog，以及最小 prompt 回傳非空內容。
- [x] safe-trial command 只安裝鎖定 commit 的 FCC package 到獨立 project／venv，並使用專屬 runtime home、loopback host、專屬 port 與 generated proxy token。
- [x] 只從現有 credential source 複製 NVIDIA NIM key；不得輸出值、不得複製其他 credential、不得把 secret 寫進 git repo，runtime secret 檔必須是 user-only 權限。
- [x] 從 FCC catalog 選出 NVIDIA 模型後送出真實 prompt；catalog 存在但 prompt 失敗不得判通過。
- [x] 確認 FCC endpoint 與既有 CLIProxyAPI port、runtime home、config、logs 和 process 完全分離。
- [x] safe-trial 產出 before／after snapshot、restore dry-run 與七日 review entry；只有真實 prompt `PASS` 能解除 Ticket 03 的 blocker。

## Verification Log

- 2026-08-23：舊 safe-trial 會把 `.codex/shell_snapshots` 內的 exported NVIDIA key 複製進 before／after；Ticket 02 fail-closed，FCC process 已停止。使用者明確接受免費 key 風險，不要求輪替或刪除原始 snapshots。
- 已修正 safe-trial：rsync／tar fallback 都在 copy 前排除 `shell_snapshots/`，snapshot 失敗不得執行 wrapped command。
- Reviewer finding 已確認並修正：rsync error／缺少 copy tool 的 fail-open，以及無 trailing slash bulk-copy mutation 的 test false-green。
- 真機續跑再發現 `.codex/ipc/ipc.sock` 會讓 rsync before snapshot fail-closed；已用真 AF_UNIX socket 加入 RED→GREEN 契約，root-level `/ipc` 現在於 copy 前排除。Focused test 22 項全數通過（含移除 `/ipc` exclude 的 tar mutation 反證）。
- 已知限制：hardlink alias 與 nested `other/shell_snapshots` 不納入本次 root-level exclusion；目前沒有證據會影響本 ticket 的真實 root-level runtime 路徑。
- v3 Gate `PASS`：未授權 401、catalog 200、`nvidia_nim/nvidia/nemotron-3-super-120b-a12b` 真實 prompt 200 且回傳非空；server停止、18082 free，完整證據見 `../evidence/02-safe-trial-nvidia.md`。
- safe-trial Self-Verify：COMPLIANT 4/4；R1 list新增集合為空、R2 ledger +7日完整、R3 manifest引用完整、R4 Stage 0結論完整。
- 獨立 security calibration：runtime dependencies 使用 ranges且未hash-lock，屬需外部package/index先被compromise才能利用的LOW supply-chain exposure；不推翻2026-08-23 v3 live Gate。未來重裝的provenance／reproducibility列為已知限制。
