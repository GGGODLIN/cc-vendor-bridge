## Problem Statement

`ccp-gpt` 在啟動 Claude Code 前會用幾行 terminal 訊息指出目前服務中的 Codex 帳號、健康備援與故障來源；`ccp-free` 與 `ccp-mix-gpt` 雖然已共用 `free(max)` routing chain，成功啟動時卻沒有對等的免費池摘要。使用者因此看不到 GLM 帳號池、DeepSeek fallback、停用 route 或最近健康狀態，必須等請求失敗後再翻 config 與 log。

## Solution

在 `ccp-free` 與 `ccp-mix-gpt` 啟動 Claude Code 前，呼叫一個共用的免費池 status 診斷。診斷沿用 `ccp-gpt-whoami` 的短行、彩色、stderr 呈現：正常時只顯示服務中／預計使用與備援狀態；偵測到 cooldown、daily limit、upstream failure 或查詢失敗時才展開警告、原因與排查命令。診斷只讀現有 local runtime/config/log evidence，不送 inference request、不消耗免費 quota，也不輸出 secret、prompt 或 completion。

## User Stories

1. As the user, I want the whole free pool summarized before Claude Code starts, so that I can see what will serve the session without opening config or logs. [user: "好，我想針對整個免費池做類似的提示，你能理解我的意思嗎"]
2. As the user, I want the summary to look like the existing `ccp-gpt` startup lines, so that vendor wrappers use one familiar terminal language. [user: "你知道我現在打ccp-gpt會先出現幾行資訊嗎？我想要看類似的"]
3. As the user, I want `ccp-free` to identify the active `free(max)` chain, so that the wrapper no longer appears to be a single-model GLM route. [evidence: commit `142e663` pins all `ccp-free` model slots to `free(max)`]
4. As the user, I want `ccp-mix-gpt` to identify both its GPT main model and its free non-main chain, so that the mixed routing is visible at launch. [evidence: `ccp-mix-gpt` maps main/Fable to GPT-5.6 Sol and other slots/subagents to `free(max)`]
5. As the user, I want the normal output to stay within a few useful lines, so that every launch does not become a dashboard dump. [user: "你知道我現在打ccp-gpt會先出現幾行資訊嗎？我想要看類似的"]
6. As the user, I want recent successful traffic labeled as `服務中`, so that observed behavior is distinguished from configured intent. [inferred]
7. As the user, I want a no-recent-traffic route labeled as `預計使用`, so that unknown health is not presented as proven healthy. [user: "看起來可以"]
8. As the user, I want the GLM account pool shown before DeepSeek, so that the displayed order matches the current free-chain contract. [user: "看起來可以"]
9. As the user, I want DeepSeek described as fallback only when the GLM pool is unavailable, so that the message does not imply round-robin or equal priority. [user: "看起來可以"]
10. As the user, I want a configured but disabled FreeLLMAPI route labeled as disabled rather than healthy fallback, so that inactive infrastructure is not overstated. [user: "看起來可以"]
11. As the user, I want partial GLM cooldown or daily-limit conditions highlighted, so that a degraded account pool is visible before the session sends work. [user: "看起來可以"]
12. As the user, I want failure output to include a short diagnostic command and log path, so that the next action is visible in the same terminal. [user: "看起來可以"]
13. As the user, I want status collection to avoid inference calls, so that checking the free pool does not consume quota or alter session affinity. [inferred]
14. As the user, I want launch to continue when status collection is unavailable, so that an optional diagnostic cannot make a usable wrapper fail. [inferred]
15. As the user, I want no API key, auth token, prompt, completion, or raw response body printed, so that startup diagnostics preserve the existing secret boundary. [evidence: existing wrapper and relay diagnostics avoid secret values]
16. As the user, I want `ccp-free` and `ccp-mix-gpt` to share the same status logic, so that labels and health rules cannot drift. [inferred]
17. As the user, I want the output to use the existing green／yellow／red meanings, so that service, uncertainty, and failure remain visually consistent with `ccp-gpt-whoami`. [user: "看起來可以"]
18. As the user, I want the status lines emitted before Claude Code takes over the terminal, so that they remain readable during startup. [evidence: existing `ccp-gpt` calls `ccp-gpt-whoami` before invoking Claude Code]

## Implementation Decisions

- Add one shared free-pool status function and call it from both `ccp-free` and `ccp-mix-gpt`; do not duplicate the classification logic inside each wrapper. [inferred]
- The public behavior under test is each wrapper's stderr before the Claude binary is invoked. [user: "看起來可以"]
- Pass the caller identity into the shared diagnostic so lines use `[ccp-free]` or `[ccp-mix-gpt]` rather than a misleading fixed prefix. [inferred]
- `ccp-mix-gpt` prints its GPT main route separately, then prints the shared free-pool status for non-main slots. [user: "看起來可以"]
- Emit status only after the relay is reachable and the keys file has supplied the required management/client variables, but before invoking Claude Code. [inferred]
- Read only non-mutating local evidence already available from CLIProxyAPI, cline2api, enabled/disabled route config, and recent local logs or management state. [inferred]
- Do not send `/messages`, `/chat/completions`, or any other inference probe during normal startup. [inferred]
- Use observed recent success for `服務中`; use configured route order plus no recent evidence for `預計使用`; use explicit disabled state for `已停用`. [inferred]
- Present the GLM account pool as the primary free source and DeepSeek as whole-pool fallback when that is the live route contract. [evidence: current `free(max)` contract and user-approved terminal draft]
- Do not list FreeLLMAPI as a usable fallback while its route is disabled; a configured disabled entry may be shown as a neutral informational line. [user: "看起來可以"]
- Healthy output should normally fit in two or three lines; warning detail is conditional and may add indented recovery lines. [user: "看起來可以"]
- Reuse `ccp-gpt-whoami` color semantics: green for observed service, yellow for predicted／idle／degraded state, red for confirmed failure. [user: "看起來可以"]
- A status-query error prints one yellow diagnostic line and returns success to the wrapper; it must not block Claude Code launch. [inferred]
- Redact or omit any field that could contain a key, bearer token, prompt, completion, raw body, or unmasked account identifier not already permitted by the existing terminal contract. [evidence: existing secret-safe wrapper convention]
- Keep routing, priority, provider enablement, session affinity, cooldown behavior, and model mappings unchanged. [evidence: user request is a startup hint, not a routing redesign]
- Preserve caller arguments and all current model/context environment behavior in both wrappers. [evidence: existing wrapper contract tests]

## Testing Decisions

- Test at the highest stable seam: invoke `ccp-free` and `ccp-mix-gpt`, capture stderr before a fake Claude binary runs, and assert user-visible lines rather than private helper internals.
- Extend the existing wrapper fixture style instead of introducing a real relay dependency into the contract suite.
- Fixture data should cover: recent GLM success, no recent traffic, partial GLM cooldown, whole GLM pool unavailable with DeepSeek fallback, disabled FreeLLMAPI, management/config query failure, and no usable free source.
- Verify that the diagnostic failure path still invokes the fake Claude binary and returns the wrapper's normal result.
- Verify that healthy output stays concise and does not print warning-only recovery lines.
- Verify caller-specific prefixes and the extra GPT-main line for `ccp-mix-gpt`.
- Verify output contains no fixture key/token values, prompt text, completion text, or raw JSON body.
- Preserve existing env/model assertions for `free(max)`, context windows, WebSearch disabling, argument passthrough, relay kickstart, and timeout behavior.
- After fixture tests pass, run a read-only live smoke with the Claude binary replaced by a no-op command; confirm real local state produces a summary without consuming inference quota.
- Any live smoke result proves only the observed moment; it does not establish provider reliability or long-term quota availability.

## Out of Scope

- Changing the `free`／`free(max)` model mapping or provider priority.
- Enabling, starting, stopping, or reconfiguring FreeLLMAPI.
- Repairing cline2api model selection, quota handling, cooldown recovery, or provider credentials.
- Sending startup inference probes to determine health.
- Building a persistent monitor, status dashboard, notification daemon, or historical metrics store.
- Guaranteeing that a configured provider will remain available after Claude Code starts.
- Printing raw provider responses, request payloads, keys, tokens, prompts, or completions.
- Adding the free-pool summary to unrelated vendor wrappers.

## Further Notes

- The accepted terminal direction is intentionally closer to `ccp-gpt-whoami` than to a dashboard: short status lines first, details only on failure.
- The current wrapper behavior was independently observed through `ccp-free --print`; this spec does not reopen routing correctness.
- `服務中` is an evidence claim and must not be emitted solely because a config entry exists. When recent success cannot be established, use `預計使用` or a neutral state.
- Runtime confirmation（2026-08-29）：structured cline2api account／request-log data can produce the summary without inference. The observed live snapshot was GLM `6/13` available、DeepSeek `3/6` available、FreeLLMAPI route disabled；這只代表 smoke 當下，不是長期可用性承諾。
- Runtime correction：status data 不需從 unstructured service logs 推測；現有 owner-only `.cline-accounts.json` 與 `.cline-request-logs.json` 已提供 account cooldown、model stats 與 completed request evidence。
