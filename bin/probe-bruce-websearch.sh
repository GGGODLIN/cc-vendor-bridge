#!/usr/bin/env bash
# Probe Bruce token proxy WebSearch (Anthropic server-side tool) acceptance.
#
# Usage:  BRUCE_API_KEY=... probe-bruce-websearch.sh
#
# Sends raw curl directly to Bruce's /v1/messages declaring Anthropic's
# server-side `web_search_20250305` tool. Reports HTTP status, request_id,
# and any error snippet.
#
# Expected before fix (2026-06-19 morning report):
#   HTTP 400 + "tools.0.input_schema: Invalid input: expected record"
# Expected after fix:
#   HTTP 200 (with or without web_search_tool_result blocks)

set -uo pipefail
: "${BRUCE_API_KEY:?BRUCE_API_KEY not set}"
URL="https://api.bruceai.net/v1/messages"

salt="$(date +%s%N)-$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 12)"
payloadfile=$(mktemp /tmp/bruce-ws-payload.XXXX)
bodyfile=$(mktemp /tmp/bruce-ws-body.XXXX)

jq -n --arg salt "$salt" '{
  model: "gpt-5.5",
  max_tokens: 256,
  stream: false,
  tools: [
    { type: "web_search_20250305", name: "web_search", max_uses: 1 }
  ],
  messages: [
    { role: "user",
      content: ("Probe " + $salt + " — search the web for: official Anthropic content block tool_reference. Then reply OK.")
    }
  ]
}' > "$payloadfile"

status=$(curl -sS -o "$bodyfile" -w "%{http_code}" \
  -X POST "$URL" \
  -H "Authorization: Bearer ${BRUCE_API_KEY}" \
  -H "Content-Type: application/json" \
  -H "anthropic-version: 2023-06-01" \
  --max-time 90 \
  -d "@$payloadfile")

if jq -e . "$bodyfile" >/dev/null 2>&1; then
  req_id=$(jq -r '.id // .error.request_id // "n/a"' "$bodyfile")
  err_msg=$(jq -r '.error.message // empty' "$bodyfile")
  tool_blocks=$(jq -r '[.content[]? | select(.type == "server_tool_use" or .type == "web_search_tool_result" or .type == "tool_use")] | length' "$bodyfile" 2>/dev/null || echo "?")
else
  req_id=$(grep -oE '"id":"[^"]+"' "$bodyfile" | head -n1 | sed 's/.*:"//;s/"$//')
  [[ -z "$req_id" ]] && req_id="n/a"
  err_msg=$(grep -oE '"message":"[^"]+"' "$bodyfile" | head -n1 | sed 's/^"message":"//;s/"$//')
  tool_blocks="?"
fi

echo "=== Bruce WebSearch tool probe ==="
echo "URL : $URL"
echo "Time: $(date -Iseconds)"
echo
printf 'HTTP %s  request_id=%s  web_search_blocks=%s\n' "$status" "${req_id:0:48}" "$tool_blocks"
if [[ -n "${err_msg:-}" ]]; then
  printf '  └─ error: %s\n' "${err_msg:0:300}"
fi

echo
if [[ "$status" == "200" ]]; then
  echo "✅ FIX VERIFIED — WebSearch tool accepted by proxy."
elif [[ "$status" == "400" && "$err_msg" == *"input_schema"* ]]; then
  echo "❌ STILL BROKEN — same input_schema rejection as 2026-06-19 morning."
  echo "   Body (first 600 bytes):"
  head -c 600 "$bodyfile"; echo
else
  echo "⚠️  UNEXPECTED — HTTP $status / error shape differs from original report."
  echo "   Body (first 600 bytes):"
  head -c 600 "$bodyfile"; echo
fi

rm -f "$payloadfile" "$bodyfile"
