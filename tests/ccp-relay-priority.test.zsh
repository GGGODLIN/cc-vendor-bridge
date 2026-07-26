#!/usr/bin/env zsh
# 驗 ccp-relay-priority-snapshot / -apply：模擬 --codex-login 清掉 priority 後能不能補回
set -u

SRC="${0:A:h}/../shell/ccp-functions.sh"
source "$SRC" 2>/dev/null

FAIL=0
ok()   { print "  ✅ $1" }
bad()  { print "  ❌ $1"; FAIL=1 }

setup() {
  WORK=$(mktemp -d)
  export CCP_RELAY_AUTH_DIR="$WORK"
  print '{"email":"pro@example.com","type":"codex","priority":10,"access_token":"a"}' \
    > "$WORK/codex-pro@example.com-pro.json"
  print '{"email":"team@example.com","type":"codex","priority":0,"access_token":"b"}' \
    > "$WORK/codex-deadbeef-team@example.com-team.json"
}
teardown() { rm -rf "$WORK"; unset CCP_RELAY_AUTH_DIR }

prio_of() { jq -r '.priority // "缺"' "$1" }

print "── snapshot 抓到兩個帳號"
setup
SNAP=$(ccp-relay-priority-snapshot | sort)
[[ "$SNAP" == "pro@example.com	10
team@example.com	0" ]] && ok "snapshot 正確" || bad "snapshot 不對：$SNAP"
teardown

print "── 重登清掉 priority 後補回（檔名也改了，靠 email 對上）"
setup
SNAP=$(ccp-relay-priority-snapshot)
rm "$WORK/codex-pro@example.com-pro.json"
print '{"email":"pro@example.com","type":"codex","access_token":"NEW"}' \
  > "$WORK/codex-99999999-pro@example.com-pro.json"
[[ $(prio_of "$WORK/codex-99999999-pro@example.com-pro.json") == "缺" ]] \
  && ok "前置條件：新檔沒有 priority" || bad "前置條件錯"
print -r -- "$SNAP" | ccp-relay-priority-apply >/dev/null 2>&1
[[ $(prio_of "$WORK/codex-99999999-pro@example.com-pro.json") == "10" ]] \
  && ok "priority 10 已補回新檔" || bad "沒補回：$(prio_of "$WORK/codex-99999999-pro@example.com-pro.json")"
[[ $(jq -r .access_token "$WORK/codex-99999999-pro@example.com-pro.json") == "NEW" ]] \
  && ok "新 token 沒被蓋掉" || bad "token 被破壞"
[[ $(stat -f '%Lp' "$WORK/codex-99999999-pro@example.com-pro.json") == "600" ]] \
  && ok "權限維持 600" || bad "權限變成 $(stat -f '%Lp' "$WORK/codex-99999999-pro@example.com-pro.json")"
teardown

print "── 已經正確時不動檔案"
setup
BEFORE=$(stat -f '%m' "$WORK/codex-pro@example.com-pro.json")
sleep 1
ccp-relay-priority-snapshot | ccp-relay-priority-apply >/dev/null 2>&1
AFTER=$(stat -f '%m' "$WORK/codex-pro@example.com-pro.json")
[[ "$BEFORE" == "$AFTER" ]] && ok "idempotent，未改寫" || bad "無謂改寫了檔案"
teardown

print "── 沒有 priority 欄位時 snapshot 為空"
setup
print '{"email":"x@example.com","type":"codex"}' > "$WORK/codex-x@example.com.json"
rm "$WORK"/codex-pro* "$WORK"/codex-deadbeef*
[[ -z "$(ccp-relay-priority-snapshot)" ]] && ok "空 snapshot" || bad "應為空"
teardown

print ""
(( FAIL )) && { print "有測試失敗"; exit 1 } || { print "全部通過"; exit 0 }
