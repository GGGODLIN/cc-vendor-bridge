_cc_flag_takes_value() {
  case "${1:-}" in
    -r|--resume|--model|--effort|--settings|--fallback-model|--output-format|--input-format|--permission-mode|--plugin-dir|--add-dir|--mcp-config|--max-turns|--session-id|--system-prompt|--append-system-prompt|--append-subagent-system-prompt|--disallowed-tools|--allowed-tools|--disallowedTools|--allowedTools|--agents|--json-schema|--tools|-n|--name|--agent|--debug-file|--max-budget-usd|--autocompact|--plugin-url|--permission-prompts|--environment|--betas|--file|--system-prompt-file|--append-system-prompt-file|--remote-control-session-name-prefix)
      return 0
      ;;
    *)
      return 1
      ;;
  esac
}

# 在子 shell 設 header，避免下一次啟動繼承本次的 fast 選擇。
cc_fast_run() (
  local -a prefix=()
  while (( $# > 0 )) && [[ "$1" != -- ]]; do
    prefix+=("$1")
    shift
  done
  if (( $# == 0 || ${#prefix[@]} == 0 )); then
    printf '%s\n' 'cc_fast_run: missing launcher or argument separator' >&2
    return 2
  fi
  shift

  # 清除從上層常駐服務或舊版 herdr 繼承的殘留 child-session 與舊 pane 變數，避免觸發 nested_marker 關閉 .jsonl 轉錄檔寫入。
  unset CLAUDECODE CLAUDE_PID CLAUDE_CODE_CHILD_SESSION CLAUDE_CODE_SESSION_ID \
    CLAUDE_CODE_MESSAGING_SOCKET CLAUDE_CODE_MESSAGING_TOKEN CODEX_COMPANION_SESSION_ID
  [[ -n "${HC_TERMINAL_ID:-}" ]] && unset HERDR_ENV HERDR_PANE_ID HERDR_TAB_ID HERDR_WORKSPACE_ID HERDR_SOCKET_PATH
  export CLAUDE_CODE_FORCE_SESSION_PERSISTENCE=1

  # 分隔啟動器預設參數與使用者參數，不誤吞 prompt 裡的 -fast / -bot。
  local bot_selected=0
  while [[ "${1:-}" == -fast || "${1:-}" == --fast || "${1:-}" == -bot || "${1:-}" == --bot ]]; do
    if [[ "$1" == -bot || "$1" == --bot ]]; then
      shift
      bot_selected=1
      continue
    fi
    shift
    case $'\n'"${ANTHROPIC_CUSTOM_HEADERS:-}"$'\n' in
      *$'\nX-CCP-Fast: 1\n'*) ;;
      *)
        local headers="${ANTHROPIC_CUSTOM_HEADERS:-}"
        [[ -z "$headers" ]] || headers+=$'\n'
        export ANTHROPIC_CUSTOM_HEADERS="${headers}X-CCP-Fast: 1"
        ;;
    esac
  done
  if [[ "${1:-}" == -* && "${1:-}" != -- && "${1:-}" != -p && "${1:-}" != --print ]] && ! _cc_flag_takes_value "${1:-}"; then
    if [[ "${2:-}" == -bot || "${2:-}" == --bot ]]; then
      bot_selected=1
      set -- "$1" "${@:3}"
    fi
  fi
  if (( bot_selected )); then
    export PERSONAL_BOT_SESSION=1
    local bot_bin="${PERSONAL_BOT_BIN:-$HOME/Desktop/projects/personal-bot/bin/personal-bot}"
    if [[ ( -n "${HERDR_PANE_ID:-}" || -n "${HC_TERMINAL_ID:-}" ) && -x "$bot_bin" ]]; then
      "$bot_bin" register-session >/dev/null 2>&1 || true
    fi
  fi
  "${prefix[@]}" "$@"
)
