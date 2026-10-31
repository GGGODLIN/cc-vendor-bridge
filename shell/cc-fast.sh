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
  if [[ "${1:-}" == -* && "${1:-}" != -p && "${1:-}" != --print && ( "${2:-}" == -bot || "${2:-}" == --bot ) ]]; then
    bot_selected=1
    set -- "$1" "${@:3}"
  fi
  if (( bot_selected )); then
    export PERSONAL_BOT_SESSION=1
    local bot_bin="${PERSONAL_BOT_BIN:-$HOME/Desktop/projects/personal-bot/bin/personal-bot}"
    if [[ -n "${HERDR_PANE_ID:-}" && -x "$bot_bin" ]]; then
      "$bot_bin" register-session >/dev/null 2>&1 || true
    fi
  fi
  "${prefix[@]}" "$@"
)
