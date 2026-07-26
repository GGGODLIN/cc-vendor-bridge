#!/usr/bin/env zsh
# 用合成 JSON 驗 ccp-gpt-whoami 的分類邏輯（避開真實 relay 狀態）
set -u

SRC=/Users/linhancheng/Desktop/projects/cc-vendor-bridge/shell/ccp-functions.sh

run_case() {
  local name="$1" json="$2"
  print "── $name"
  MOCK_JSON="$json" zsh -c "
    source $SRC 2>/dev/null
    ccp-gpt-whoami() {
      local mgmt_json=\"\$MOCK_JSON\"
      $(sed -n '/^  local rows$/,/^  return 0$/p' "$SRC")
    }
    ccp-gpt-whoami
    print \"  exit=\$?\"
  " 2>&1 | sed 's/^/  /'
  print ""
}

mk() {
  # mk <email> <plan> <priority> <recent_success> <recent_failed> <cum_success> <cum_failed>
  print -n "{\"provider\":\"codex\",\"name\":\"codex-$1.json\",\"email\":\"$1\",\"id_token\":{\"plan_type\":\"$2\"},\"priority\":$3,\"disabled\":false,\"recent_requests\":[{\"time\":\"a\",\"success\":$4,\"failed\":$5}],\"success\":$6,\"failed\":$7,\"modtime\":\"2026-07-26T21:02:33.1+08:00\"}"
}

run_case "情境1 Pro 額度冷卻（無近期流量、累計健康），team 正在服務" \
  "{\"files\":[$(mk qwe70301@gmail.com pro 10 0 0 5000 3),$(mk philip@akohub.com team 0 150 2 500 16)]}"

run_case "情境2 Pro 憑證壞掉（近期全失敗）" \
  "{\"files\":[$(mk qwe70301@gmail.com pro 10 1 7 1 35),$(mk philip@akohub.com team 0 152 4 507 16)]}"

run_case "情境3 兩邊都沒近期流量（剛重啟 relay）" \
  "{\"files\":[$(mk qwe70301@gmail.com pro 10 0 0 0 0),$(mk philip@akohub.com team 0 0 0 0 0)]}"

run_case "情境4 兩邊都壞" \
  "{\"files\":[$(mk qwe70301@gmail.com pro 10 0 9 0 30),$(mk philip@akohub.com team 0 0 5 2 40)]}"

run_case "情境5 Pro 健康正在服務（重登成功後的樣子）" \
  "{\"files\":[$(mk qwe70301@gmail.com pro 10 200 1 5200 4),$(mk philip@akohub.com team 0 0 0 507 16)]}"
