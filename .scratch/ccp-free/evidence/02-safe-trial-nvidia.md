# Ticket 02：safe-trial NVIDIA Gate 證據

- 執行日期：2026-08-23
- Gate：`PASS`
- Trial：`ccp-free-fcc-v3`
- safe-trial 修正 commit：`890765a`（排除 `.codex` AF_UNIX IPC runtime，snapshot error fail-closed）
- FCC pinned commit：`f405a929f7c14b168554528c54ffec46bf303faf`
- FCC archive SHA-256：`58a7849fc85af95d17e59a2e2a4cc1ef74e8d03debd639d3abb3e8491a53f13b`

## TDD RED

Seam 是 FCC 對 localhost 暴露的 authenticated HTTP endpoint。測試只透過 HTTP public interface，不讀 private Python internals。

Command：

```text
FCC_BASE_URL=http://127.0.0.1:18082 FCC_PROXY_TOKEN_FILE=/tmp/ccp-free-red-token python3 /Users/linhancheng/Desktop/projects/fcc-free-setup/tests/test_fcc_endpoint.py
```

實際結果：`RED_EXIT=1`。

非敏感輸出：`urllib.error.URLError: <urlopen error [Errno 61] Connection refused>`。當時 endpoint 尚未存在，測試確實失敗。

## TDD GREEN 與 safe-trial

Command：

```text
cd /Users/linhancheng/Desktop/projects/fcc-free-setup && /Users/linhancheng/.claude/scripts/safe-trial.sh ccp-free-fcc-v3 -- ./bin/provision-and-probe
```

非敏感輸出：

```text
runtime_install=PASS
fcc_commit=f405a929f7c14b168554528c54ffec46bf303faf
provider=nvidia_nim
provider_credential_source=CLIProxyAPI openai-compatibility name=nvidia
provider_credential_copied=NVIDIA_NIM_API_KEY
excluded_python-telegram-bot=NOT_INSTALLED
excluded_discord.py=NOT_INSTALLED
excluded_pystray=NOT_INSTALLED
excluded_Pillow=NOT_INSTALLED
{"assistant_content_non_empty": true, "catalog_status": 200, "model_id": "nvidia_nim/nvidia/nemotron-3-super-120b-a12b", "nvidia_model_cataloged": true, "prompt_status": 200, "unauthenticated_status": 401}
server_ready=true
focused_http_smoke=PASS
server_stopped=true
port_18082_free=true
[safe-trial] cmd exit: 0
```

## HTTP／provider 結果

- 未帶 bearer token：`401`
- 帶 token 取得 `/v1/models?view=messages`：`200`
- catalog NVIDIA model：`nvidia_nim/nvidia/nemotron-3-super-120b-a12b`
- 真實 prompt endpoint：`POST /v1/messages`，`200`
- assistant content：非空
- provider：`nvidia_nim`
- FCC server log 記錄 health、401、catalog 200、prompt 200 與 graceful shutdown；沒有把 response body 寫入 evidence。
- source 只注入 `NVIDIA_NIM_API_KEY`；runtime bearer token 是 FCC private proxy auth，不是 Anthropic credential。

## Runtime paths 與 modes

- config／secret directory：`/Users/linhancheng/.config/ccp-free/`，mode `0700`
- runtime data directory：`/Users/linhancheng/.local/share/ccp-free/`，mode `0700`
- runtime home：`/Users/linhancheng/.local/share/ccp-free/home/`，mode `0700`
- FCC config directory：`/Users/linhancheng/.local/share/ccp-free/home/.fcc/`，mode `0700`
- FCC managed secret config：`/Users/linhancheng/.local/share/ccp-free/home/.fcc/.env`，mode `0600`
- proxy token：`/Users/linhancheng/.config/ccp-free/proxy-token`，mode `0600`
- server log：`/Users/linhancheng/.local/share/ccp-free/logs/server.log`，mode `0600`
- install log：`/Users/linhancheng/.local/share/ccp-free/logs/install.log`，mode `0600`
- metadata：`/Users/linhancheng/.local/share/ccp-free/install-metadata.json`，mode `0600`
- tokenizer cache：`/Users/linhancheng/.local/share/ccp-free/tiktoken-cache/`，mode `0700`，非空
- venv Python：`3.14`
- endpoint：`127.0.0.1:18082`
- runtime env keys：`FCC_CONFIG_SCHEMA`, `HOST`, `PORT`, `FCC_OPEN_BROWSER`, `MESSAGING_PLATFORM`, `VOICE_NOTE_ENABLED`, `PROXY_AUTH_ENABLED`, `ANTHROPIC_AUTH_TOKEN`, `NVIDIA_NIM_API_KEY`, `MODEL`, `LOG_LEVEL`

FCC startup 使用專用 tokenizer cache。Stage 0 已確認公開 URL 類型是 `https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken`；v3 先預熱到上述 git 外 cache，沒有把 tokenizer fetch 誤報成 NVIDIA provider call，也沒有使用 provider key 做 tokenizer fetch。

## Isolation

v3 前後 probe 完全相同：

- CLIProxyAPI PID：`2415`
- CLIProxyAPI command：`/Users/linhancheng/.cli-proxy-api/bin/cli-proxy-api --config /Users/linhancheng/.cli-proxy-api/config.yaml`
- service：`com.philip.cli-proxy-api`
- sibling service：`com.gggodlin.cc-vendor-bridge-proxy`
- existing port：`127.0.0.1:8317`
- v3 port：`18082` 前後皆為 `FREE`
- FCC server：command 結束後 process `STOPPED`
- 沒有建立 launchd job，也沒有修改既有 CLIProxyAPI config、service label、port 或 logs。

## Snapshot／ledger／restore

- before：`/Users/linhancheng/Desktop/projects/.claude/trials/ccp-free-fcc-v3/snapshot/before/`
- after：`/Users/linhancheng/Desktop/projects/.claude/trials/ccp-free-fcc-v3/snapshot/after/`
- before／after 都沒有 `shell_snapshots` directory。
- before／after 都保留 `.codex/config.toml`，證明 snapshot 不是整個 `.codex` 刪除。
- before／after manifest 都包含 `dir ... /Users/linhancheng/.codex`。
- active ledger：`/Users/linhancheng/Desktop/projects/.claude/trials/active.md`
- v3 active H2 數量：`1`
- v3 review date：`2026-08-30`
- restore：`/Users/linhancheng/Desktop/projects/.claude/trials/ccp-free-fcc-v3/restore.sh`
- restore dry-run exit：`0`
- dry-run 涵蓋：`/Users/linhancheng/.config/ccp-free/`、`/Users/linhancheng/.local/share/ccp-free/`
- restore 沒有執行。
- 舊的 `ccp-free-fcc` 與 `ccp-free-fcc-v2` directories 沒有覆寫或刪除。

## Secret scan

掃描範圍包含 setup repo、v3 trial、v3 safe-trial output、v3 restore dry-run output 與 FCC server log；secret env 與 proxy-token source file 排除，不會把 secret source 複製進掃描輸出。

```text
secret_scan_scope_files=15312
nvidia_key_hit_count=0
proxy_token_hit_count=0
secret_sources_excluded=true
```

掃描只輸出 hit count/path，沒有輸出 NVIDIA key 或 proxy token 的值、長度、prefix、suffix 或 hash。

## 未做項目

- 沒有建立 launchd job；屬於 Ticket 03。
- 沒有執行 restore。
- 沒有修改 ticket status、checkbox 或 shared Verification Log。
- 沒有 commit。
- safe-trial Self-Verify 尚未執行，由 controller 另派 auditor。

## Verdict

`PASS`。v3 通過 loopback、private bearer auth、catalog、真實 NVIDIA prompt、secret mode、runtime isolation、snapshot exclusion、config retention、restore dry-run 與 CLIProxyAPI 前後 identity 一致性；Ticket 03 blocker 可由 controller 依本證據解除。
