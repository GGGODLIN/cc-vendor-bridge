#!/usr/bin/env zsh

set -u

ROOT="${0:A:h:h}"
source "$ROOT/shell/ccp-functions.sh"

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

assert_not_contains \
  "ccp-gpt does not flatten subagent routing" \
  "${functions[ccp-gpt]}" \
  "CLAUDE_CODE_SUBAGENT_MODEL="

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
