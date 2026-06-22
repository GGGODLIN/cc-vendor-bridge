#!/usr/bin/env bash
# Unit tests for glm-quota-watch.sh --probe-once.
# Exercises: 5h parsing, weekly parsing, peak window detection, pause/resume decision.
set -uo pipefail
SCRIPT="$HOME/.claude/scripts/glm-quota-watch.sh"
FIXTURES="$(cd "$(dirname "$0")/fixtures/glm-cache" && pwd)"

pass=0; fail=0
assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "$expected" = "$actual" ]; then
    echo "  ✓ $label"
    pass=$((pass+1))
  else
    echo "  ✗ $label"
    echo "    expected: $expected"
    echo "    actual:   $actual"
    fail=$((fail+1))
  fi
}

# Inject NOW_CN override so peak detection is deterministic in tests.
probe() {
  local cache="$1" now_cn="$2" direction="$3" threshold="$4"
  CACHE_FILE="$cache" NOW_CN="$now_cn" \
    "$SCRIPT" --probe-once "$threshold" 30 360 "$direction" test
}

echo "== healthy cache, off-peak =="
out=$(probe "$FIXTURES/healthy.json" "10:00" above 85)
assert_eq "5h percentage parsed" "five_h=40%" "$(echo "$out" | grep -o 'five_h=[0-9]*%')"
assert_eq "weekly percentage parsed" "weekly=30%" "$(echo "$out" | grep -o 'weekly=[0-9]*%')"
assert_eq "off-peak detected" "in_peak=false" "$(echo "$out" | grep -o 'in_peak=[a-z]*')"
assert_eq "pause would not fire" "would_fire_pause=false" "$(echo "$out" | grep -o 'would_fire_pause=[a-z]*')"
assert_eq "resume would fire (5h<=85 & weekly<95 & not peak)" "would_fire_resume=true" "$(echo "$out" | grep -o 'would_fire_resume=[a-z]*')"

echo "== token-hot, off-peak =="
out=$(probe "$FIXTURES/token-hot.json" "10:00" above 85)
assert_eq "5h=87" "five_h=87%" "$(echo "$out" | grep -o 'five_h=[0-9]*%')"
assert_eq "pause fires (5h>=85)" "would_fire_pause=true" "$(echo "$out" | grep -o 'would_fire_pause=[a-z]*')"

echo "== healthy cache, in peak =="
out=$(probe "$FIXTURES/healthy.json" "14:30" above 85)
assert_eq "peak detected" "in_peak=true" "$(echo "$out" | grep -o 'in_peak=[a-z]*')"
assert_eq "pause fires (peak)" "would_fire_pause=true" "$(echo "$out" | grep -o 'would_fire_pause=[a-z]*')"
assert_eq "resume blocked (in peak)" "would_fire_resume=false" "$(echo "$out" | grep -o 'would_fire_resume=[a-z]*')"

echo "== healthy cache, peak boundary 13:55 =="
out=$(probe "$FIXTURES/healthy.json" "13:55" above 85)
assert_eq "13:55 IS in peak (inclusive)" "in_peak=true" "$(echo "$out" | grep -o 'in_peak=[a-z]*')"

echo "== healthy cache, peak boundary 18:05 =="
out=$(probe "$FIXTURES/healthy.json" "18:05" above 85)
assert_eq "18:05 IS in peak (inclusive)" "in_peak=true" "$(echo "$out" | grep -o 'in_peak=[a-z]*')"

echo "== healthy cache, just outside peak 18:06 =="
out=$(probe "$FIXTURES/healthy.json" "18:06" above 85)
assert_eq "18:06 OUT of peak" "in_peak=false" "$(echo "$out" | grep -o 'in_peak=[a-z]*')"

echo "== weekly-blocked, off-peak, 5h healthy =="
out=$(probe "$FIXTURES/weekly-blocked.json" "10:00" below 60)
assert_eq "weekly=97" "weekly=97%" "$(echo "$out" | grep -o 'weekly=[0-9]*%')"
assert_eq "resume blocked (weekly >= 95)" "would_fire_resume=false" "$(echo "$out" | grep -o 'would_fire_resume=[a-z]*')"

echo "== zero cache, off-peak =="
out=$(probe "$FIXTURES/zero.json" "10:00" above 85)
assert_eq "zero 5h" "five_h=0%" "$(echo "$out" | grep -o 'five_h=[0-9]*%')"
assert_eq "resume fires from zero" "would_fire_resume=true" "$(echo "$out" | grep -o 'would_fire_resume=[a-z]*')"

echo
echo "== results: pass=$pass fail=$fail =="
[ "$fail" -eq 0 ]
