# `/glm-workflow-monitor` Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add `/glm-workflow-monitor` slash command + supporting `glm-quota-watch.sh` + hook routing so ccp-glm background workflows get watch-pause-resume parity with `/workflow-monitor` (Anthropic) and `/bruce-workflow-monitor` (Bruce).

**Architecture:** Lean fork of `/bruce-workflow-monitor`. New watch script reads existing local cache `~/.claude/cache/vendor-glm-*.json` (cc-quota-fetcher chrome ext path — no new API call, 0 token cost). Two pause triggers (5h tokens ≥ 85% OR CN peak window 13:55-18:05); resume requires 5h ≤ 60% AND weekly < 95% AND not peak. Hook `workflow-monitor-nudge.sh` gains a `glm)` case mirroring `bruce)`.

**Tech Stack:** bash shell scripts, `jq`, claude code slash command markdown, PostToolUse hook.

## Global Constraints

- TZ for peak window: **hard-coded `Asia/Shanghai`** — never inherit local TZ
- Peak window: **[13:55, 18:05] inclusive** (HH:MM string compare)
- 5h pause threshold: **85** (試水溫值, trial-tunable via positional arg)
- 5h resume threshold: **60**
- Weekly resume ceiling: **95** (env-overridable via `WEEKLY_CEIL`)
- Cache staleness: warn at **mtime > 5 min**, abort at **mtime > 15 min**
- State/args filenames namespaced as `glm-workflow-monitor-state-<sid>.json` / `glm-workflow-monitor-args-<sid>.json` — distinct from anthropic/bruce
- Process tag for pgrep: `glm-quota-watch.sh` (substring filter)
- Never `pkill -f` watch processes (cross-session safety) — always `kill <pid>` recorded PID or session-scoped grep
- Cleanup chains: TERM → sleep 0.5 → re-pgrep → KILL → sleep 0.3 → re-pgrep → loud `❌` if alive (verification non-negotiable)
- Never use `awk '{print $1}'` in command markdown — CC harness rewrites `$1` to active task id; use `cut -d' ' -f1` instead

## File Structure

| File | Repo | Action | Responsibility |
|---|---|---|---|
| `~/.claude/scripts/glm-quota-watch.sh` | `~/.claude/` | create | Poll cache → fire on 5h/peak threshold cross; dumb execution body for the command |
| `~/.claude/commands/glm-workflow-monitor.md` | `~/.claude/` | create | Slash command markdown — watch/pause/resume orchestration; lean fork of `/bruce-workflow-monitor` |
| `~/.claude/hooks/workflow-monitor-nudge.sh` | `~/.claude/` | modify | Add `glm)` case in CC_VENDOR switch (between `bruce)` and `*)`) |
| `bin/probe-glm-quota-watch.sh` | `cc-vendor-bridge` | create | Unit-test harness for `glm-quota-watch.sh --probe-once` decision logic against fixture cache files |
| `~/Desktop/projects/.claude/trials/active.md` | individual file | append | Register glm-workflow-monitor trial entry per CLAUDE.md trial discipline |

---

### Task 1: Build `glm-quota-watch.sh` probe-once mode (pure decision logic, TDD with fixtures)

**Files:**
- Create: `~/.claude/scripts/glm-quota-watch.sh`
- Test: `bin/probe-glm-quota-watch.sh` (cc-vendor-bridge repo)

**Interfaces:**
- Consumes: cache file path (default `~/.claude/cache/vendor-glm-*.json` first match), `TZ=Asia/Shanghai date +%H:%M` for peak detection
- Produces: script with `--probe-once` flag printing structured one-liner the loop in Task 2 + tests in this task consume

  ```
  five_h=<int>% weekly=<int>% mtime_age=<sec> in_peak=<true|false> would_fire_pause=<true|false> would_fire_resume=<true|false>
  ```

- [ ] **Step 1.1: Stub script with arg parsing + usage**

```bash
mkdir -p ~/.claude/scripts
cat > ~/.claude/scripts/glm-quota-watch.sh <<'SH'
#!/usr/bin/env bash
# glm-quota-watch.sh THRESHOLD [POLL_SECONDS] [MAX_MINUTES] [DIRECTION] [SESSION_ID]
#
# Dumb execution body for /glm-workflow-monitor. Mirrors workflow-limit-watch.sh
# (anthropic) + bruce-health-watch.sh (bruce) shape. Reads local cache
# ~/.claude/cache/vendor-glm-<profile>.json (cc-quota-fetcher chrome ext path —
# no API call, 0 token cost).
#
# Pause direction: fire when 5h >= THRESHOLD OR in CN peak window [13:55, 18:05]
# Resume direction: fire when 5h <= THRESHOLD AND weekly < WEEKLY_CEIL AND NOT in peak
#
# Env overrides:
#   WEEKLY_CEIL=95           block resume if weekly tokens % >= this
#   PEAK_START_CN="13:55"    CN peak window start (HH:MM)
#   PEAK_END_CN="18:05"      CN peak window end (HH:MM, inclusive)
#   STALE_WARN_MIN=5         cache mtime > N min → stderr warn
#   STALE_ABORT_MIN=15       cache mtime > N min → exit non-zero
#   CACHE_FILE=<path>        override cache file (default: first ~/.claude/cache/vendor-glm-*.json)
#
# Flags:
#   --probe-once             skip the poll loop; print one structured line + exit 0
#
# exit 0 = threshold crossed (or probe-once success). exit 2 = safety timeout.
# exit 3 = config error (no cache file / jq missing / cache > STALE_ABORT_MIN old).
set -uo pipefail

PROBE_ONCE=0
while [[ "${1:-}" == --* ]]; do
  case "$1" in
    --probe-once) PROBE_ONCE=1; shift ;;
    *) echo "glm-quota-watch: unknown flag $1" >&2; exit 3 ;;
  esac
done

THRESHOLD=${1:-85}
POLL=${2:-30}
MAX_MINUTES=${3:-360}
DIRECTION=${4:-above}
SESSION_ID=${5:-}

WEEKLY_CEIL=${WEEKLY_CEIL:-95}
PEAK_START_CN=${PEAK_START_CN:-13:55}
PEAK_END_CN=${PEAK_END_CN:-18:05}
STALE_WARN_MIN=${STALE_WARN_MIN:-5}
STALE_ABORT_MIN=${STALE_ABORT_MIN:-15}

command -v jq >/dev/null || { echo "glm-quota-watch: jq not found" >&2; exit 3; }

# Cache file resolution: env override > glob first match
if [ -z "${CACHE_FILE:-}" ]; then
  shopt -s nullglob 2>/dev/null || true
  for f in "$HOME"/.claude/cache/vendor-glm-*.json; do
    CACHE_FILE="$f"; break
  done
fi
if [ -z "${CACHE_FILE:-}" ] || [ ! -f "$CACHE_FILE" ]; then
  echo "glm-quota-watch: no cache file found at ~/.claude/cache/vendor-glm-*.json — chrome ext / receiver runtime not deployed?" >&2
  exit 3
fi

# Placeholder for probe-once handler — implemented in subsequent steps.
if (( PROBE_ONCE )); then
  echo "five_h=0% weekly=0% mtime_age=0 in_peak=false would_fire_pause=false would_fire_resume=false"
  exit 0
fi

echo "glm-quota-watch: poll loop not implemented yet (use --probe-once for now)" >&2
exit 3
SH
chmod +x ~/.claude/scripts/glm-quota-watch.sh
```

- [ ] **Step 1.2: Run stub to verify arg parsing + cache resolution + jq check work**

Run: `~/.claude/scripts/glm-quota-watch.sh --probe-once 85`
Expected:
```
five_h=0% weekly=0% mtime_age=0 in_peak=false would_fire_pause=false would_fire_resume=false
```
(stub values; not yet real)

Negative test — Run: `CACHE_FILE=/tmp/nonexistent ~/.claude/scripts/glm-quota-watch.sh --probe-once 85; echo "exit=$?"`
Expected: stderr "no cache file found ...", `exit=3`

- [ ] **Step 1.3: Build test harness with fixtures**

```bash
mkdir -p bin/fixtures/glm-cache
cat > bin/fixtures/glm-cache/healthy.json <<'JSON'
{
  "vendor": "glm",
  "profile_id": "test01",
  "data": {
    "level": "lite",
    "limits": [
      { "type": "TIME_LIMIT", "unit": 5, "number": 1, "usage": 100, "currentValue": 13, "remaining": 87, "percentage": 13, "nextResetTime": 1784434774990 },
      { "type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 40 },
      { "type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 30, "nextResetTime": 1782447574978 }
    ]
  }
}
JSON
cat > bin/fixtures/glm-cache/token-hot.json <<'JSON'
{
  "vendor": "glm",
  "profile_id": "test01",
  "data": {
    "level": "lite",
    "limits": [
      { "type": "TIME_LIMIT", "unit": 5, "number": 1, "percentage": 13 },
      { "type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 87 },
      { "type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 30, "nextResetTime": 1782447574978 }
    ]
  }
}
JSON
cat > bin/fixtures/glm-cache/weekly-blocked.json <<'JSON'
{
  "vendor": "glm",
  "profile_id": "test01",
  "data": {
    "level": "lite",
    "limits": [
      { "type": "TIME_LIMIT", "unit": 5, "number": 1, "percentage": 13 },
      { "type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 40 },
      { "type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 97, "nextResetTime": 1782447574978 }
    ]
  }
}
JSON
cat > bin/fixtures/glm-cache/zero.json <<'JSON'
{
  "vendor": "glm",
  "profile_id": "test01",
  "data": {
    "level": "lite",
    "limits": [
      { "type": "TIME_LIMIT", "unit": 5, "number": 1, "percentage": 0 },
      { "type": "TOKENS_LIMIT", "unit": 3, "number": 5, "percentage": 0 },
      { "type": "TOKENS_LIMIT", "unit": 6, "number": 1, "percentage": 0, "nextResetTime": 1782447574978 }
    ]
  }
}
JSON
```

- [ ] **Step 1.4: Write failing test harness driving --probe-once across fixtures**

```bash
cat > bin/probe-glm-quota-watch.sh <<'SH'
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
SH
chmod +x bin/probe-glm-quota-watch.sh
```

- [ ] **Step 1.5: Run tests — verify they fail against stub**

Run: `bin/probe-glm-quota-watch.sh; echo "exit=$?"`
Expected: many `✗` (stub returns hard-coded `five_h=0%`...), `exit=1`

- [ ] **Step 1.6: Implement real probe-once logic in glm-quota-watch.sh**

Replace the `if (( PROBE_ONCE ))` placeholder block with real logic, and define helpers above the dispatch:

```bash
# Insert these helpers BEFORE the `if (( PROBE_ONCE ))` block:

# Read 5h rolling tokens percentage from (TOKENS_LIMIT, 3, 5).
# Fallback: any TOKENS_LIMIT with no nextResetTime (rolling).
read_5h_pct() {
  jq -r '
    .data.limits
    | map(select(.type=="TOKENS_LIMIT" and ((.unit==3 and .number==5) or (.nextResetTime==null))))
    | (first // {percentage:0}) | .percentage // 0
  ' "$CACHE_FILE" 2>/dev/null
}

# Read weekly tokens percentage from (TOKENS_LIMIT, 6, 1).
# Fallback: any TOKENS_LIMIT with nextResetTime 5d-9d out.
read_weekly_pct() {
  local now_ms=$(( $(date +%s) * 1000 ))
  jq -r --argjson now "$now_ms" '
    .data.limits
    | map(select(.type=="TOKENS_LIMIT" and ((.unit==6 and .number==1) or (
        .nextResetTime != null
        and ((.nextResetTime - $now) >= 432000000)
        and ((.nextResetTime - $now) <= 777600000)
      ))))
    | (first // {percentage:0}) | .percentage // 0
  ' "$CACHE_FILE" 2>/dev/null
}

# Cache file mtime age in seconds.
read_mtime_age() {
  local mt now
  mt=$(stat -f %m "$CACHE_FILE" 2>/dev/null || stat -c %Y "$CACHE_FILE" 2>/dev/null)
  now=$(date +%s)
  echo $(( now - mt ))
}

# CN peak window check. Tests inject NOW_CN; production uses TZ=Asia/Shanghai.
current_cn_hhmm() {
  if [ -n "${NOW_CN:-}" ]; then
    echo "$NOW_CN"
  else
    TZ=Asia/Shanghai date +%H:%M
  fi
}

# HH:MM string compare via lexicographic — works because zero-padded HH:MM is monotonic.
in_peak_window() {
  local now="$1"
  [[ "$now" > "$PEAK_START_CN" || "$now" == "$PEAK_START_CN" ]] && \
  [[ "$now" < "$PEAK_END_CN" || "$now" == "$PEAK_END_CN" ]]
}

# Decision logic.
would_fire_pause() {
  local five_h="$1" in_peak="$2"
  if (( five_h >= THRESHOLD )); then echo true; return; fi
  if [ "$in_peak" = "true" ]; then echo true; return; fi
  echo false
}

would_fire_resume() {
  local five_h="$1" weekly="$2" in_peak="$3"
  if (( five_h > THRESHOLD )); then echo false; return; fi
  if (( weekly >= WEEKLY_CEIL )); then echo false; return; fi
  if [ "$in_peak" = "true" ]; then echo false; return; fi
  echo true
}

# Replace the stub probe-once block with:
if (( PROBE_ONCE )); then
  five_h=$(read_5h_pct)
  weekly=$(read_weekly_pct)
  age=$(read_mtime_age)
  now_cn=$(current_cn_hhmm)
  if in_peak_window "$now_cn"; then in_peak=true; else in_peak=false; fi
  pause=$(would_fire_pause "$five_h" "$in_peak")
  resume=$(would_fire_resume "$five_h" "$weekly" "$in_peak")
  echo "five_h=${five_h}% weekly=${weekly}% mtime_age=${age} in_peak=${in_peak} would_fire_pause=${pause} would_fire_resume=${resume}"
  exit 0
fi
```

Apply via Edit to existing script (do NOT rewrite whole file — preserve arg parsing + cache resolution + jq check from Step 1.1).

- [ ] **Step 1.7: Run tests — expect all pass**

Run: `bin/probe-glm-quota-watch.sh`
Expected: All `✓`, final line `== results: pass=11 fail=0 ==`, exit 0.

If any fail: read the actual vs expected, fix the helper, re-run. Do NOT proceed until clean.

- [ ] **Step 1.8: Commit (cc-vendor-bridge repo for tests + fixtures, ~/.claude repo for script)**

```bash
# cc-vendor-bridge repo
git add bin/probe-glm-quota-watch.sh bin/fixtures/glm-cache/
git commit -m "test(glm): add probe-glm-quota-watch.sh with cache fixtures

Drives glm-quota-watch.sh --probe-once across healthy / token-hot /
weekly-blocked / zero cache states + peak window boundary cases."

# ~/.claude repo
git -C ~/.claude add scripts/glm-quota-watch.sh
git -C ~/.claude commit -m "feat(glm-monitor): add glm-quota-watch.sh probe-once mode

Parses ~/.claude/cache/vendor-glm-*.json for 5h + weekly tokens %,
checks CN peak window [13:55, 18:05], computes pause/resume decision.
Probe-once flag returns structured one-liner for tests + manual debug."
```

---

### Task 2: Wrap probe-once in poll loop with cache staleness guard + safety timeout

**Files:**
- Modify: `~/.claude/scripts/glm-quota-watch.sh`

**Interfaces:**
- Consumes: Task 1's probe-once helpers (`read_5h_pct`, `read_weekly_pct`, `read_mtime_age`, `current_cn_hhmm`, `in_peak_window`, `would_fire_pause`, `would_fire_resume`)
- Produces: poll-loop body — exit 0 on threshold cross, exit 2 on safety timeout, exit 3 on cache abort

- [ ] **Step 2.1: Replace the "poll loop not implemented" stub with real loop**

Edit `~/.claude/scripts/glm-quota-watch.sh` — replace the final 2 lines (`echo ... not implemented` + `exit 3`) with:

```bash
deadline=$(( $(date +%s) + MAX_MINUTES * 60 ))

while true; do
  age=$(read_mtime_age)
  if (( age > STALE_ABORT_MIN * 60 )); then
    echo "glm-quota-watch: cache stale (mtime ${age}s old > ${STALE_ABORT_MIN}min) — abort${SESSION_ID:+ [sid=${SESSION_ID}]}" >&2
    exit 3
  fi
  if (( age > STALE_WARN_MIN * 60 )); then
    echo "glm-quota-watch: cache mtime ${age}s old (> ${STALE_WARN_MIN}min) — chrome ext may be stalled${SESSION_ID:+ [sid=${SESSION_ID}]}" >&2
  fi

  five_h=$(read_5h_pct)
  weekly=$(read_weekly_pct)
  now_cn=$(current_cn_hhmm)
  if in_peak_window "$now_cn"; then in_peak=true; else in_peak=false; fi

  hit=0
  if [ "$DIRECTION" = "below" ]; then
    [ "$(would_fire_resume "$five_h" "$weekly" "$in_peak")" = "true" ] && hit=1
  else
    [ "$(would_fire_pause "$five_h" "$in_peak")" = "true" ] && hit=1
  fi

  if (( hit )); then
    if [ "$DIRECTION" = "below" ]; then
      echo "GLM-QUOTA-WATCH resume tripped: 5h=${five_h}% weekly=${weekly}% in_peak=${in_peak} at $(date +%H:%M:%S) CN=${now_cn}${SESSION_ID:+ [sid=${SESSION_ID}]}"
      echo "ACTION: invoke /glm-workflow-monitor resume — 5h recovered, weekly OK, off-peak"
    else
      reason=""
      (( five_h >= THRESHOLD )) && reason="5h=${five_h}%>=${THRESHOLD}"
      [ "$in_peak" = "true" ] && reason="${reason:+$reason+}peak[${PEAK_START_CN}-${PEAK_END_CN}]@${now_cn}"
      echo "GLM-QUOTA-WATCH pause tripped: ${reason} weekly=${weekly}% at $(date +%H:%M:%S)${SESSION_ID:+ [sid=${SESSION_ID}]}"
      echo "ACTION: invoke /glm-workflow-monitor pause — stop the guarded workflow now"
    fi
    exit 0
  fi

  if (( $(date +%s) >= deadline )); then
    echo "glm-quota-watch safety-timeout after ${MAX_MINUTES}min (5h=${five_h}% weekly=${weekly}% in_peak=${in_peak}, dir=${DIRECTION})${SESSION_ID:+ [sid=${SESSION_ID}]}, exiting"
    exit 2
  fi

  sleep "$POLL"
done
```

- [ ] **Step 2.2: Syntax sanity**

Run: `bash -n ~/.claude/scripts/glm-quota-watch.sh; echo "exit=$?"`
Expected: `exit=0` (no syntax errors).

- [ ] **Step 2.3: Smoke test poll loop with real cache, 2s poll, 1min safety timeout, NOW_CN override**

Test pause direction (off-peak, healthy cache should not fire):

```bash
NOW_CN="10:00" timeout 6 ~/.claude/scripts/glm-quota-watch.sh 85 2 1 above smoke-test
echo "exit=$?"
```
Expected: stderr quiet (cache fresh, no warn), no stdout (no fire), `exit=124` (`timeout` killed it before safety timeout) OR `exit=2` (safety timeout if test runs > 1min).

Test pause direction (peak override, should fire instantly):

```bash
NOW_CN="14:30" ~/.claude/scripts/glm-quota-watch.sh 85 2 1 above smoke-test
echo "exit=$?"
```
Expected: stdout has `GLM-QUOTA-WATCH pause tripped: peak[13:55-18:05]@14:30 ...`, `exit=0`.

Test resume direction (healthy off-peak should fire):

```bash
NOW_CN="10:00" ~/.claude/scripts/glm-quota-watch.sh 60 2 1 below smoke-test
echo "exit=$?"
```
Expected: stdout has `GLM-QUOTA-WATCH resume tripped: 5h=<n>% weekly=<n>% in_peak=false ...`, `exit=0`.

Test cache stale abort:

```bash
TMP=$(mktemp /tmp/glm-stale.XXXX.json)
cp ~/.claude/cache/vendor-glm-*.json "$TMP"
touch -t 202501010000 "$TMP"
CACHE_FILE="$TMP" ~/.claude/scripts/glm-quota-watch.sh 85 2 1 above smoke-test
echo "exit=$?"
rm -f "$TMP"
```
Expected: stderr "cache stale (mtime ...) — abort", `exit=3`.

- [ ] **Step 2.4: Commit**

```bash
git -C ~/.claude add scripts/glm-quota-watch.sh
git -C ~/.claude commit -m "feat(glm-monitor): wrap probe-once in poll loop

Cache staleness guard (warn>5min, abort>15min), safety timeout exit 2,
fires on direction-aware threshold cross with informative reason."
```

---

### Task 3: Create `/glm-workflow-monitor` slash command markdown

**Files:**
- Create: `~/.claude/commands/glm-workflow-monitor.md`

**Interfaces:**
- Consumes: `glm-quota-watch.sh` (Task 1+2), `~/.claude/scripts/resume-workflow-with-injected-args.sh` (existing from `/workflow-monitor`)
- Produces: slash command surface user invokes; hook (Task 4) routes to this command name

- [ ] **Step 3.1: Write command file as lean fork of bruce-workflow-monitor.md**

Create `~/.claude/commands/glm-workflow-monitor.md` with these sections (full content below). The file is long but mostly direct adaptation of `bruce-workflow-monitor.md` — swap `bruce` → `glm`, swap metric source, swap thresholds.

```markdown
---
description: Watch, pause, and resume any background Workflow running under ccp-glm so a long run survives z.ai 5h token cap + CN peak window 3× burn without re-spending tokens. Watch mode auto-guards a running workflow (background poll of ~/.claude/cache/vendor-glm-*.json, wakes the session to pause when 5h ≥ 85% OR CN time entering peak window 13:55-18:05); resume fires automatically when 5h ≤ 60% AND weekly < 95% AND off-peak. Use when launching a long workflow under ccp-glm. Sibling of /workflow-monitor (Anthropic 5h OAuth) and /bruce-workflow-monitor (Bruce pool health).
---

# /glm-workflow-monitor — watch · pause · resume GLM-backed Workflows

Fork of `/workflow-monitor` that swaps the metric source from CC's 5h OAuth quota cache to z.ai's cc-quota-fetcher cache (`~/.claude/cache/vendor-glm-*.json`) plus a CN peak-window time guard. All Workflow tool pause/resume mechanics (TaskStop / `Workflow({scriptPath, resumeFromRunId})` / GOLDEN snapshot / inject-and-resume helper / per-session isolation) are identical — see `/workflow-monitor` for the underlying logic notes and 踩過的坑. This file documents only the glm-specific divergences + full step body for execution.

`$ARGUMENTS`:
- `watch` — guard a just-launched workflow: spawn background quota-watch that wakes session to pause when 5h ≥ 85% or CN time enters [13:55, 18:05].
- `pause` — stop the guarded/running workflow now, save resume state.
- `resume` — continue suspended workflow from cache.
- a `wf_...` runId — target that specific run.
- empty → **auto**: suspend state exists → resume; watching state exists → pause; else → pause.

---

## When this fires vs /workflow-monitor

| Hook situation | Behavior |
|---|---|
| Vendor session = glm (`CC_VENDOR=glm`) | PostToolUse(Workflow) hook routes to `/glm-workflow-monitor watch` |
| Vendor session = bruce | `/bruce-workflow-monitor watch` |
| Vendor session = other | Hook silent |
| No vendor session | `/workflow-monitor watch` (Anthropic 5h OAuth) |

Meant to be invoked **only** from a ccp-glm session. z.ai single-key, single profile per Lite-Monthly subscription — cache is one file `vendor-glm-<profile_id>.json`. Default thresholds tuned to user pact 2026-06-22 (pause≥85, resume≤60, weekly cap 95, peak [13:55, 18:05] CN; trial-tunable).

---

## Mechanism (Workflow tool side identical to /workflow-monitor)

A Workflow runs as a background task and journals to `~/.claude/projects/<proj>/<session>/workflows/wf_<runId>.json`. `Workflow({scriptPath, resumeFromRunId})` replays from that journal the longest **deterministic prefix** of `agent()` calls whose (prompt, opts) reproduce **byte-identical** on re-execution — those return **instantly, zero LLM tokens**; from the first agent whose prompt differs, everything re-runs live.

> ⚠️ **Resume only saves tokens to the extent the workflow is DETERMINISTIC** — same caveat as /workflow-monitor. Nondeterministic agent prompts (mutable counters, no-barrier pipeline races, unsorted dedup) → cache miss → re-run from divergence on. For non-deterministic workflows under ccp-glm, pause→resume ≈ full re-run; the win is just "survive the dip without 429 or peak 3× burn", not "save tokens".

> ⚠️ **Resume re-runs script body from the top — original `args` MUST be re-passed byte-identical** — same caveat as /workflow-monitor. Use the inject-and-resume helper (Step 3.4), don't manually re-pass args.

| Stage | journal file | journal `status` | transcript dir |
|---|---|---|---|
| **running** | **absent** | — | present |
| **after TaskStop** | present | `killed` | present |
| **completed** | present | `completed` | present |

Two bridges:
- **Quota source** = local file read of `~/.claude/cache/vendor-glm-<profile>.json` (cc-quota-fetcher chrome ext pushes via native messaging host). 0 token cost. Polled every 30s by `glm-quota-watch.sh`. Cache mtime > 5 min → warn; > 15 min → watch abort (chrome ext / receiver runtime副本 possibly broken).
- **Background bash exit → re-invokes the main session** — same wake-bridge as /workflow-monitor. Only `Bash(run_in_background=true)` launched FROM the main session has this bridge.

---

## Step 0 — show current quota + peak status (best-effort, never block)

```bash
shopt -s nullglob 2>/dev/null || true
for f in ~/.claude/cache/vendor-glm-*.json; do
  jq -r '
    .data as $d
    | ($d.limits | map(select(.type=="TOKENS_LIMIT" and (.unit==3 and .number==5))) | first.percentage // 0) as $five_h
    | ($d.limits | map(select(.type=="TOKENS_LIMIT" and (.unit==6 and .number==1))) | first.percentage // 0) as $weekly
    | ($d.limits | map(select(.type=="TIME_LIMIT"   and (.unit==5 and .number==1))) | first.percentage // 0) as $mcp
    | "tier=\($d.level) | 5h=\($five_h)% | weekly=\($weekly)% | monthly MCP=\($mcp)% | cache=\(input_filename)"
  ' "$f"
done
CN=$(TZ=Asia/Shanghai date +%H:%M)
PEAK="false"; [[ "$CN" > "13:54" && "$CN" < "18:06" ]] && PEAK="true"
echo "CN time = $CN | in_peak[13:55-18:05] = $PEAK"
```

---

## Step 0a — resolve SESSION_ID (per-session isolation)

State files and watch processes are per-session. Pull the current session id from the launch result's `Transcript dir:` line (path shape `~/.claude/projects/<proj>/<SESSION_ID>/...`):

```bash
SESSION_ID="<extract from Transcript dir — the dir name two levels up from /subagents/>"
STATE_FILE="$HOME/.claude/glm-workflow-monitor-state-${SESSION_ID}.json"
ARGS_FILE="$HOME/.claude/glm-workflow-monitor-args-${SESSION_ID}.json"
```

If SESSION_ID can't be resolved, fall back to single-session paths `~/.claude/glm-workflow-monitor-state.json` / `glm-workflow-monitor-args.json`. Never `pkill -f` watch processes; always `kill <pid>` a recorded PID or `pgrep -af glm-quota-watch.sh | grep $SESSION_ID` to filter.

State-file namespaces distinct from `/workflow-monitor` and `/bruce-workflow-monitor` (`glm-workflow-monitor-state-*` vs `workflow-monitor-state-*` vs `bruce-workflow-monitor-state-*`) so all three can coexist.

---

## Step 1 — pick mode

1. `$ARGUMENTS` forces `watch`/`pause`/`resume`/a runId → honor it.
2. Else read `$STATE_FILE` if present:
   - `phase=suspended` → **RESUME** (Step 3)
   - `phase=watching` → **PAUSE** (Step 2)
3. Else → **PAUSE** (Step 2).

---

## Step W — WATCH (guard a running workflow)

> **Always arm — no judgement.** Arm watch on every background workflow launch under ccp-glm. Cost ≈ one idle background poll (no token cost); cost of NOT arming (5h撞滿 429 / peak 期間 3× 燒爆) is large and asymmetric.

1. Identify the workflow from the **launch result in context** (`Task ID:`, `Run ID: wf_...`, `Script file:`, `Transcript dir:`). Resolve SESSION_ID per Step 0a.

2. **Avoid duplicates (session-scoped):**

   ```bash
   pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" >/dev/null && echo "glm watch already running for this session — skip" && exit 0 || true
   ```

3. Record what we're guarding (`phase=watching`):

   ```bash
   cat > "$STATE_FILE" <<EOF
   {"phase":"watching","runId":"<runId>","taskId":"<task_id>","scriptPath":"<scriptPath>","sessionDir":"<...workflows dir>","sessionId":"${SESSION_ID}","pauseAt5h":85,"resumeAt5h":60,"weeklyCeil":95,"peakStartCN":"13:55","peakEndCN":"18:05"}
   EOF
   ```

4. Launch the watch as a **main-session background bash** (wake bridge). Direction `above` 85 = pause trigger; pass SESSION_ID as 5th arg for ps-visible filtering:

   ```
   Bash(run_in_background=true): bash ~/.claude/scripts/glm-quota-watch.sh 85 30 360 above "${SESSION_ID}"
   ```

5. Return to waiting. Two wake-ups possible:
   - **quota-watch completes** with `GLM-QUOTA-WATCH pause tripped … ACTION: invoke /glm-workflow-monitor pause` → immediately invoke `/glm-workflow-monitor pause`.
   - **the workflow completes first** → kill **only this session's** watch and clear state:

     ```bash
     # session-scoped kill with VERIFICATION (TERM → check → KILL → loud fail)
     # NEVER pkill -f. NEVER awk '{print $1}' (CC harness rewrites $1 — see /workflow-monitor 踩過的坑).
     pids=$(pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" | cut -d' ' -f1)
     if [ -n "$pids" ]; then
       kill $pids 2>/dev/null; sleep 0.5
       still=$(pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" | cut -d' ' -f1)
       [ -n "$still" ] && kill -9 $still 2>/dev/null && sleep 0.3
     fi
     if pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" >/dev/null; then
       echo "❌ glm watch for $SESSION_ID STILL ALIVE after kill+kill-9 — run: ps aux | grep glm-quota-watch"
     else
       rm -f "$STATE_FILE" "$ARGS_FILE"
       echo "✅ workflow done; this-session glm watch stopped"
     fi
     ```

     走到這條 = workflow 自然跑完，watch 任務結束——不要繼續走 pause/resume。

---

## Step 2 — PAUSE

1. **task_id**: prefer `taskId` from the `watching` state file. Fallback: launch result in context.
2. Stop it: `TaskStop({task_id: "<task_id>"})`
3. Wait ~8s, confirm it froze. (TaskStop lags — queued agents finish first; they still cache.)
4. Read back the killed journal and capture original args:

   ```bash
   shopt -s nullglob 2>/dev/null || setopt null_glob 2>/dev/null || true
   J=$(ls -t ~/.claude/projects/*/${SESSION_ID}/workflows/wf_*.json 2>/dev/null | head -1)
   jq -r '"runId=\(.runId) status=\(.status) scriptPath=\(.scriptPath) argsType=\(.args|type)"' "$J"
   jq '.args' "$J" > "$ARGS_FILE"
   ```

   Expect `status=killed`.

5. **GOLDEN snapshot** (immutable base for fork-from-GOLDEN restore — load-bearing safety mechanism, MUST happen BEFORE any resume attempt):

   ```bash
   SD=$(dirname "$J" | sed 's|/workflows$|/subagents/workflows|')/wf_<runId>
   cp "$J" "$J.GOLDEN"
   [[ ! -d "${SD}.GOLDEN" ]] && cp -r "$SD" "${SD}.GOLDEN"
   echo "GOLDEN: $J.GOLDEN + ${SD}.GOLDEN ($(ls "${SD}.GOLDEN" | wc -l) entries)"
   ```

6. Flip state to `suspended` (kill any lingering pause-direction watch for this session first, with verification):

   ```bash
   pids=$(pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" | cut -d' ' -f1)
   if [ -n "$pids" ]; then
     kill $pids 2>/dev/null; sleep 0.5
     still=$(pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" | cut -d' ' -f1)
     [ -n "$still" ] && kill -9 $still 2>/dev/null && sleep 0.3
   fi
   pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" >/dev/null && \
     echo "⚠️ lingering glm watch for $SESSION_ID — investigate before flipping to suspended"
   cat > "$STATE_FILE" <<EOF
   {"phase":"suspended","runId":"<runId>","scriptPath":"<scriptPath>","sessionDir":"<...workflows dir>","sessionId":"${SESSION_ID}","argsFile":"${ARGS_FILE}","pausedNote":"<why, e.g. 5h hit 87% / entered peak / both>"}
   EOF
   ```

7. **Arm auto-resume** — launch a reverse watch (direction `below` 60 = resume trigger):

   ```
   Bash(run_in_background=true): bash ~/.claude/scripts/glm-quota-watch.sh 60 30 360 below "${SESSION_ID}"
   ```

   It exits when 5h ≤ 60 AND weekly < 95 AND off-peak, and prints `ACTION: invoke /glm-workflow-monitor resume`. When that wakes you, do exactly that (Step 3).

8. Tell the user: paused `<runId>` (reason: <5h N%, peak, both>); auto-resume armed (continues automatically when 5h ≤ 60% & weekly < 95% & off-peak). Keep CC open. Manual resume via `/glm-workflow-monitor` anytime.

---

## Step 3 — RESUME

(Triggered manually, OR automatically when reverse watch wakes you with `ACTION: invoke /glm-workflow-monitor resume`.)

⚠️ **DO NOT manually re-pass args** — main session LLM cannot achieve byte-identical args reproduction (unicode normalization at cognitive layer — see /workflow-monitor 踩過的坑 for F8 case). Use the inject-and-resume helper instead.

1. Kill the reverse watch — it did its job (session-scoped only):

   ```bash
   pids=$(pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" | cut -d' ' -f1)
   if [ -n "$pids" ]; then
     kill $pids 2>/dev/null; sleep 0.5
     still=$(pgrep -lf glm-quota-watch.sh | grep -F "${SESSION_ID}" | cut -d' ' -f1)
     [ -n "$still" ] && kill -9 $still 2>/dev/null && sleep 0.3
   fi
   ```

2. Read `$STATE_FILE` → `runId`, `scriptPath`, `sessionDir`, `argsFile`.

3. **Same-session guard:** if current session's project dir differs from `sessionDir`, STOP → cross-session fallback below.

4. **Run the inject helper** (replaces broken "manually re-pass args" path):

   ```bash
   ~/.claude/scripts/resume-workflow-with-injected-args.sh \
     ~/.claude/workflows/<original-workflow-name>.js \
     "$ARGS_FILE" \
     /tmp/<workflow-name>-injected.js
   ```

5. **Resume with the injected script — DO NOT pass args**:

   ```
   Workflow({scriptPath: "/tmp/<workflow-name>-injected.js", resumeFromRunId: "<runId>"})
   ```

6. **If resume fails (cache miss / runtime rejects injected script)** — fork-from-GOLDEN and retry:

   ```bash
   cp "$J.GOLDEN" "$J"
   rm -rf "$SD" && cp -r "${SD}.GOLDEN" "$SD"
   echo "restored to clean GOLDEN state — safe to retry or abandon resume"
   ```

7. **Re-arm:** resuming itself is a `Workflow` call → PostToolUse hook fires again → routes back to `/glm-workflow-monitor watch` (because CC_VENDOR=glm in ccp-glm session). Full loop (watch→pause→reverse-watch→inject→resume→watch…) continues across multiple dips untouched.

8. On completion, report token spend. Clear this session's state including GOLDEN (only after success):

   ```bash
   rm -f "$STATE_FILE" "$ARGS_FILE"
   rm -f "$J.GOLDEN"
   rm -rf "${SD}.GOLDEN"
   rm -f /tmp/<workflow-name>-injected.js
   ```

---

## Cross-session fallback (original session gone)

`resumeFromRunId` won't rehydrate in a new session even though the journal is on disk. Best first:
1. **Per-unit workflows**: completed units already persisted as output files — start the next unit fresh.
2. **Manual aggregation rescue** (preferred when workflow reached verify stage): see `[[reference_workflow_jsonl_cache_rescue_pattern]]` (F8 case template).
3. **Last resort:** hand-author a continuation script.

Same as /workflow-monitor — no glm-specific divergence.

---

## When NOT to attempt resume (decision tree)

Same heuristic as /workflow-monitor — pick by phase reached:

| agents journaled | likely phase | preferred action |
|---|---|---|
| < 10 | scope / early search | start fresh run |
| 10-30 | search → fetch | inject-and-resume worth it |
| > 30, verify happening | verify phase | inject-and-resume → cache-hits heavy phases |
| > 75, verify mostly done, synth pending | manual aggregation rescue beats resume |

---

## GLM-specific 踩過的坑 (additions beyond /workflow-monitor)

- **Cache is pushed by chrome extension, not CC itself** — `~/.claude/cache/vendor-glm-*.json` is written by cc-quota-fetcher native messaging host (separate from CC's anthropic quota cache). If chrome is closed / extension disabled / receiver runtime 副本 (`~/.claude/scripts/cc-quota-fetcher-host/quota-receiver.py`) not deployed, cache freezes. `glm-quota-watch.sh` self-aborts when mtime > 15 min (configurable via STALE_ABORT_MIN env). See `[[reference_z_ai_glm_widget_integration_2026_06_19]]` for receiver runtime-deploy parity踩坑.
- **5h vs weekly limit selection is by `(type, unit, number)` tuple**, with fallback by `nextResetTime` window. Z.ai changing unit編號 doesn't silently break watch — but you'll see weekly read as 0 if neither tuple nor fallback window matches. Run probe-once if numbers look wrong.
- **Lite/Pro/Max tier not hard-coded** — `data.level` carries it, but `glm-quota-watch.sh` only uses percentage so tier swap is transparent.
- **Single-key vendor** — z.ai one ZAI_API_KEY, cache file is one `vendor-glm-<profile_id>.json`. No multi-account glob like /workflow-monitor's `quota-*.json` over multiple anthropic accounts.
- **Peak window inclusive boundary** — 13:55:00 起算、18:05:59 截止. Done via HH:MM string compare (zero-padded monotonic). Z.ai's actual 14:00/18:00 倍率 switch atomicity unverified — the 5-min buffer is a guess; if peak entry burns hotter than expected, narrow it.
- **TZ hard-coded Asia/Shanghai** — never inherits local TZ. User can cross-timezone travel without watch misfiring.
- **Weekly second-ceiling is resume cap** — 5h pretty but weekly ≥ 95% still blocks resume. Avoids resuming straight into weekly 429.
- **Pause uses OR / resume uses AND** — pause任一條成立 fire、resume 三條都成立 fire. Asymmetric on purpose (statistic hysteresis): peak guard + 5h threshold both pause, but resume requires recovery on all dimensions.
- **Trial-tunable thresholds** — 85/60/95 are 試水溫 values 2026-06-22. After 1 week of trial observation, expect 5h pause to revise based on observed burn rate vs hard rate-limit distance. Trial entry tracked in `~/Desktop/projects/.claude/trials/active.md`.

For Workflow tool side caveats (`task_id` capture, cache deterministic prefix, GOLDEN-must-come-first, $1 awk rewrite, kill silent-fail) — all identical to /workflow-monitor 踩過的坑; see that file. Don't duplicate them here.
```

- [ ] **Step 3.2: Sanity check the command file**

```bash
# All required sections present
for s in "Step 0" "Step 0a" "Step 1" "Step W" "Step 2" "Step 3" "踩過的坑"; do
  grep -q "$s" ~/.claude/commands/glm-workflow-monitor.md || echo "MISSING: $s"
done
# No copy-paste leftovers
grep -n "bruce" ~/.claude/commands/glm-workflow-monitor.md | grep -v "/bruce-workflow-monitor" | grep -v "Bruce pool" | grep -v "sibling of"
# No $1 awk traps (CC harness rewrite gotcha)
grep -nE "awk '\\{print \\\$1\\}'" ~/.claude/commands/glm-workflow-monitor.md && echo "FOUND awk \$1 trap — must use cut -d' ' -f1"
```
Expected: no `MISSING`, no stray `bruce` references, no `awk '{print $1}'` matches.

- [ ] **Step 3.3: Commit**

```bash
git -C ~/.claude add commands/glm-workflow-monitor.md
git -C ~/.claude commit -m "feat(glm-monitor): add /glm-workflow-monitor slash command

Lean fork of /bruce-workflow-monitor: swaps metric source to local
cc-quota-fetcher cache + adds CN peak-window guard. Shares all Workflow
tool mechanics (TaskStop / inject helper / GOLDEN snapshot) via reference
to /workflow-monitor."
```

---

### Task 4: Patch hook routing for `CC_VENDOR=glm`

**Files:**
- Modify: `~/.claude/hooks/workflow-monitor-nudge.sh`

**Interfaces:**
- Consumes: `CC_VENDOR=glm` env (set by `ccp-glm` wrapper at `shell/ccp-functions.sh:123`)
- Produces: PostToolUse(Workflow) `additionalContext` nudging main session to invoke `/glm-workflow-monitor watch`

- [ ] **Step 4.1: Write failing test harness for hook routing**

```bash
cat > /tmp/test-hook-routing.sh <<'SH'
#!/usr/bin/env bash
set -uo pipefail
HOOK="$HOME/.claude/hooks/workflow-monitor-nudge.sh"
pass=0; fail=0
assert_contains() {
  local label="$1" needle="$2" haystack="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    echo "  ✓ $label"; pass=$((pass+1))
  else
    echo "  ✗ $label"; echo "    looking for: $needle"; echo "    in: $haystack"; fail=$((fail+1))
  fi
}

# Hook reads no stdin — direct env-driven dispatch.
echo "== CC_VENDOR=glm =="
out=$(CC_VENDOR=glm "$HOOK")
assert_contains "additionalContext mentions glm-workflow-monitor" "/glm-workflow-monitor" "$out"
assert_contains "describes 5h ≥ 85% trigger" "85" "$out"
assert_contains "describes peak window" "13:55" "$out"

echo "== CC_VENDOR=bruce (regression) =="
out=$(CC_VENDOR=bruce "$HOOK")
assert_contains "still routes to bruce-workflow-monitor" "/bruce-workflow-monitor" "$out"

echo "== CC_VENDOR= (anthropic native) =="
out=$(unset CC_VENDOR; "$HOOK")
assert_contains "routes to /workflow-monitor (no slash mention required)" "5 小時用量限額" "$out"

echo "== CC_VENDOR=mimo (other vendor — silent) =="
out=$(CC_VENDOR=mimo "$HOOK")
[ -z "$out" ] && { echo "  ✓ mimo silent"; pass=$((pass+1)); } || { echo "  ✗ mimo not silent: $out"; fail=$((fail+1)); }

echo
echo "== results: pass=$pass fail=$fail =="
[ "$fail" -eq 0 ]
SH
chmod +x /tmp/test-hook-routing.sh
```

- [ ] **Step 4.2: Run test — verify it fails (glm not yet wired)**

Run: `/tmp/test-hook-routing.sh; echo "exit=$?"`
Expected: `glm` assertions fail (3 ✗), bruce + anthropic + mimo pass, `exit=1`.

- [ ] **Step 4.3: Patch the hook — add `glm)` case**

Edit `~/.claude/hooks/workflow-monitor-nudge.sh` — find this block:

```bash
  bruce)
    read -r -d '' CTX <<'EOF' || true
背景 Workflow 剛在 ccp-bruce session 啟動。...
EOF
    jq -n --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
    exit 0
    ;;
  *)
    exit 0
    ;;
```

Insert a new case between `bruce)` and `*)`:

```bash
  glm)
    read -r -d '' CTX <<'EOF' || true
背景 Workflow 剛在 ccp-glm session 啟動。一律 invoke glm-workflow-monitor skill 的 watch 模式守護它撐過 z.ai 5h token 上限 + CN peak window 倍率燒費——掛的成本極低（一個背景本地 cache 輪詢，no token cost），不掛的代價（5h 撞滿觸發 429 / peak 期間 3× 燒爆 quota）大且不對稱。它會掛 background glm-quota-watch（poll ~/.claude/cache/vendor-glm-*.json，5h ≥ 85% 或進 CN peak 13:55-18:05 自動暫停、5h ≤ 60% 且離 peak 且 weekly < 95% 自動 resume）。啟動結果裡有它需要的 Task ID / Run ID / Script file。
EOF
    jq -n --arg ctx "$CTX" '{hookSpecificOutput:{hookEventName:"PostToolUse",additionalContext:$ctx}}'
    exit 0
    ;;
```

- [ ] **Step 4.4: Re-run test — verify all pass**

Run: `/tmp/test-hook-routing.sh`
Expected: All `✓`, final line `pass=6 fail=0`, exit 0.

- [ ] **Step 4.5: Syntax sanity + commit**

```bash
bash -n ~/.claude/hooks/workflow-monitor-nudge.sh && echo "syntax OK"
git -C ~/.claude add hooks/workflow-monitor-nudge.sh
git -C ~/.claude commit -m "feat(glm-monitor): route PostToolUse(Workflow) for CC_VENDOR=glm

Adds glm) case to workflow-monitor-nudge.sh between bruce) and *).
Mirrors bruce nudge shape — describes 5h≥85% / peak / weekly<95% / resume rules
so main session knows what to expect when it invokes /glm-workflow-monitor watch.

Bruce + anthropic-native + other-vendor (silent) paths regression-tested."
rm -f /tmp/test-hook-routing.sh
```

---

### Task 5: Trial registration + smoke test in live ccp-glm session

**Files:**
- Append: `~/Desktop/projects/.claude/trials/active.md`

**Interfaces:**
- Consumes: All Task 1-4 artifacts working
- Produces: Trial entry that `trial-review.sh` hook proactively reminds user about at review date

- [ ] **Step 5.1: Append trial entry**

Append this H2 to `~/Desktop/projects/.claude/trials/active.md`:

```markdown
## /glm-workflow-monitor — 5h-85% + peak-window guard for ccp-glm Workflows (2026-06-29 review)

**Focus**: 試水溫 threshold tuning + peak-buffer width tuning
- 5h pause @ 85% / resume @ 60% / weekly ceil 95% — all 抄 anthropic、未經 glm-specific 校準
- Peak buffer 13:55/18:05 — 5min guess、實際 z.ai 14:00/18:00 倍率切換 atomicity 未驗

**Install**: `cc-vendor-bridge` + `~/.claude/` 兩 repo commits 2026-06-22

**Review 方式**: 一週後（2026-06-29）看 `~/.claude/cache/vendor-glm-*.json` 累積數據對比實際 pause/resume 觸發紀錄，調整：
1. 5h-85 是否撞牆過晚（observe distance to 429）
2. 5h-60 hysteresis 是否導致 peak 過後 stuck
3. Peak 5min buffer 是否需要縮窄

If R1 (cancel Lite-Monthly 7/16) trigger 命中 → 本 trial 同步退役、watch 留 archive 不用。
```

- [ ] **Step 5.2: Smoke test in live ccp-glm session — verify CC_VENDOR + cache + watch can be launched manually**

Open a fresh terminal:

```bash
source ~/Desktop/projects/cc-vendor-bridge/shell/ccp-functions.sh
# Verify ccp-glm function defined
type ccp-glm | head -3
# Sanity that ZAI_API_KEY present (don't print)
[ -n "$ZAI_API_KEY" ] && echo "ZAI_API_KEY present" || echo "MISSING — set in ~/.zsh_secrets"
```
Expected: `ccp-glm is a function`, `ZAI_API_KEY present`.

Probe-once against live cache:

```bash
~/.claude/scripts/glm-quota-watch.sh --probe-once 85
```
Expected: `five_h=<N>% weekly=<N>% mtime_age=<sec> in_peak=<bool> would_fire_pause=<bool> would_fire_resume=<bool>` with sensible numbers (5h % matching statusline widget).

Background poll test (5s safety timeout — should exit 2 quickly):

```bash
~/.claude/scripts/glm-quota-watch.sh 85 2 0.1 above smoke
echo "exit=$?"
```
Expected: stdout `... safety-timeout after 0.1min ...`, `exit=2`.

- [ ] **Step 5.3: Manual end-to-end check (no actual workflow run needed)**

In a new ccp-glm session (just to spawn one — no real workflow):

```bash
ccp-glm <<EOF
echo "CC_VENDOR=\$CC_VENDOR"
ls ~/.claude/commands/glm-workflow-monitor.md
EOF
```
Expected: stdout has `CC_VENDOR=glm` and the command file path exists. (This proves vendor marker propagates + slash command file is in place; real Workflow run is too expensive to smoke-test here.)

- [ ] **Step 5.4: Commit trial entry**

```bash
# active.md lives in ~/Desktop/projects/.claude/ — separate from cc-vendor-bridge
git -C ~/Desktop/projects/.claude add trials/active.md
git -C ~/Desktop/projects/.claude commit -m "trial: register glm-workflow-monitor 2026-06-29 review

Threshold values are 試水溫 (抄 anthropic), peak buffer is a guess.
1-week observation window then tune."
```

If `~/Desktop/projects/.claude/` isn't a git repo, skip git commands — append-only file update is sufficient (trial-review hook reads file regardless).

- [ ] **Step 5.5: Commit plan doc to cc-vendor-bridge**

```bash
git add docs/superpowers/plans/2026-06-22-glm-workflow-monitor.md
git commit -m "docs(plan): /glm-workflow-monitor implementation plan

5 tasks: glm-quota-watch.sh probe-once (TDD) → poll loop wrapper →
slash command markdown → hook routing → trial registration + smoke."
```

---

## Self-Review

**Spec coverage check** (cross spec §1-§7 vs plan tasks):

| Spec section | Covered by |
|---|---|
| §1 Signal source (cache file, staleness guard) | Task 1.6 (`read_mtime_age`), Task 2.1 (stale abort) |
| §2 Schema (5h tuple, weekly tuple, MCP ignored, fallback by reset window) | Task 1.6 (`read_5h_pct`, `read_weekly_pct` with reset-window fallback) |
| §3 Trigger logic (OR pause / AND resume / TZ Asia/Shanghai) | Task 1.6 (`would_fire_pause`, `would_fire_resume`, `current_cn_hhmm`, `in_peak_window`), Task 1.4 boundary tests |
| §4 State + naming (file paths) | Task 3.1 step W & step 0a (state/args file paths), Task 1.1 (script path) |
| §5 Watch script API | Task 1.1 stub + Task 2.1 final |
| §6 Hook routing | Task 4 |
| §7 Document structure (lean fork of bruce) | Task 3.1 |
| Spec "踩坑" predictions 1-8 | Task 3.1 (踩過的坑 section reproduces all 8) |

No gaps.

**Placeholder scan**: All code blocks contain real content. No "TBD" / "implement later" / "similar to Task N" anywhere.

**Type / name consistency**:
- `read_5h_pct` / `read_weekly_pct` / `read_mtime_age` / `current_cn_hhmm` / `in_peak_window` / `would_fire_pause` / `would_fire_resume` — all defined in Task 1.6, consumed in Task 2.1 poll loop. Names match exactly.
- State file schema in Task 3.1 step W and Step 2 — fields `phase` / `runId` / `taskId` / `scriptPath` / `sessionDir` / `sessionId` / `pauseAt5h` / `resumeAt5h` / `weeklyCeil` / `peakStartCN` / `peakEndCN` / `argsFile` / `pausedNote` consistent across watching → suspended phases.
- pgrep filter string `glm-quota-watch.sh` — used in Task 3.1 step W avoidance, step W cleanup, Step 2.6 cleanup, Step 3.1 reverse-watch cleanup. Consistent.
- Hook command name `/glm-workflow-monitor` — matches slash command filename `glm-workflow-monitor.md` and trial entry. Consistent.

No issues.

---

## Execution Handoff

Plan complete and saved to `docs/superpowers/plans/2026-06-22-glm-workflow-monitor.md`. Two execution options:

**1. Subagent-Driven (recommended)** — dispatch fresh subagent per task, review between tasks, fast iteration. Tasks 1+2 are bash with concrete TDD; Task 3 is a long markdown file ideal for fresh-context fidelity; Tasks 4+5 are small wiring + smoke.

**2. Inline Execution** — execute tasks in this session using executing-plans, batch with checkpoints. Trade-off: this session already has full context but is also long.

**Which approach?**
