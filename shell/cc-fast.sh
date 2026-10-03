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

  # 分隔啟動器預設參數與使用者參數，不誤吞 prompt 裡的 -fast。
  while [[ "${1:-}" == -fast || "${1:-}" == --fast ]]; do
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
  "${prefix[@]}" "$@"
)
