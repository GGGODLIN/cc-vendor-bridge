# DeepSeek tool_choice rewriter proxy

Thin Bun proxy that fixes [caveat 8](../docs/caveats.md) — DeepSeek anthropic endpoint rejects `tool_choice: {type:"tool", name:"X"}` with HTTP 400 "deepseek-reasoner does not support this tool_choice".

The proxy intercepts requests to `127.0.0.1:9091`, rewrites specific tool_choice to `{type:"any"}`, and forwards everything else unchanged to `https://api.deepseek.com/anthropic`.

## Files

- `server.ts` — single-file Bun proxy (zero deps, native `Bun.serve` + `fetch`)
- `package.json` — `bun run start` / `bun run dev` scripts
- `launchd.plist` — macOS auto-start template (paths hardcoded for current user)

## Install (one-time)

```bash
# 1. Verify bun installed
which bun  # should show ~/.bun/bin/bun

# 2. Install plist to LaunchAgents
cp launchd.plist ~/Library/LaunchAgents/com.gggodlin.cc-vendor-bridge-proxy.plist

# 3. Bootstrap (loads + starts)
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/com.gggodlin.cc-vendor-bridge-proxy.plist

# 4. Verify it's listening on 127.0.0.1:9091
lsof -i :9091 -P -n | grep LISTEN
```

## Daemon control

```bash
# Restart (after editing server.ts)
launchctl kickstart -k "gui/$UID/com.gggodlin.cc-vendor-bridge-proxy"

# Stop temporarily
launchctl bootout "gui/$UID/com.gggodlin.cc-vendor-bridge-proxy"
launchctl bootstrap "gui/$UID" ~/Library/LaunchAgents/com.gggodlin.cc-vendor-bridge-proxy.plist

# Tail log
tail -f ~/Library/Logs/cc-vendor-bridge-proxy.log

# Uninstall completely
launchctl bootout "gui/$UID/com.gggodlin.cc-vendor-bridge-proxy"
rm ~/Library/LaunchAgents/com.gggodlin.cc-vendor-bridge-proxy.plist
```

## How `ccp-deepseek` uses it

`shell/ccp-functions.sh` `ccp-deepseek` is wired to:

1. Check if `:9091` is listening (`nc -z 127.0.0.1 9091`)
2. If not, `launchctl kickstart` the daemon and wait up to 5s for ready
3. Then `ANTHROPIC_BASE_URL=http://127.0.0.1:9091` and exec claude

So you don't need to manually ensure the proxy is up — `ccp-deepseek` handles it.

## Verify caveat 8 is fixed

```bash
# Direct hit (reproduces caveat 8)
curl -sS -w "\nHTTP %{http_code}\n" -X POST https://api.deepseek.com/anthropic/v1/messages \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-pro","max_tokens":30,"tools":[{"name":"ping","description":"x","input_schema":{"type":"object","properties":{}}}],"tool_choice":{"type":"tool","name":"ping"},"messages":[{"role":"user","content":"hi"}]}'
# → HTTP 400 "deepseek-reasoner does not support this tool_choice"

# Via proxy (caveat 8 fixed)
curl -sS -w "\nHTTP %{http_code}\n" -X POST http://127.0.0.1:9091/v1/messages \
  -H "Authorization: Bearer $DEEPSEEK_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "Content-Type: application/json" \
  -d '{"model":"deepseek-v4-pro","max_tokens":30,"tools":[{"name":"ping","description":"x","input_schema":{"type":"object","properties":{}}}],"tool_choice":{"type":"tool","name":"ping"},"messages":[{"role":"user","content":"hi"}]}'
# → HTTP 200, tool_use → ping
```

## Security

- `Bun.serve({ hostname: "127.0.0.1", ... })` — listens on loopback only, never exposed to LAN
- Authorization header is forwarded as-is to upstream, never logged
- No request bodies persisted to disk

## Cross-machine sync

Plist paths are hardcoded to `linhancheng`. To use on another machine, edit `launchd.plist` and replace `/Users/linhancheng` with the target user's home directory before installing.
