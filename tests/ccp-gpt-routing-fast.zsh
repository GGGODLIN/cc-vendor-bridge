#!/usr/bin/env zsh

set -u

ROOT="${0:A:h:h}"
alias claude='claude --settings '\''{"ultracode": true}'\'''
source "$ROOT/shell/ccp-functions.sh"
unalias claude

failures=0

assert_eq() {
  local label="$1"
  local expected="$2"
  local actual="$3"
  if [[ "$actual" == "$expected" ]]; then
    print -r -- "ok - $label"
  else
    print -ru2 -- "not ok - $label"
    print -ru2 -- "expected: ${(qqq)expected}"
    print -ru2 -- "actual:   ${(qqq)actual}"
    (( failures++ ))
  fi
}

assert_not_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" != *"$needle"* ]]; then
    print -r -- "ok - $label"
  else
    print -ru2 -- "not ok - $label"
    print -ru2 -- "unexpected: ${(qqq)needle}"
    (( failures++ ))
  fi
}

assert_contains() {
  local label="$1"
  local haystack="$2"
  local needle="$3"
  if [[ "$haystack" == *"$needle"* ]]; then
    print -r -- "ok - $label"
  else
    print -ru2 -- "not ok - $label"
    print -ru2 -- "missing: ${(qqq)needle}"
    (( failures++ ))
  fi
}

assert_not_contains \
  "ccp-gpt does not flatten subagent routing" \
  "${functions[ccp-gpt]}" \
  "CLAUDE_CODE_SUBAGENT_MODEL="

assert_not_contains \
  "ccp-gpt does not inherit the global ultracode alias" \
  "${functions[ccp-gpt]}" \
  "ultracode"

assert_contains \
  "ccp-gpt defaults to max effort" \
  "${functions[ccp-gpt]}" \
  "command claude --effort max"

assert_contains \
  "ccp-gpt maps Opus to Luna at max effort" \
  "${functions[ccp-gpt]}" \
  'ANTHROPIC_DEFAULT_OPUS_MODEL="${ANTHROPIC_DEFAULT_OPUS_MODEL:-gpt-5.6-luna(max)}"'

assert_contains \
  "ccp-gpt exposes the Fast main-model option" \
  "${functions[ccp-gpt]}" \
  "ANTHROPIC_CUSTOM_MODEL_OPTION="

assert_contains \
  "ccp-gpt labels the Fast main-model option" \
  "${functions[ccp-gpt]}" \
  "ANTHROPIC_CUSTOM_MODEL_OPTION_NAME="

ccp_list_output="$(ccp-list)"

assert_contains \
  "ccp-list explains the session-only model key" \
  "$ccp_list_output" \
  "press s"

assert_not_contains \
  "ccp-list does not recommend the persistent direct model command" \
  "$ccp_list_output" \
  "/model gpt-5.6-sol-fast"

if (( ${+functions[ccp-gpt-fast]} )); then
  ccp-gpt() {
    print -r -- "${ANTHROPIC_CUSTOM_HEADERS:-}"
  }

  assert_eq \
    "ccp-gpt-fast adds the opt-in header" \
    "X-CCP-Fast: 1" \
    "$(ccp-gpt-fast)"

  assert_eq \
    "ccp-gpt-fast preserves existing custom headers" \
    $'X-Existing: yes\nX-CCP-Fast: 1' \
    "$(ANTHROPIC_CUSTOM_HEADERS='X-Existing: yes' ccp-gpt-fast)"
else
  print -ru2 -- "not ok - ccp-gpt-fast exists"
  (( failures++ ))
fi

(( failures == 0 ))
