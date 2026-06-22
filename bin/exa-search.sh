#!/usr/bin/env bash
# bin/exa-search.sh — Exa Search API curl wrapper for cc-vendor-bridge.
#
# Reads EXA_API_KEY from macOS keychain (service name: EXA_API_KEY),
# calls https://api.exa.ai/search with type=auto + highlights,
# dedups results by URL path (strips query strings), outputs LLM-ready
# markdown by default or raw JSON with --json flag.
#
# Usage:
#   exa-search.sh "your query here" [numResults]
#   exa-search.sh --json "your query" [numResults]
#
# Exit codes: 0 OK, 1 missing query, 2 keychain miss, 3 HTTP/API error.

set -uo pipefail

JSON_OUT=0
if [ "${1:-}" = "--json" ]; then JSON_OUT=1; shift; fi

QUERY="${1:-}"
N="${2:-5}"

if [ -z "$QUERY" ]; then
  echo "Usage: $(basename "$0") [--json] <query> [numResults]" >&2
  exit 1
fi

KEY=$(security find-generic-password -s EXA_API_KEY -w 2>/dev/null)
if [ -z "$KEY" ]; then
  echo "ERROR: EXA_API_KEY not in macOS keychain" >&2
  echo "Add it with: security add-generic-password -s EXA_API_KEY -a \"\$USER\" -U -w" >&2
  exit 2
fi

bodyfile=$(mktemp /tmp/exa-body.XXXX)
trap 'rm -f "$bodyfile"' EXIT

payload=$(jq -n --arg q "$QUERY" --argjson n "$N" \
  '{query:$q, type:"auto", numResults:$n, contents:{highlights:true}}')

status=$(curl -sS -o "$bodyfile" -w "%{http_code}" \
  -X POST "https://api.exa.ai/search" \
  -H "x-api-key: $KEY" \
  -H "Content-Type: application/json" \
  --max-time 30 \
  -d "$payload")

if [ "$status" -lt 200 ] || [ "$status" -ge 300 ]; then
  echo "ERROR: HTTP $status" >&2
  cat "$bodyfile" >&2
  echo >&2
  exit 3
fi

if [ "$JSON_OUT" = "1" ]; then
  cat "$bodyfile"
  exit 0
fi

jq -r '
  .results
  | map(.url |= (split("?")[0] | split("#")[0]))
  | reduce .[] as $r ([]; if any(.[]; .url == $r.url) then . else . + [$r] end)
  | to_entries[]
  | "[\(.key + 1)] \(.value.title // "(no title)")"
    + "\n    URL: \(.value.url)"
    + (if .value.publishedDate then "\n    Date: \(.value.publishedDate)" else "" end)
    + (if (.value.highlights // []) | length > 0
         then "\n    > " + (.value.highlights[0] | gsub("\n+"; " "))
         else "" end)
    + "\n"
' "$bodyfile"
