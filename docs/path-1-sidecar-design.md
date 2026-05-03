# Path 1 — `claude -p` Headless Reuse

CC stays on Claude as orchestrator; specific sub-tasks are offloaded to other vendor sessions running in `claude -p` (headless mode), reusing the same Path 0 env-var setup.

**Status: 2026-05-03 — design simplified after Stage 2 insight**

## TL;DR

Once a vendor is wired through Path 0 (`ccp-<vendor>` zsh function with all caveat fixes), Path 1 sidecar capability is essentially **free**:

```bash
ccp-<vendor>-rescue() { ccp-<vendor> -p --dangerously-skip-permissions "$@"; }
```

5-line wrapper per vendor. CC's built-in `-p` flag runs the full agent loop (Read / Write / Edit / Bash / MCP / subagent dispatch) non-interactively and prints the final assistant message to stdout. The vendor's anthropic-format endpoint, ToolSearch defer, subagent routing, hook bypass, proxy fix — all inherited.

## When you'd want Path 1 vs Path 0

| Scenario | Path 0 | Path 1 |
|---|---|---|
| Whole exploration session in vendor | ✅ | — |
| Long doc summarization (1M context) | ✅ | — |
| Throwaway cheap test | ✅ | — |
| Main Claude session needs a vendor for ONE task | — | ✅ |
| Second opinion / cross-check | — | ✅ |
| Implementation-heavy sub-task while Claude orchestrates | — | ✅ |

Path 0 swaps the orchestrator entirely; Path 1 keeps Claude orchestrating + ecosystem intact.

## How the architecture clicks

`claude` CLI's `-p` (or `--print`) mode = headless: take prompt as arg/stdin → run full agent loop internally → print final assistant message to stdout → exit. Same model / tools / MCP / CLAUDE.md as interactive mode.

Combined with subshell `ccp-<vendor>` env setup:

```
Main Claude (Opus, interactive)
  └─ Bash tool: ccp-deepseek-rescue "<task>"
       └─ subshell with vendor env vars
            └─ claude -p "<task>"
                 └─ DS V4-Pro agent loop (Read / Write / Edit / Bash / Task / MCP)
                 └─ exit, prints final message
       ← Main Claude reads the printed message and decides next step
```

This is the structural equivalent of `codex-rescue`:

| Pattern | Outer | Inner |
|---|---|---|
| codex-rescue | main Claude → Bash | `codex exec "task"` (OpenAI agent) |
| ccp-deepseek-rescue | main Claude → Bash | `claude -p` with DS env (DS agent) |

## File layout

```
plugin/
└── sidecar.sh    # all wrapper functions (one per Path 0 vendor)
```

That's it. No plugin manifest, no agents/, no commands/, no lib/. The full work is the 5-line wrapper times N vendors.

## Per-vendor: what carries over from Path 0

Once Path 0 is verified for a vendor, Path 1 inherits:

| From Path 0 | Inherited by Path 1? |
|---|---|
| `ANTHROPIC_BASE_URL` env | ✅ |
| `ANTHROPIC_AUTH_TOKEN` | ✅ |
| `*_SUBAGENT_MODEL` (subagent routing) | ✅ verified for DS |
| `ENABLE_TOOL_SEARCH=auto` (caveat 7 fix) | ✅ |
| `CC_VENDOR=<name>` marker (caveat 8 fix — hook bypass) | ✅ |
| Proxy daemon (caveat 9 fix for DS) | ✅ |
| `DISABLE_COMPACT=1` + `MAX_CONTEXT_TOKENS` (caveat 6 fix) | ✅ |
| Vendor caveats 1-5 schema-level pass | ✅ |

Pre-launch health check (proxy daemon kickstart for DS) also runs identically, since `-p` mode is just a flag on the same `claude` invocation.

## Per-vendor: what needs new Path 1 verification

| Check | Done for DS? | Notes |
|---|---|---|
| `claude -p` runs to completion in vendor session | 待 first dispatch test | Should work — same agent loop |
| Subagent dispatch in headless mode | 待測 | Theoretical: same env, should route via SUBAGENT_MODEL |
| Tool permission handling (skip-permissions vs allowedTools) | 設計選 skip-permissions for vibe coding | See safety section |
| Stdout buffering / streaming | 待測 | `-p` defaults to non-streaming text output |

## Safety: `--dangerously-skip-permissions`

Headless mode can't show permission prompts. Two options:

1. **`--dangerously-skip-permissions`** (vibe coding default) — All tool calls run without confirmation. Acceptable when:
   - You wrote the wrapper invocation
   - The task description is your own (not from external prompt injection)
   - You're in your own repos, not production systems
   - The wrapper is called from your own main Claude session, not exposed to untrusted callers

2. **`--allowedTools <list>`** (stricter) — Whitelist specific tools (e.g. `Read,Write,Edit,Bash` but not `WebFetch`). More secure but requires per-task configuration.

`plugin/sidecar.sh` defaults to skip-permissions. Override per-call by passing different flags through `"$@"` (the wrapper passes args verbatim after the prompt, so `ccp-deepseek-rescue "task" --allowedTools Read,Bash` works).

## Usage from main Claude session

Main Claude's Bash tool runs the wrapper:

```bash
ccp-deepseek-rescue "讀 src/foo.ts，把所有 Promise.then 重構成 async/await，跑 npm test 確認通過"
```

DS V4-Pro session: opens, reads file, edits, runs test, prints summary, exits. Main Claude receives the summary text via Bash stdout and decides next move.

For multi-step delegation (Claude plans → DS implements → Claude reviews), main Claude can dispatch multiple sequential or parallel `ccp-*-rescue` calls.

## Cost framing

| Cost component | Path 1 sidecar |
|---|---|
| Main Claude (Opus) | per-token Pro/Max quota |
| DS V4-Pro (sub-task) | $0.435/M in, $0.87/M out (75% off until 5/31) — ~10x cheaper than Opus |
| DS V4-Flash (DS subagent during sub-task) | even cheaper |
| Cache hit | DS auto-cache up to 99% (no creation fee) |

Net: implementation-heavy sub-tasks delegated to DS save ~90% on token cost vs main Claude doing it all.

## What's archived (was over-engineered)

The original Path 1 design (this doc, pre-2026-05-03) proposed:
- CC plugin manifest (`plugin.json`, `.claude/plugins/`)
- Per-vendor `agents/<vendor>-rescue.md` (subagent definitions)
- Per-vendor `commands/<vendor>.md` (slash commands)
- Per-vendor `lib/<vendor>-call.sh` wrappers (50-150 lines each, with curl + jq parsing for non-CLI vendors)

Total estimated: 300–600 lines of code across 4-5 vendors.

**Why archived**: All of the above complexity assumed each vendor needs a custom subprocess pattern (CLI wrapper for Qwen-Code / Kimi-CLI / curl for others). Stage 2 verification revealed that Path 0's `ANTHROPIC_BASE_URL` swap pattern + `claude -p` headless reuse covers 100% of the use cases. The vendor-specific subprocess patterns become unnecessary.

The archived approach would still be needed if:
- A vendor doesn't have an Anthropic-native endpoint (forcing custom CLI)
- A specific vendor CLI has features beyond what `claude -p` exposes (e.g. Qwen-Code's planning mode that's not in CC)
- Headless mode breaks for some vendor in unforeseen way

If those cases arise, fall back to per-vendor `lib/*-call.sh` wrapper for that specific vendor only, not as the default architecture.

## Implementation order

1. **Write `plugin/sidecar.sh`** — 7 wrapper functions for Path 0 vendors
2. **Test with DeepSeek** — main Claude session dispatches via Bash → `ccp-deepseek-rescue "<small task>"` → verify agent loop + final message printout
3. **Document in plugin/README.md** — usage, safety note, cost framing
4. **Per-vendor onboarding (Kimi/GLM/Qwen)** — when added, sidecar function added simultaneously since Path 0 + Path 1 are unified

## Open questions

- **Headless subagent dispatch behavior**: in `claude -p`, when the model emits a `Task` tool_use, does the subagent run inline (V4-Flash spawned in same process) or fail because no interactive UI? Needs first-dispatch test.
- **Stdout structuring**: `claude -p` defaults to plain text. For programmatic parsing from main Claude, may want `--output-format=json` or `--output-format=stream-json` (verify available + schema).
- **Long-running task timeout**: main Claude's Bash tool has default timeout. For sub-tasks expected to take 5+ minutes, may need `timeout` flag adjustment or background `&` + status polling.
