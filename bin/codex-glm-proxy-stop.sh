#!/usr/bin/env bash
# Stop LiteLLM proxy started by codex-glm-proxy-start.sh.
set -euo pipefail
PIDFILE="${HOME}/.cache/cc-vendor-bridge/litellm-zai.pid"
if [[ -f "$PIDFILE" ]]; then
  pid=$(cat "$PIDFILE")
  if kill -0 "$pid" 2>/dev/null; then
    kill "$pid"
    echo "stopped pid=$pid"
  fi
  rm -f "$PIDFILE"
fi
# Fallback: kill any uvx litellm process bound to our config name
pkill -f "litellm-zai.yaml" 2>/dev/null || true
echo "done"
