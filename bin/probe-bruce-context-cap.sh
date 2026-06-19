#!/usr/bin/env bash
# Probe Bruce token proxy actual context cap.
#
# Usage:  BRUCE_API_KEY=... probe-bruce-context-cap.sh [sizes_in_K_chars...]
# Default sizes: 100 300 350 500 700 900 1100
#
# Sends raw curl directly to Bruce's /v1/messages with a controlled-size payload
# of random hex filler (low BPE compression, ratio ≈ 1.6 chars/token). Reports
# HTTP status, server-side input_tokens, server-side output_tokens, content len,
# request_id. Random per-call salt prevents any caching from masking real cap.
#
# Bruce returns either SSE-streamed body OR plain JSON depending on payload size
# and stream flag. We grep both shapes for input_tokens.
#
# IMPORTANT silent-failure mode: large payloads sometimes return HTTP 200 with
# usage.input_tokens=0 and empty content — the proxy SILENTLY drops the request.
# We surface this by also reporting output_tokens + content length.

set -uo pipefail

: "${BRUCE_API_KEY:?BRUCE_API_KEY not set}"
URL="https://bruce-token-proxy-431026649525.asia-east1.run.app/v1/messages"

if [[ $# -eq 0 ]]; then
  sizes=(100 300 350 500 700 900 1100)
else
  sizes=("$@")
fi

build_filler() {
  local target_chars=$1
  local outfile=$2
  LC_ALL=C tr -dc '0-9a-f' </dev/urandom \
    | head -c "$target_chars" \
    | fold -w 8 \
    | tr '\n' ' ' \
    > "$outfile"
}

probe_one() {
  local k=$1
  local target_chars=$(( k * 1024 ))
  local salt
  salt="$(date +%s%N)-$(LC_ALL=C tr -dc 'a-zA-Z0-9' </dev/urandom | head -c 32)"

  local fillerfile payloadfile bodyfile
  fillerfile=$(mktemp /tmp/bruce-filler-$k.XXXX)
  payloadfile=$(mktemp /tmp/bruce-payload-$k.XXXX)
  bodyfile=$(mktemp /tmp/bruce-body-$k.XXXX)

  build_filler "$target_chars" "$fillerfile"

  jq -n \
    --arg salt "$salt" \
    --rawfile filler "$fillerfile" \
    '{
      model: "gpt-5.5",
      max_tokens: 32,
      stream: false,
      messages: [
        { role: "user",
          content: ("Probe salt: " + $salt + "\n\nFiller (ignore):\n" + $filler + "\n\nReply OK.")
        }
      ]
    }' > "$payloadfile"

  local status
  status=$(curl -sS -o "$bodyfile" -w "%{http_code}" \
    -X POST "$URL" \
    -H "Authorization: Bearer ${BRUCE_API_KEY}" \
    -H "Content-Type: application/json" \
    -H "anthropic-version: 2023-06-01" \
    --max-time 180 \
    -d "@$payloadfile")

  local req_id input_tokens output_tokens content_len err_snip
  # Try JSON first (stream:false path)
  if jq -e . "$bodyfile" >/dev/null 2>&1; then
    input_tokens=$(jq -r '.usage.input_tokens // empty' "$bodyfile")
    output_tokens=$(jq -r '.usage.output_tokens // empty' "$bodyfile")
    req_id=$(jq -r '.id // .error.request_id // "n/a"' "$bodyfile")
    err_snip=$(jq -r '.error.message // empty' "$bodyfile" | head -c 240)
    content_len=$(jq -r '[.content[]?.text // ""] | join("") | length' "$bodyfile" 2>/dev/null || echo "?")
  else
    # SSE path
    input_tokens=$(grep -oE '"input_tokens":[0-9]+' "$bodyfile" | tail -n1 | grep -oE '[0-9]+')
    output_tokens=$(grep -oE '"output_tokens":[0-9]+' "$bodyfile" | tail -n1 | grep -oE '[0-9]+')
    req_id=$(grep -oE '"id":"[^"]+"' "$bodyfile" | head -n1 | sed 's/.*:"//;s/"$//')
    [[ -z "$req_id" ]] && req_id="n/a"
    err_snip=$(grep -oE '"message":"[^"]+"' "$bodyfile" | head -n1 | sed 's/^"message":"//;s/"$//' | head -c 240)
    # SSE content delta count
    content_len=$(grep -oE '"text_delta","text":"[^"]*"' "$bodyfile" \
      | sed 's/.*,"text":"//;s/"$//' \
      | awk '{ total += length($0) } END { print total+0 }')
  fi

  printf '%6sK | HTTP %3s | in=%-7s out=%-3s content=%-4s | id=%s\n' \
    "$k" "$status" "${input_tokens:-—}" "${output_tokens:-—}" "${content_len:-—}" \
    "${req_id:0:56}"
  if [[ -n "${err_snip:-}" ]]; then
    printf '         └─ error: %s\n' "$err_snip"
  fi
  if [[ "$status" == "200" && "${input_tokens:-0}" == "0" && "${content_len:-0}" == "0" ]]; then
    printf '         └─ ⚠️  SILENT-DROP: 200 OK but empty body + 0 input_tokens\n'
  fi

  rm -f "$fillerfile" "$payloadfile" "$bodyfile"
}

echo "=== Bruce backend context-cap probe ==="
echo "URL : $URL"
echo "Time: $(date -Iseconds)"
echo "Note: random hex filler (≈ 1.6 chars/token); per-call salt; cache cannot mask."
echo "      content=0 + input_tokens=0 + HTTP 200 = silent backend drop."
echo
printf '%6s | %s | %s | %s\n' "size" "status" "tokens/content" "id (truncated)"
printf -- '--------|----------|-------------------------------|---------------------------------------\n'

for k in "${sizes[@]}"; do
  probe_one "$k"
done
