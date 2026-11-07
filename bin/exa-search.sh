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

KEY=$(security find-generic-password -s EXA_API_KEY -w 2>/dev/null || true)
TAVILY_KEY_FILE="$HOME/.config/tavily/api-key"
TAVILY_KEY=""
if [ -f "$TAVILY_KEY_FILE" ]; then
  TAVILY_KEY=$(tr -d '\n\r ' < "$TAVILY_KEY_FILE" 2>/dev/null || true)
fi

if [ -z "$KEY" ] && [ -z "$TAVILY_KEY" ]; then
  echo "ERROR: Neither EXA_API_KEY (keychain) nor ~/.config/tavily/api-key found" >&2
  exit 2
fi

bodyfile=$(mktemp /tmp/exa-body.XXXX)
trap 'rm -f "$bodyfile"' EXIT

status=0
used_engine=""

if [ -n "$KEY" ] && [ "${EXA_FORCE_FALLBACK:-0}" != "1" ]; then
  payload=$(jq -n --arg q "$QUERY" --argjson n "$N" \
    '{query:$q, type:"auto", numResults:$n, contents:{highlights:true}}')
  status=$(curl -sS -o "$bodyfile" -w "%{http_code}" \
    -X POST "https://api.exa.ai/search" \
    -H "x-api-key: $KEY" \
    -H "Content-Type: application/json" \
    --max-time 30 \
    -d "$payload" 2>/dev/null || echo 000)
  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    used_engine="exa"
  fi
fi

if [ -z "$used_engine" ] && [ -n "$TAVILY_KEY" ]; then
  t_payload=$(jq -n --arg q "$QUERY" --argjson n "$N" \
    '{query:$q, search_depth:"basic", max_results:$n}')
  status=$(curl -sS -o "$bodyfile" -w "%{http_code}" \
    -X POST "https://api.tavily.com/search" \
    -H "Authorization: Bearer $TAVILY_KEY" \
    -H "Content-Type: application/json" \
    --max-time 30 \
    -d "$t_payload" 2>/dev/null || echo 000)
  if [ "$status" -ge 200 ] && [ "$status" -lt 300 ]; then
    used_engine="tavily"
  fi
fi

if [ -z "$used_engine" ]; then
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
    + (if (.value.publishedDate // .value.published_date) then "\n    Date: \(.value.publishedDate // .value.published_date)" else "" end)
    + (if (.value.highlights // []) | length > 0
         then "\n    > " + (.value.highlights[0] | gsub("\n+"; " "))
       elif (.value.content // "") != ""
         then "\n    > " + ((.value.content | gsub("\n+"; " "))[:280])
       else "" end)
    + "\n"
' "$bodyfile"
