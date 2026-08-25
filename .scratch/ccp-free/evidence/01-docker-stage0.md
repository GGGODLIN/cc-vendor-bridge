# Ticket 01：Docker Stage 0 證據

- 執行時間：2026-08-23 08:12:14 UTC
- Gate：`PASS`
- Stage 0 結論：准許進入 Ticket 02，但 Ticket 02 必須維持 loopback、啟用 proxy auth，並處理 startup 的 tokenizer data fetch。
- 實際執行位置：Linux Docker container；沒有安裝到 macOS，也沒有讀取 home config、launchd、Keychain 或任何 credential。

## 固定來源與映像

- Upstream repository：[Alishahryar1/free-claude-code](https://github.com/Alishahryar1/free-claude-code)
- Exact commit：[f405a929f7c14b168554528c54ffec46bf303faf](https://github.com/Alishahryar1/free-claude-code/commit/f405a929f7c14b168554528c54ffec46bf303faf)
- Source archive：[immutable commit archive](https://github.com/Alishahryar1/free-claude-code/archive/f405a929f7c14b168554528c54ffec46bf303faf.tar.gz)
- Archive SHA-256：`58a7849fc85af95d17e59a2e2a4cc1ef74e8d03debd639d3abb3e8491a53f13b`
- Docker image：`python:3.14-slim@sha256:ce40764625a4ff50df3548277632e7f96c4e77fe75fa848aae9885476e7df5a4`
- `git ls-remote` 對 exact hash 回傳 `HEAD` 與 `refs/heads/main`；執行時使用 hash archive，不是 mutable branch URL。

## 第一輪：停用網路

### Container 與安裝命令

Container 使用以下隔離條件：

- `--rm`
- `--network none`
- `--read-only`
- `--cap-drop=ALL`
- `--security-opt=no-new-privileges`
- source 以 read-only bind mount 掛到 `/work`
- `/tmp` 是 container-only tmpfs
- `HOME=/tmp/fcc-home`
- 沒有 mount host home、credential、SSH、Keychain 或 repo 可寫目錄

核心命令：

```text
docker run --rm --network none --read-only --cap-drop=ALL --security-opt=no-new-privileges --mount type=bind,src=<pinned-source-tree>,dst=/work,readonly -w /work -e HOME=/tmp/fcc-home -e PIP_CACHE_DIR=/tmp/pip-cache -e PIP_NO_INPUT=1 -e FCC_OPEN_BROWSER=false -e MESSAGING_PLATFORM=none -e VOICE_NOTE_ENABLED=false -e HOST=127.0.0.1 -e PORT=8082 python:3.14-slim sh -lc 'python -m pip install --target /tmp/fcc-install --no-deps --no-input --no-cache-dir .'
```

### 結果

- Python：`3.14.7`
- pip：`26.2.1`
- package install exit code：`1`
- 失敗點：Hatchling build dependency `hatchling` 需要從 `pypi.org` 取得；DNS 在 `--network none` 下失敗。
- 觀察到的錯誤是 `Temporary failure in name resolution`，接著 `Could not find a version that satisfies the requirement hatchling`。
- 這是預期的合法 build dependency fetch failure；沒有進入 package wheel 安裝或 runtime 啟動。
- `HOME_FOOTPRINT` 為空；`/tmp` 沒有留下 package 安裝檔；`/work` 只有 read-only source tree。第一輪沒有看到 install 後外連、host 寫入、credential 存取、persistence 或其他可疑行為。

## 第二輪：連網安裝與 server smoke

第一輪只因 build dependency 下載失敗，所以使用全新的 `--rm` container。這一輪沒有執行 upstream installer，也沒有使用 `scripts/install.sh`。

### 安裝策略

先以 `--no-deps` 安裝 pinned source 的 `free-claude-code` wheel，再只安裝 server runtime 需要的 direct dependencies：

```text
fastapi>=0.141.1
uvicorn>=0.52.1
httpx[socks]>=0.28.1
httpx2[socks]>=2.7.0,<3
markdown-it-py>=4.2.0
pydantic>=2.13.4
python-dotenv>=1.2.2
tiktoken>=0.13.0
openai>=3.2.0
loguru>=0.7.0
aiohttp>=3.14.3
jsonschema>=4.25.0
google-auth[requests]>=2.56.3
requests[socks]>=2.34.2
```

`python-telegram-bot`、`discord.py`、`pystray`、`Pillow` 與 `voice`／`voice_local` extras 沒有安裝。Container 內以 `/opt/fcc-install` exec-only tmpfs 放 native wheels；`/tmp` 維持 `noexec`。這個 mount 調整只修正測試 container 的 native `.so` 載入條件，不是修改 upstream code。

### 安裝結果

- core package build/install exit code：`0`
- 建出的 wheel：`free_claude_code-5.13.10-py3-none-any.whl`
- wheel size：`601709` bytes
- wheel SHA-256：`02b99e345fb89fc3b913b4a36e41bd26c687351e271308b07f5500a09763436c`
- selected runtime dependencies exit code：`0`
- import probe：`free_claude_code`, `fastapi`, `uvicorn`, `httpx`, `httpx2` 全部 import 成功，exit code `0`
- excluded distribution checks：
  - `python-telegram-bot=NOT_INSTALLED`
  - `discord.py=NOT_INSTALLED`
  - `pystray=NOT_INSTALLED`
  - `Pillow=NOT_INSTALLED`

### Server startup smoke

Container startup environment 明確設定：

- `HOST=127.0.0.1`
- `PORT=8082`
- `FCC_OPEN_BROWSER=false`
- `MESSAGING_PLATFORM=none`
- `VOICE_NOTE_ENABLED=false`
- 沒有設定任何 provider key，也沒有注入 `ANTHROPIC_AUTH_TOKEN` 或其他 credential
- 沒有送出任何模型 prompt

執行 `/opt/fcc-install/bin/fcc-server` 後，以 Python `urllib` 對 loopback endpoint 發出唯一 probe：

```text
GET http://127.0.0.1:8082/health
```

實際結果：

```text
LOOPBACK_PROBE_EXIT=0
HTTP 200
{"status":"healthy"}
```

Server log 顯示 process 啟動、application startup complete、loopback `/health` 回應 200，接著收到測試 harness 的 SIGTERM 並完成 graceful shutdown。`SERVER_EXIT_AFTER_TERM=143` 是受控的 SIGTERM 結果，不是 startup crash。

Server log 另出現 Python `resource_tracker` 關於 8 個 semaphore objects 的 shutdown warning。這些 objects 位於 disposable container，container 隨 `--rm` 丟棄；沒有 host persistence。這列為 Minor runtime observation，不構成 Stage 0 fail 條件。

## 寫入 footprint 與外連觀察

### Container-only writes

由於 root filesystem 與 `/work` 都是 read-only，只有 `/tmp` 與 `/opt/fcc-install` tmpfs 可寫。成功 smoke 後觀察到的主要路徑如下：

```text
/tmp/fcc-home/.fcc/.env                         mode 600  92 bytes
/tmp/fcc-home/.fcc/config.lock                  mode 644   0 bytes
/tmp/fcc-home/.fcc/logs/server.log              mode 644 1179 bytes
/tmp/fcc-home/.fcc/codex-model-catalog.json     mode 644 1926 bytes
/tmp/pip-cache/                                  dependency cache
/tmp/data-gym-cache/<opaque-file>               1681126 bytes
/opt/fcc-install/                                selected package/runtime install
```

所有路徑都在 disposable container 的 tmpfs；沒有工作目錄外的 host write。沒有看到 `.ssh`、Keychain、launchd、global Claude config 或既有 repo runtime 的存取。

### Startup 的公開 tokenizer data fetch

Server startup 會載入 upstream 的 `core/token_estimation.py`；該檔案在 import 時呼叫 `tiktoken.get_encoding("cl100k_base")`。本次 smoke 在 `/tmp/data-gym-cache` 產生一個約 1.68 MB cache file。用同一輪安裝的 `tiktoken==0.14.0` wheel 靜態檢查確認：

- cache 位置會使用 `/tmp/data-gym-cache`
- `cl100k_base` 的公開 encoding URL 是 `https://openaipublic.blob.core.windows.net/encodings/cl100k_base.tiktoken`

因此本次有一個安裝後、非 provider、非 credential 的公開 tokenizer data fetch。它看起來是 tiktoken 的正常 lazy cache 行為，不是 FCC 自行隱藏 persistence，也沒有使用 provider key；但它不是純 pip package download。Ticket 02 若要求 startup 完全禁止外連，必須先預熱這個 cache 或在 network-denied 條件下另做 smoke，不能假設 server startup 零外連。

### FCC 預設值的安全 caveat

Pinned source 的設定 schema 顯示 FCC 預設 `HOST` 是 all-interface、proxy auth 預設關閉。這次 smoke 明確覆寫成 `127.0.0.1`，所以本次 container probe 只驗 loopback。Ticket 02 不得沿用 upstream defaults；必須在隔離 runtime 中設定 loopback 與 private bearer token，並另外驗證未帶 token 的請求會被拒絕。

## Upstream installer 與 extras 排除

- 沒有執行 upstream `scripts/install.sh`。
- 沒有使用 README 的 mutable `main` installer 或 `main.zip`。
- `scripts/install.sh` 會處理多個外部 coding agents、桌面整合與 RTK；本票只 build/install pinned `free-claude-code` wheel 與上述 server dependencies。
- `pyproject.toml` 雖宣告 messaging dependencies、GUI entrypoint、9 個 launcher entrypoints 與 optional voice extras，但本輪沒有安裝其外部 agent distributions、messaging distributions、desktop distributions 或 voice extras。
- 沒有安裝 Claude Code、Codex、Pi、OpenCode、Cline、Hermes、DeepSeek Harness、Grok Build、Muse Code 等無關 agent binary。

## Gate decision

**PASS。** 理由：

1. exact upstream commit 已取得並以 immutable archive 驗證。
2. 第一輪在 network-none container 只因合法 Hatchling dependency fetch 失敗，沒有看到可疑 install-time 行為。
3. 第二輪全新 container 成功 build/install core package，selected server dependencies 安裝成功。
4. `fcc-server` process 成功啟動，loopback `/health` 回應 HTTP 200，沒有 provider key，也沒有送出 prompt。
5. 沒有使用 upstream all-in-one installer，也沒有安裝 messaging、voice、desktop 或外部 coding-agent extras。
6. 寫入只落在 disposable container 的 tmpfs；沒有 host config、credential、launchd 或既有工作目錄寫入。

**Ticket 02 blocker 可解除，但必須帶入本檔 caveat：** startup tokenizer cache 的公開外連，以及 FCC defaults 的 all-interface／auth-off，不得直接帶到真機 safe-trial。