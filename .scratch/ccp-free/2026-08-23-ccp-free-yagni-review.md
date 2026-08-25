# ccp-free YAGNI Review

## 三句入口

- 這輪在審值不值得做：值得做隔離、可還原、只打 NVIDIA 的最小 `ccp-free`，不值得先建多 provider 基礎設施。
- 兩席一致認為太早的部分：未來 provider 擴充、動態 model discovery、過大的測試矩陣；對 launchd、key 複製與 safe-trial 強度有分歧。
- 本輪處置：spec 已縮成單一 NVIDIA v1；沒有剩餘 scope、行為或風險承擔需要使用者拍板。

## Reviewer 與完整性

- Gemini 3.7 Flash (High)：[`2026-08-23-yagni-agy.md`](2026-08-23-yagni-agy.md)，主表 31/31 條。
- routed-judge（同族 fresh reviewer）：[`2026-08-23-yagni-routed-judge.md`](2026-08-23-yagni-routed-judge.md)，主表 31/31 條。
- Review packet：[`2026-08-23-yagni-packet.md`](2026-08-23-yagni-packet.md)。

兩席最終建議皆為 `縮成最簡版`。

## 分母

兩席都判 `未定價`：spec 沒有列出過去發生次數、每次損失或預期使用頻率。因此 v1 以使用者明確要求的最小可用路線為上限，不把長期維護收益當成驗收項。

## 逐條處置

| 原條目 | Gemini | routed-judge | 作者處置 | 理由 |
|---|---|---|---|---|
| US1 `ccp-free` 獨立入口 | keep | keep | keep | 使用者明確選定。 |
| US2 FCC 承擔 provider 維護 | keep | demote-v2 | simplify | 保留 FCC endpoint；v1 不宣稱已證明長期維護收益。 |
| US3 只允許免費來源 | keep | keep | keep | 核心邊界。 |
| US4 複用既有 NIM key | keep | demote-v2 | keep | Reviewer packet 缺選項上下文；使用者選的 `a` 明確代表複製進隔離 FCC config，屬 mental-model correction。 |
| US5 真實 NIM prompt 才算可用 | keep | keep | keep | 核心驗收。 |
| US6 runtime 隔離 | keep | keep | keep | 避免碰既有中繼站。 |
| US7 保留正常 Claude 環境 | keep | keep | keep | 使用正常 `claude` 與 process-local env。 |
| US8 loopback＋private token | keep | keep | keep | 最低安全邊界。 |
| US9 wrapper 自動啟動／恢復 | keep | keep | keep | 保留按需啟動。 |
| US10 啟動失敗即停止 | keep | keep | keep | 防止誤走付費來源。 |
| US11 pin commit | keep | keep | keep | 可重現 trial。 |
| US12 restore path | keep | keep | keep | safe-trial 必要產物。 |
| US13 未來 provider 擴充 | demote-v2 | kill | remove | 第二個 provider 出現再開題。 |
| US14 provider 健康紀錄 | demote-v2 | keep | simplify | 只寫進 safe-trial 當次證據，不建長期帳。 |
| US15 既有測試保持綠燈 | keep | keep | keep | 低成本回歸 gate；更新後重新編為 US14。 |
| ID1 獨立 project＋venv | keep | keep | keep | 最小安裝隔離。 |
| ID2 pin exact commit | keep | keep | keep | 不使用 mutable `main.zip`。 |
| ID3 不用 all-in-one installer | keep | keep | keep | 避免安裝無關 client 與桌面整合。 |
| ID4 dedicated runtime home | keep | keep | keep | 隔離 `.fcc`、auth 與 logs。 |
| ID5 loopback＋port＋auth | keep | keep | keep | 隔離與額度防護。 |
| ID6 launchd service | keep | kill | simplify | 改成無 `RunAtLoad`、無 `KeepAlive` 的按需 launchd job；避免 unmanaged orphan，也不常駐。 |
| ID7 health-check＋kickstart | keep | demote-v2 | keep | kickstart 對象改為按需 job，保留 bounded wait 與 fail-closed。 |
| ID8 使用正常 `claude` | keep | keep | keep | 不採會重寫環境政策的 `fcc-claude`。 |
| ID9 route marker＋model discovery | demote-v2 | keep | simplify | 保留 route marker；改用 live probe 成功的固定 model ID，延後 discovery。 |
| ID10 初始只接 NVIDIA | keep | keep | keep | v1 唯一 provider。 |
| ID11 複製現有 NIM key | keep | demote-v2 | keep | 使用者已明確拍板 option `a`；只複製這一把。 |
| ID12 secret 檔 user-only | keep | keep | keep | 不進 git。 |
| ID13 禁止 paid fallback | keep | keep | keep | 免費路線核心邊界。 |
| ID14 inventory 與 live health 分離 | keep | keep | keep | config 不算存活證據。 |
| ID15 safe-trial＋7 日 review | demote-v2 | keep | keep | 外部陌生工具安裝的既有 hard requirement，不由個案 reviewer 降級。 |
| ID16 單一來源通過即停工 | keep | keep | keep | 防止 v1 擴張。 |

## 測試縮減

原測試清單收斂成六個 focused checks：wrapper fake test、server auth smoke、真實 NVIDIA prompt、secret leakage、safe-trial/restore、既有 wrapper regression。移除「完整矩陣」措辭，不降低 safe-trial 的 mandatory Stage 0 與 snapshot gate。

## Spec 修改

已更新 [`spec.md`](spec.md)：

- 移除未來 provider 擴充 story。
- provider 健康結果只進 safe-trial evidence。
- launchd 改成按需 job，不開機啟動、不 KeepAlive。
- v1 固定使用 live probe 成功的 model ID，延後 gateway model discovery。
- 測試矩陣縮成 focused checks。
- 補明 option `a` 的完整 credential 決策，避免 reviewer 再把 key 複製誤判為模型推導。
