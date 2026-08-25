## Problem Statement

使用者已有 `ccp-gpt` 與 `ccp-relay`，但兩者服務訂閱或既有中繼站路線。使用者希望另外取得一個只承載免費模型來源的 `ccp-free` 入口，不把不穩定的免費池混進主要路線，也不再自行承擔每一家免費 provider 的整合維護。

Free Claude Code 已提供免費 provider 的 catalog、Anthropic-compatible endpoint、model routing 與相容性維護，但其預設 installer、設定目錄、網路綁定與 Claude launcher 可能影響既有環境。因此導入時必須隔離安裝、設定、port、credential 與 process，並以真實請求驗證 NVIDIA NIM key 和至少一個模型可用。

## Solution

建立獨立的 `ccp-free` 路線：以隔離安裝的 Free Claude Code server 作為免費來源轉接站，由 `ccp-free` wrapper 把既有 Claude Code session 指向該端點。

Free Claude Code 使用獨立 runtime home、設定、auth token、port 與按需啟動的 launchd job；它不會隨開機常駐，也不會在失敗後自動重啟。初始 provider 只接 NVIDIA NIM，安全複用現有 CLIProxyAPI 裡的 NVIDIA NIM key，但不輸出、不 commit，也不讀取或搬移其他 provider credential。完成安裝後必須以 `/v1/models` 與真實 prompt 驗證可用性；驗證失敗時保持既有 `ccp-gpt`、`ccp-relay` 與 CLIProxyAPI 完全不變。

## User Stories

1. As a 使用者, I want a `ccp-free` command, so that I can deliberately enter a free-model route without changing how `ccp-gpt` or `ccp-relay` works. [user: "可以，就走這個ccp-free的路線"]
2. As a 使用者, I want `ccp-free` to use Free Claude Code as its endpoint, so that provider integration maintenance is mostly handled upstream instead of being maintained manually in CLIProxyAPI. [user: "所以FCC對我來說最高的作用應該是有持續維護？"]
3. As a 使用者, I want this route to contain only explicitly free sources, so that a request cannot silently consume my paid or subscription-backed routes. [user: "如果我的需求明確要搞一個免費token的端點"]
4. As a 使用者, I want the existing NVIDIA NIM key reused without exposing it, so that I can validate the route without creating another credential first. [user: "a，當然要驗證可用性"]
5. As a 使用者, I want a real NVIDIA request to succeed before the route is called usable, so that a provider merely remaining in config is not mistaken for a live source. [user: "a，當然要驗證可用性"]
6. As a 使用者, I want the Free Claude Code runtime isolated from my current CLIProxyAPI runtime, so that trial installation, restart, config changes, or removal cannot interrupt existing model routes. [inferred]
7. As a 使用者, I want `ccp-free` to preserve my normal Claude Code config, skills, hooks, agents, sessions, and credentials, so that the free route changes only the model endpoint for that process. [inferred]
8. As a 使用者, I want the server bound only to loopback and protected by a private bearer token, so that other devices on the network cannot consume my provider quota. [evidence: FCC settings.py defaults inspected on 2026-08-23]
9. As a 使用者, I want `ccp-free` to start or recover its own server when needed, so that using the command does not require a separate manual startup ritual. [evidence: existing ccp-relay health-check and launchd convention]
10. As a 使用者, I want startup failure to produce a direct diagnostic and stop before launching Claude Code, so that the command never silently falls back to Anthropic or another existing endpoint. [inferred]
11. As a 使用者, I want the initial installation pinned to an exact upstream commit, so that the safe-trial result is reproducible and cannot change when upstream `main` moves. [evidence: FCC installer main.zip behavior inspected on 2026-08-23]
12. As a 使用者, I want a complete restore path, so that I can remove the trial and return global config and services to the before snapshot. [evidence: safe-trial workflow requirement]
13. As a 使用者, I want the trial evidence to record the provider, model, date, and live-verification result, so that stale inventory is not presented as healthy capacity. [inferred]
14. As a 使用者, I want existing cc-vendor-bridge tests to remain green, so that adding the route does not regress model mapping or credential-priority behavior elsewhere. [evidence: existing zsh wrapper tests]

## Implementation Decisions

- Free Claude Code SHALL be installed into an independent setup project and virtual environment rather than the global uv tool directory. [inferred]
- The trial SHALL pin the exact Free Claude Code commit selected at trial start; it SHALL NOT install mutable `main.zip`. [evidence: FCC installer main.zip behavior inspected on 2026-08-23]
- The upstream all-in-one installer SHALL NOT be used because it can install or verify unrelated coding agents and create desktop integration. Only the Free Claude Code package and server dependencies SHALL be installed. [evidence: FCC install.sh inspected on 2026-08-23]
- The FCC server SHALL run with a dedicated runtime home so its `.fcc` config, auth state, logs, and generated artifacts cannot overlap the normal user home or CLIProxyAPI runtime. [inferred]
- The service SHALL bind to `127.0.0.1` on a dedicated port and SHALL enable proxy authentication with a generated private token. [evidence: FCC network and auth defaults inspected on 2026-08-23]
- A dedicated on-demand launchd job SHALL own the FCC server process, following the existing `ccp-relay` process-management convention while using a distinct label, runtime home, port, logs, and executable. Its launcher and working directory SHALL live under the dedicated runtime data path rather than Desktop/project paths, because macOS launchd TCC blocks the latter. It SHALL set neither `RunAtLoad` nor `KeepAlive`; only `ccp-free` starts it. [evidence: existing ccp-relay convention + 2026-08-23 exit-126 Desktop-path probe and corrected runtime-path `/health` 200]
- The single provisioning flow SHALL install a source-identical dedicated plist and bootstrap the job after the runtime launcher exists; an unknown existing target SHALL fail without overwrite, and a repeat run SHALL safely re-register the same dedicated label. [evidence: 2026-08-23 final code review + fresh-registration regression]
- The `ccp-free` wrapper SHALL health-check the dedicated port, kickstart only the dedicated on-demand FCC job when unavailable, wait for readiness with a fixed upper bound, and abort with a diagnostic if readiness fails. Before reading or forwarding the bearer token, it SHALL verify that the dedicated launchd job is running and that its PID owns the port-18082 listener; an unrelated localhost listener SHALL fail closed. [evidence: existing ccp-relay seam + 2026-08-23 real port-squatting negative control]
- The wrapper SHALL invoke the normal installed `claude` binary with process-local endpoint and auth environment variables. It SHALL NOT invoke `fcc-claude`, because that launcher removes existing `ANTHROPIC_*` values, fixes the compaction window, and disables several Claude Code behaviors. [evidence: FCC claude_env.py inspected on 2026-08-23]
- The wrapper SHALL mark the session as the free route and launch Claude Code with the exact NVIDIA model ID that passed the live probe. Dynamic gateway model discovery is deferred until a second provider or interactive model selection is requested. Context, effort, tool, hook, agent, and skill behavior SHALL remain unchanged unless a live compatibility test proves an override is required. [inferred]
- Initial provider configuration SHALL contain NVIDIA NIM only. It SHALL require the exact approved `provider_model_ref` returned by the provider catalog and prove that same entry with a live prompt; another available `nvidia_nim/*` model cannot satisfy the Gate. [user: "a，當然要驗證可用性"]
- The existing NVIDIA NIM key SHALL be read from the current CLIProxyAPI credential source and copied directly into the isolated FCC config without printing it. No other credential SHALL be copied. [user: "a，當然要驗證可用性"]
- Secret-bearing runtime files SHALL use user-only permissions and SHALL remain outside every git repository. [inferred]
- `ccp-free` SHALL NOT include CLIProxyAPI, Codex OAuth, Antigravity, Anthropic subscription, or any paid provider as a fallback. [user: "如果我的需求明確要搞一個免費token的端點"]
- Provider inventory and provider health SHALL be represented separately: configuration proves only that a route exists; a dated live probe proves that it worked. [user: "沒有的話，我現在要自己去驗證我串的NVIDIA有沒有活著對嗎"]
- Installation and first execution SHALL run inside safe-trial snapshots, with a seven-day review entry and a dry-run restore script. [evidence: safe-trial workflow requirement]
- The implementation SHALL stop after the isolated NVIDIA-backed route passes acceptance tests; adding more providers belongs to later iterations. [inferred]

## Testing Decisions

- The highest behavioral seam is `ccp-free` as observed by a caller: invoking it must start the isolated endpoint when necessary and launch Claude Code with the expected process-local endpoint, auth, free-route marker, and exact live-verified model.
- One focused wrapper test will replace `claude`, port checks, and launchd calls with controlled fakes. It will assert the launched command, bounded readiness behavior, environment, and fail-closed path without contacting real services.
- One server smoke test will verify loopback binding, authenticated `/v1/models`, rejection without the bearer token, and isolation from the CLIProxyAPI port.
- One provider acceptance test will obtain the FCC model catalog, choose the configured NVIDIA model, send a minimal real prompt, and require a non-empty successful response. A catalog-only result is insufficient.
- Secret verification will assert that no tracked file or test output contains the copied NVIDIA key or generated proxy token, and that runtime credential files have user-only permissions.
- Safe-trial verification remains mandatory: record the Stage 0 Docker result, compare before and after snapshots, confirm restore coverage, add the seven-day review entry, and run the restore script in dry-run mode.
- Regression testing will run the existing cc-vendor-bridge tests plus the focused `ccp-free` test. Git diff and targeted grep will confirm the change is additive and does not alter existing `ccp-gpt` or `ccp-relay` definitions.

## Out of Scope

- Replacing CLIProxyAPI, `ccp-gpt`, `ccp-relay`, or any existing provider route.
- Importing Codex, Antigravity, Anthropic, Gemini, OpenRouter, or other paid/subscription credentials into FCC.
- Building cost-aware or quota-aware dynamic routing.
- Adding multiple free providers in the first iteration.
- Enabling FCC Discord, Telegram, voice, desktop tray, Codex, Pi, OpenCode, Cline, Hermes, DeepSeek Harness, Grok Build, or Muse Code integrations.
- Publishing the endpoint outside localhost.
- Treating FCC README token totals as guaranteed capacity.
- Automatically promoting the trial into permanent infrastructure before the seven-day review.

## Further Notes

The initial route proves only that Free Claude Code can safely coexist with the current stack and that the reused NVIDIA credential can complete a real request. It does not prove that NVIDIA remains permanently free or reliable, nor does v1 attempt to quantify long-term maintenance savings. The provider, model, date, and result belong in the safe-trial evidence; no separate ongoing health ledger is introduced.

The user explicitly selected option `a`, whose stated meaning was to read the existing CLIProxyAPI NVIDIA NIM key and copy it into isolated FCC configuration. This is a confirmed trust-boundary decision rather than an inferred implementation convenience. The implementation must not inherit any other CLIProxyAPI credential, port, model mapping, or management behavior.

The on-demand launchd job is the minimal process manager for v1: it avoids an unmanaged orphan process but does not run at boot or restart itself. A persistent `RunAtLoad` or `KeepAlive` service remains out of scope.

2026-08-23 confirmation：`ccp-free` completed two real wrapper-triggered cold starts through `nvidia_nim/nvidia/nemotron-3-super-120b-a12b`; both prompts returned non-empty marker matches. A dedicated-label SIGKILL did not increase launchd runs during the three-second observation window, and only the next wrapper call restarted the server. Final state is registered/not-running with port 18082 free; CLIProxyAPI PID/service/port remained unchanged. The restore path remains dry-run-only and names only the dedicated job, runtime, plist, wrapper commit, and setup commits.

The FCC source archive is commit- and SHA-pinned, but runtime dependencies are range-resolved rather than hash-locked and an existing source/venv may be reused. Independent security calibration classified this as a future reinstall provenance limitation, not a reason to invalidate the dated live Gate.

Final review corrections were revalidated on 2026-08-23：a fresh-registration helper made the documented one-command provisioning flow sufficient to register the on-demand job; catalog validation rejected alternate NVIDIA entries unless the exact approved model was present; and a real localhost port-squatting control caused `ccp-free` to exit before invoking Claude, with the temporary listener receiving zero bytes. The final real prompt still returned through the approved NVIDIA route, and the job ended registered/not-running with port 18082 free.

## 2026-08-23 Ox Alpha Route Amendment

The user later changed the active trial goal from the direct NVIDIA model to trying OpenRouter's exact `stealth/ox-alpha`. This amendment supersedes the NVIDIA-only active-route decisions above without rewriting their historical Gate evidence.

- `ccp-free` SHALL route every Claude Code model slot and subagent to `open_router/stealth/ox-alpha`; it SHALL NOT use `openrouter/free`, another OpenRouter model, NVIDIA, or any fallback.
- The FCC runtime SHALL contain only `OPENROUTER_API_KEY` as its provider credential. First provisioning reads it from the process environment; later idempotent provisioning may reuse it from the private FCC `.env`. Setup children and the server launcher SHALL not inherit unrelated credentials.
- The dedicated OpenRouter key is named `ccp-free-ox`, expires on 2026-08-30 at 21:00 GMT+8, and has a US$0.01 key limit. The account showed US$0.00 available credits when the key was created.
- A direct OpenRouter Gate cataloged `stealth/ox-alpha`; a prompt returned HTTP 200 with non-empty content, and a forced function call returned `get_trial_marker` with `OX_TOOL_OK`.
- Provisioning completed with authenticated exact-model catalog HTTP 200, real FCC prompt HTTP 200, and unauthenticated HTTP 401. A wrapper-triggered cold start returned `OX_CCP_FREE_OK`; a real Claude Code `Read` tool call returned `OX_TOOL_FROM_READ_OK`.
- Final state is registered/not-running with port 18082 free; CLIProxyAPI remains PID 2415 on port 8317. Runtime secret files use mode 600, contain no NVIDIA entry or `MODEL_FALLBACKS`, and a 171-file scoped repo/log exact-secret scan found zero illegal hits.
- Context metadata：OpenRouter reports `context_length=1048576`, while FCC's model catalog does not expose a context field and Claude Code therefore assumes 200K for the unrecognized provider-prefixed ID. `ccp-free` SHALL force `CLAUDE_CODE_MAX_CONTEXT_TOKENS=1048576`, request the supported `CLAUDE_CODE_AUTO_COMPACT_WINDOW=1000000`, and clear inherited `DISABLE_COMPACT`; Claude Code 2.1.241 behavior evidence SHALL show `effectiveWindow=980000` before this route is treated as 1M-configured.
- Known limitations：Claude Code prints a non-fatal `unrecognized_model` diagnostic for the provider-prefixed ID; Ox Alpha is a zero-priced anonymous preview rather than a `:free` policy variant; the provider retains prompts/completions; the key expires after seven days; and FCC's authenticated direct-model routing plus loopback Admin API are existing LOW trust-boundary limitations rather than a hard exact-model allowlist.
