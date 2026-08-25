# 04 — Confirmation：全鏈驗收與還原預演

**What to build:** 對完成後的 `ccp-free` 做一次完整真實驗收，證明冷啟動、NVIDIA 路由、既有 stack 隔離、secret 邊界與還原路徑都符合 spec，並把證據寫進 trial 紀錄。

**Blocked by:** 03 — 建立 `ccp-free` 冷啟動路線

**Status:** completed

**Needs:** 可用 NVIDIA NIM provider、完成的 `ccp-free` wrapper、隔離 FCC runtime、現有 CLIProxyAPI service 正常執行。

**TDD:** waived

**TDD waiver:** `non-executable-artifact`

**TDD waiver approved:** `ticket-breakdown-user-approved`

- [x] 在 FCC process 未執行的前提下呼叫 `ccp-free`，觀察它冷啟動專屬 job 並完成一個非空真實 prompt。
- [x] 用 server evidence 確認請求實際由已核准的 NVIDIA provider／model 處理，而不是 Anthropic、CLIProxyAPI 或其他 fallback。
- [x] 確認 FCC 意外退出後不會由 launchd 自動重啟；下一次呼叫 `ccp-free` 才會再次啟動。
- [x] 確認既有 CLIProxyAPI service、port、`ccp-gpt` 與 `ccp-relay` 行為不變，並執行所有相關 regression tests。
- [x] 掃描 git diff、tracked files、test output 與 logs，確認 NVIDIA key、generated token 和其他 credential 均未洩漏。
- [x] 執行 restore script dry-run，確認只涵蓋本 trial 新增的 runtime、job、wrapper 與設定，不會碰既有 stack。
- [x] 在 safe-trial evidence 中記錄驗證日期、FCC commit、NVIDIA provider、model、實際結果與未做項目。

## Verification Log

- 歷史首輪FAIL：launchd執行Desktop path遭TCC拒絕（exit126）；已由Ticket03 commit`c2c4ca5`移至runtime path修正，歷史證據保留。
- Corrected first cold-start：`ccp-free --print` exit0、非空且marker match；runs 1→2。
- Provider/model：FCC metadata HTTP200、102rows、exact `nvidia_nim/nvidia/nemotron-3-super-120b-a12b` 1match；disallowed route分類0。
- Crash boundary：SIGKILL後3秒runs不增、registered/not-running、18082free；第二次wrapper call才runs 2→3並回非空marker；SIGTERM後仍not-running/free。
- Existing stack：CLIProxyAPI PID2415、8317與service identity不變；bridge tests 6/6、62 pass、0fail。
- Secret scan：15,378 files＋2 diff blobs，NVIDIA key/proxy token非法hits皆0。
- Restore dry-run：7條manual plan，僅專屬job/plist/runtime與commits`38fa1cf`,`c2c4ca5`,`1f9ab55`,`29991bd`；未execute。
- 最終狀態：job registered/not-running、runs3、18082free；CLIProxyAPI running/8317open。完整證據見`../evidence/04-confirm-live-route-and-restore.md`。
- Final review後再驗：real marker prompt exit0，launchd PID與lsof owner一致；rogue listener negative control使wrapper exit1、fakeclaude未叫、listener收到0 bytes；fresh registration helper與exact-model tests PASS。最終job重新bootstrap為registered/not-running、runs0、18082free。
