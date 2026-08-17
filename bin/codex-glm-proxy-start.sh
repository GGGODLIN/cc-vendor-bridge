#!/usr/bin/env bash
# Start LiteLLM proxy as background bridge for codex CLI → z.ai GLM.
# Listens on localhost:4000, logs to ~/.cache/cc-vendor-bridge/litellm-zai.log
set -euo pipefail

PORT=4000
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BRIDGE_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
CONFIG="${BRIDGE_ROOT}/config/litellm-zai.yaml"
LOG_DIR="${HOME}/.cache/cc-vendor-bridge"
LOG="${LOG_DIR}/litellm-zai.log"
PIDFILE="${LOG_DIR}/litellm-zai.pid"

mkdir -p "$LOG_DIR"

if [[ -z "${ZAI_API_KEY:-}" ]]; then
  echo "codex-glm-proxy-start: ZAI_API_KEY not set. Source ~/.zsh_secrets first." >&2
  exit 1
fi

if /usr/sbin/lsof -nP -iTCP:${PORT} -sTCP:LISTEN >/dev/null 2>&1; then
  echo "codex-glm-proxy-start: port ${PORT} already in use:"
  /usr/sbin/lsof -nP -iTCP:${PORT} -sTCP:LISTEN
  exit 1
fi

UVX="$(command -v uvx || echo /opt/homebrew/bin/uvx)"
if [[ ! -x "$UVX" ]]; then
  echo "codex-glm-proxy-start: uvx not found. brew install uv." >&2
  exit 1
fi

echo "Starting LiteLLM proxy on port ${PORT}..."
ZAI_API_KEY="$ZAI_API_KEY" nohup "$UVX" --from 'litellm[proxy]' litellm \
  --config "$CONFIG" --port ${PORT} > "$LOG" 2>&1 &
echo $! > "$PIDFILE"
echo "pid=$(cat "$PIDFILE")  log=${LOG}"

# Wait up to 60s for ready
for i in $(seq 1 60); do
  code=$(/usr/bin/curl -sS --max-time 1 -o /dev/null -w "%{http_code}" \
    http://localhost:${PORT}/health/readiness 2>/dev/null || echo 000)
  if [[ "$code" == "200" ]]; then
    echo "ready after ${i}s"
    exit 0
  fi
  sleep 1
done

echo "codex-glm-proxy-start: did not become ready within 60s. tail of log:" >&2
tail -n 30 "$LOG" >&2
exit 1
