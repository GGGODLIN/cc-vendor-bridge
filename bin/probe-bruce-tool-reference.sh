#!/usr/bin/env bash
# Probe Bruce token proxy `tool_reference` content block acceptance.
#
# Usage:  BRUCE_API_KEY=... probe-bruce-tool-reference.sh
#
# Replays the exact mid-conversation shape that crashed 36/41 subagents on
# 2026-06-19: user → assistant(tool_use ToolSearch) →
# user(tool_result(content=[{type:tool_reference}])).
#
# Expected before fix:
#   HTTP 400 + "messages.X.content: Invalid input"
# Expected after fix:
#   HTTP 200

set -uo pipefail
: "${BRUCE_API_KEY:?BRUCE_API_KEY not set}"
URL="https://bruce-token-proxy-431026649525.asia-east1.run.app/v1/messages"

salt="$(date +%s%N)-$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 12)"
payloadfile=$(mktemp /tmp/bruce-tref-payload.XXXX)
bodyfile=$(mktemp /tmp/bruce-tref-body.XXXX)

jq -n --arg salt "$salt" '{
  model: "gpt-5.5",
  max_tokens: 64,
  stream: false,
  tools: [
    {
      name: "ToolSearch",
      description: "Fetches schema definitions for deferred tools.",
      input_schema: {
        type: "object",
        properties: {
          query: { type: "string" },
          max_results: { type: "number" }
        },
        required: ["query"]
      }
    }
  ],
  messages: [
    { role: "user",
      content: ("Probe " + $salt + " — load WebFetch tool schema.")
    },
    { role: "assistant",
      content: [
        { type: "tool_use",
          id: "toolu_probe_tref_01",
          name: "ToolSearch",
          input: { query: "select:WebFetch", max_results: 1 }
        }
      ]
    },
    { role: "user",
      content: [
        { type: "tool_result",
          tool_use_id: "toolu_probe_tref_01",
          content: [
            { type: "tool_reference", tool_name: "WebFetch" }
          ]
        }
      ]
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
else
  req_id=$(grep -oE '"id":"[^"]+"' "$bodyfile" | head -n1 | sed 's/.*:"//;s/"$//')
  [[ -z "$req_id" ]] && req_id="n/a"
  err_msg=$(grep -oE '"message":"[^"]+"' "$bodyfile" | head -n1 | sed 's/^"message":"//;s/"$//')
fi

echo "=== Bruce tool_reference block probe ==="
echo "URL : $URL"
echo "Time: $(date -Iseconds)"
echo
printf 'HTTP %s  request_id=%s\n' "$status" "${req_id:0:48}"
if [[ -n "${err_msg:-}" ]]; then
  printf '  └─ error: %s\n' "${err_msg:0:300}"
fi

echo
if [[ "$status" == "200" ]]; then
  echo "✅ FIX VERIFIED — tool_reference content block accepted by proxy."
elif [[ "$status" == "400" && "$err_msg" == *"messages"*"content"* ]]; then
  echo "❌ STILL BROKEN — same messages.X.content rejection as 2026-06-19 morning."
  echo "   Body (first 600 bytes):"
  head -c 600 "$bodyfile"; echo
else
  echo "⚠️  UNEXPECTED — HTTP $status / error shape differs from original report."
  echo "   Body (first 600 bytes):"
  head -c 600 "$bodyfile"; echo
fi

rm -f "$payloadfile" "$bodyfile"
