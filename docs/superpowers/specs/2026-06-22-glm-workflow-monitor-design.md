# `/glm-workflow-monitor` — design spec

**Date**: 2026-06-22
**Owner**: Philip (gggodlin)
**Status**: design approved, implementation pending

## Context

ccp-glm session 跑背景 Workflow 沒人盯時，會撞兩種 quota 風險：

1. **5h rolling token cap** — z.ai Coding Plan 在 5 小時滑動視窗有 token 上限（Lite tier 上限最緊），燒滿就 429。
2. **CN peak window 3× 倍率** — 每日 CN 時間 14:00-18:00 token 倍率 3×（非 peak 1×），peak 跑 workflow 等於三倍燒 quota。

`/workflow-monitor`（Anthropic 5h OAuth）跟 `/bruce-workflow-monitor`（Bruce pool healthPercent）已有 watch-pause-resume 完整 mechanic。本 spec 是同 pattern 的第三個 fork、針對 ccp-glm session。

Hook `~/.claude/hooks/workflow-monitor-nudge.sh` 對 `CC_VENDOR=glm` 目前是 silent — 註解原因「z.ai prompt 制結構不同、套不上 limit-watch」是錯的，因為 z.ai 已有公開 monitor endpoint 跟本地 cache 路徑（statusline GLM widget 已用）。本 spec 接 statusline 既有 signal 路徑、補上 hook gap。

## Goal

ccp-glm session 跑長 Workflow 時，跟 Anthropic / Bruce 同等保護：
- 5h token 撞 85% 自動 pause、降到 60% 自動 resume
- CN peak 14:00-18:00（± 5min buffer）自動 pause、結束自動 resume
- Weekly token cap 撞 95% 阻止 resume（避免 resume 後一秒 429）

不引入任何新外部 API call — 純讀本地 cache file（statusline 路徑共用），0 token cost。

## Non-goals

- 不重寫 Workflow tool 的 pause/resume mechanic（沿用 `/workflow-monitor` 的 TaskStop / inject-and-resume / GOLDEN snapshot / per-session isolation）
- 不做 monthly MCP tool quota 監控（`(TIME_LIMIT, 5, 1)` 跟 workflow token 用量無關）
- 不做 peak 倍率動態 threshold（peak 期間 token 燒得快、但 85% threshold 自然包住，不額外 adapt）
- 不做 multi-account routing（z.ai 單一 ZAI_API_KEY、cache 只有一個 vendor-glm-<profile>.json）
- 不取代 statusline GLM widget（widget 只顯示、本 skill 處理 workflow 守護動作）

## Signal source

讀 `~/.claude/cache/vendor-glm-<profile_id>.json`，由 cc-quota-fetcher chrome extension + native messaging host 推、跟 statusline GLM widget 共用。

Schema 驗證樣本（2026-06-22 10:07）：

```json
{
  "vendor": "glm",
  "profile_id": "4a6f8fb4",
  "data": {
    "level": "lite",
    "limits": [
      {
        "type": "TIME_LIMIT", "unit": 5, "number": 1,
        "usage": 100, "currentValue": 13, "remaining": 87, "percentage": 13,
        "nextResetTime": 1784434774990
      },
      { "type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 0 },
      {
        "type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 9,
        "nextResetTime": 1782447574978
      }
    ]
  }
}
```

### Limit key 對應（primary key 驗證自 opencode-glm-quota source + memory `reference_z_ai_glm_widget_integration_2026_06_19`）

| `(type, unit, number)` | 意義 | 用途 |
|---|---|---|
| `(TOKENS_LIMIT, 3, 5)` | 5h rolling tokens % | **主 trigger**（pause/resume threshold） |
| `(TOKENS_LIMIT, 6, 1)` | weekly tokens % | **二次 guard**（resume block 條件） |
| `(TIME_LIMIT, 5, 1)` | monthly MCP tool 月計數 | **忽略** |

### Fallback by `nextResetTime` window

z.ai 將來改 unit 編號不致 silently 變空：

- `TOKENS_LIMIT` 無 `nextResetTime` → 5h rolling
- `TOKENS_LIMIT` 且 5d < (reset - now) < 9d → weekly
- 其他 silently skip

## Trigger logic

### Pause（任一條成立）

| 條件 | 判定 |
|---|---|
| Token rule | 5h tokens percentage ≥ **85** |
| Peak guard | `TZ=Asia/Shanghai date +%H:%M` ∈ [13:55, 18:05] inclusive |

### Resume（**所有條件**成立）

| 條件 | 判定 |
|---|---|
| Token recovery | 5h tokens percentage ≤ **60** |
| Weekly headroom | weekly tokens percentage < **95** |
| Off-peak | `TZ=Asia/Shanghai date +%H:%M` ∉ [13:55, 18:05] |

統一 hysteresis、不分 pause 原因 — peak 期間 5h 漲到 60-85% 之間時、peak 結束後仍要等 5h 降 ≤ 60% 才 resume（保守設計、避免 peak 結束秒 burst）。

### TZ 寫死 Asia/Shanghai

不繼承本機 TZ。user 跨時區出差不會誤判 peak window。

## State + naming

| 用途 | 路徑 |
|---|---|
| Slash command | `~/.claude/commands/glm-workflow-monitor.md` |
| Watch script | `~/.claude/scripts/glm-quota-watch.sh` |
| State file (per-session) | `~/.claude/glm-workflow-monitor-state-<SESSION_ID>.json` |
| Args file (per-session) | `~/.claude/glm-workflow-monitor-args-<SESSION_ID>.json` |
| Fallback state (no SESSION_ID) | `~/.claude/glm-workflow-monitor-state.json` |
| Process tag for pgrep | `glm-quota-watch.sh` 字串（跟 anthropic `workflow-limit-watch.sh` / bruce `bruce-health-watch.sh` 不撞） |

State file schema（watching phase）：

```json
{
  "phase": "watching",
  "runId": "wf_xxx",
  "taskId": "task_xxx",
  "scriptPath": "/path/to/workflow.js",
  "sessionDir": "/path/to/.claude/projects/.../<SESSION>/workflows",
  "sessionId": "<SESSION_ID>",
  "pauseAt5h": 85,
  "resumeAt5h": 60,
  "weeklyCeil": 95,
  "peakStartCN": "13:55",
  "peakEndCN": "18:05"
}
```

State file schema（suspended phase）：

```json
{
  "phase": "suspended",
  "runId": "wf_xxx",
  "scriptPath": "/path/to/workflow.js",
  "sessionDir": "/path/to/.claude/projects/.../<SESSION>/workflows",
  "sessionId": "<SESSION_ID>",
  "argsFile": "/Users/.../glm-workflow-monitor-args-<SESSION_ID>.json",
  "pausedNote": "5h hit 87% / entered peak window / both"
}
```

## Watch script API

`~/.claude/scripts/glm-quota-watch.sh` invocation：

```
glm-quota-watch.sh <pause_pct> <resume_pct> <weekly_ceil> <poll_sec> <max_min> <direction> <SESSION_ID>
```

| arg | meaning |
|---|---|
| `pause_pct` | 5h % 達到就 fire（pause direction）；default 85 |
| `resume_pct` | 5h % 降到才 fire（resume direction）；default 60 |
| `weekly_ceil` | weekly % 上限（resume direction 才檢查）；default 95 |
| `poll_sec` | tick interval；default 30 |
| `max_min` | safety timeout；default 360 (6h) |
| `direction` | `pause` or `resume` |
| `SESSION_ID` | 5th arg、ps-visible session filter |

Exit conditions：

- `direction=pause`：5h ≥ pause_pct OR in peak window → print `GLM-LIMIT pause ... ACTION: invoke /glm-workflow-monitor pause` → exit
- `direction=resume`：5h ≤ resume_pct AND weekly < weekly_ceil AND NOT in peak → print `GLM-LIMIT resume ... ACTION: invoke /glm-workflow-monitor resume` → exit
- Cache stale > 15 min → print `GLM-LIMIT abort: cache stale` → exit non-zero（不誤觸發）
- Safety timeout → exit normally

### Staleness guard

- `mtime > 5 min` → tick 印 warning 到 stderr、但 watch 仍跑
- `mtime > 15 min` → watch abort、不誤觸 pause/resume（chrome ext / receiver runtime 副本可能斷）

## Hook routing

`~/.claude/hooks/workflow-monitor-nudge.sh` 在 `bruce)` 後加 `glm)` case：

```bash
glm)
  read -r -d '' CTX <<'EOF' || true
背景 Workflow 剛在 ccp-glm session 啟動。一律 invoke glm-workflow-monitor skill 的 watch 模式守護它撐過 z.ai 5h token 上限 + CN peak window 倍率燒費——掛的成本極低（一個背景本地 cache 輪詢，no token cost），不掛的代價（5h 撞滿觸發 429 / peak 期間 3× 燒爆 quota）大且不對稱。它會掛 background glm-quota-watch（poll ~/.claude/cache/vendor-glm-*.json，5h ≥ 85% 或進 CN peak 13:55-18:05 自動暫停、5h ≤ 60% 且離 peak 且 weekly < 95% 自動 resume）。啟動結果裡有它需要的 Task ID / Run ID / Script file。
EOF
  jq -n --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
  exit 0
  ;;
```

## Document structure

`~/.claude/commands/glm-workflow-monitor.md` 仿 `bruce-workflow-monitor.md` lean fork pattern — 只寫 glm-specific divergence、共通機制全引用 `/workflow-monitor`：

| Section | 內容 |
|---|---|
| Front-matter `description` | hook detection 用、明寫適用條件（ccp-glm session、watch-pause-resume by 5h tokens + peak window） |
| §0 — show current quota | 解 cache file、印 5h % + weekly % + 是否在 peak window |
| §0a — resolve SESSION_ID | 從 launch result `Transcript dir:` 抽 SESSION_ID、組 state/args path |
| §1 — pick mode | `$ARGUMENTS` → explicit；否則讀 state file 自動判斷 |
| §W — WATCH | duplicate guard、寫 state、launch background `glm-quota-watch.sh ... pause ...`、處理兩種 wake-up |
| §2 — PAUSE | TaskStop → 讀 killed journal capture args → GOLDEN snapshot → flip suspended → arm reverse watch |
| §3 — RESUME | kill reverse watch → run inject helper → Workflow({scriptPath, resumeFromRunId}) → fork-from-GOLDEN fallback |
| Cross-session fallback | 引用 `/workflow-monitor` 同段 |
| When NOT to resume | 引用 `/workflow-monitor` decision tree |
| 踩過的坑 | **glm-specific only**（共通機制坑全引用 `/workflow-monitor`） |

## GLM-specific 踩過的坑（預寫進文件）

1. **Cache 由 chrome extension 推、不是 CC 自己 refresh** — chrome 沒開 / extension disabled / receiver runtime 副本沒部署 → cache stale 但 watch 看舊值。Staleness guard：mtime > 5 min 印 warning、> 15 min watch abort。
2. **Lite/Pro/Max tier 由 `data.level` 給** — 不寫死、不假設 limit 數值（只用 percentage）。
3. **5h percentage = 0 模糊性** — 真的 0 vs cache 剛 populate 都會回 0；對齊 `currentValue` 一起看才確認。
4. **Peak window inclusive boundary** — 13:55:00 起算、18:05:59 截止。避免半開區間 race。
5. **TZ 寫死 Asia/Shanghai** — 不繼承本機 TZ。
6. **Single-key vendor** — z.ai 一把 ZAI_API_KEY、cache file 只一個 `vendor-glm-<profile_id>.json`，skip multi-account 邏輯（不像 `/workflow-monitor` glob 多個 quota-*.json）。
7. **Weekly second-ceiling 是 resume cap** — 5h 漂亮但 weekly ≥ 95% 仍 block resume（不然 resume 後一秒 429）。
8. **Peak guard 跟 token rule 用 OR pause / AND resume 不對稱** — pause 任一條成立即 fire、resume 必須三條都成立。Peak 期間 5h 漲到 60-85% 中間時、peak 結束後仍要等 5h ≤ 60% 才 resume（統一 hysteresis 設計選擇、保守）。

## Open questions / future iteration

- 85% threshold 是試水溫值；trial 一週後看實際撞牆距離調整（目標 hysteresis buffer 夠安全但不過早 pause）。Trial entry 應加進 `~/Desktop/projects/.claude/trials/active.md`。
- 5min peak buffer 是猜值；若 peak 14:00:00 那一秒 z.ai 立刻切倍率、5min buffer 太寬可調 1min；若 z.ai 倍率切換有延遲、buffer 可縮短。需要 peak entry 期間的 token burn rate 觀察才能定。
- Cross-session fallback / inject-and-resume helper 共用 `/workflow-monitor` 那條，未測 ccp-glm session 的兼容性（理論上 Workflow tool 機制跟 vendor 無關、但需第一次跑 trial 驗證）。

## Cross-references

- `/workflow-monitor` (`~/.claude/commands/workflow-monitor.md`) — 共通 mechanic source-of-truth、踩坑共用
- `/bruce-workflow-monitor` (`~/.claude/commands/bruce-workflow-monitor.md`) — lean fork pattern 範本
- Hook (`~/.claude/hooks/workflow-monitor-nudge.sh`) — PostToolUse(Workflow) vendor routing
- Memory `reference_z_ai_glm_widget_integration_2026_06_19` — z.ai monitor endpoint schema + cc-quota-fetcher integration 踩坑
- Memory `project_glm_lite_trial_2026_06_19` — GLM Lite-Monthly 試玩 plan 上下文
- `shell/ccp-functions.sh` `ccp-glm()` — vendor wrapper、export CC_VENDOR=glm
