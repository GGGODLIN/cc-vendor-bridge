# 03 — 建立 `ccp-free` 冷啟動路線

**What to build:** 使用者執行 `ccp-free` 時，命令能按需啟動隔離 FCC server、等待 readiness，然後以正常 Claude Code 環境連上已通過 live probe 的 NVIDIA 模型；任何啟動或驗證失敗都直接停止，不會落到付費來源。

**Blocked by:** 02 — Gate：safe-trial 安裝並驗證 NVIDIA

**Status:** completed

**Needs:** Ticket 02 通過後留下的隔離 FCC runtime、proxy token、live-verified NVIDIA model ID 與 dedicated port。

**TDD:** required

**TDD seam:** 呼叫者觀察到的 `ccp-free` shell function 行為，使用 fake `claude`、port probe 與 launchd command 驗證

- [x] 先寫會失敗的 focused wrapper test，覆蓋 server 已就緒、server 未啟動、啟動逾時與啟動失敗四條路徑。
- [x] 建立專屬 on-demand launchd job；不得設定 `RunAtLoad` 或 `KeepAlive`，不得使用既有 CLIProxyAPI label、port、runtime 或 logs。
- [x] `ccp-free` 在 port 未開時只 kickstart 專屬 FCC job，使用固定上限等待 readiness；逾時或失敗時輸出直接診斷並停止。
- [x] 成功路徑使用正常 `claude` binary，注入 process-local FCC endpoint、auth token、free-route marker 與 live-verified NVIDIA model ID；不得呼叫 `fcc-claude`。
- [x] `ccp-free` 不得設定任何 CLIProxyAPI、Codex、Antigravity、Anthropic subscription 或 paid fallback。
- [x] 把 `ccp-free` 加入既有 command help；除了 additive insertion，不修改 `ccp-gpt` 或 `ccp-relay` 定義。
- [x] focused test 轉綠，並確認既有 cc-vendor-bridge tests 全部維持綠燈。

## Verification Log

- RED：`ccp-free` 尚不存在時，四組 public wrapper seam 路徑皆失敗；真 FCC service 未被碰觸。
- GREEN：focused wrapper test 全數通過；controller 重跑顯示 token preflight、ready、cold-start、timeout、launch failure 與 exact env/model assertions 全綠。
- Bridge regression：`tests/*.zsh` 6/6；`ccp-gpt`／`ccp-relay` function hash與baseline相同。
- launchd：source/target `plutil -lint`皆OK且byte-identical；job registered、`state = not running`、`runs = 0`；port 18082 free。
- Controller補正：`ccp-functions.sh`檔首契約標記已加入`tests/ccp-free-wrapper.test.zsh`，grep命中1處。
- 首輪Ticket04發現真機整合缺陷：launchd執行Desktop-backed `start-server`時遭macOS TCC拒絕，exit126；Ticket03因此reopen。
- 修正：tracked launcher以atomic copy安裝到`~/.local/share/ccp-free/bin/start-server`（dir/file 700），plist ProgramArguments與WorkingDirectory皆移出Desktop；metadata記runtime launcher。
- Regression：真AF artifact test拒絕Desktop path、launcher缺失／mode錯／byte mismatch；actual artifacts PASS。
- 真機GREEN：專屬job kickstart後`GET /health`200；SIGTERM後registered/not-running、18082free，短窗未自動restart；source/actual plist與launcher皆byte-identical。
- Final review修正：cc-vendor`f89e635`新增launchd PID與`lsof` listener owner一致性驗證，port被非專屬job佔用時fail-closed且延後讀token；setup`3881d9c`讓單一provision flow安裝/bootstrap專屬job並把smoke鎖定exact model。
- Regression：port ready但job stopped、PID mismatch、rogue listener皆nonzero且不叫claude；fresh setup fake-home installer、unknown plist保護、idempotent bootstrap與exact-model mutation全PASS。
- Final actual：真prompt時launchd PID等於18082 owner；port-squatting listener收到0 bytes、fakeclaude未執行；fresh registration helper成功，final jobregistered/not-running/free。
- Ticket04已重跑並PASS，完整provider/lifecycle證據見`../evidence/04-confirm-live-route-and-restore.md`。
