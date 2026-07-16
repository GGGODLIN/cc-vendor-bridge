#!/usr/bin/env zsh

set -u

config_path="${CLIPROXY_CONFIG_PATH:-$HOME/.cli-proxy-api/config.yaml}"
auth_dir="${CLIPROXY_AUTH_DIR:-$HOME/.cli-proxy-api}"

ruby -rbase64 -rjson -ryaml -e '
  config = YAML.load_file(ARGV.fetch(0))
  abort("Codex session affinity is disabled") unless config.dig("routing", "session-affinity") == true

  accounts = Dir.glob(File.join(ARGV.fetch(1), "codex-*.json")).map do |path|
    data = JSON.parse(File.read(path))
    payload = data.fetch("id_token").split(".").fetch(1)
    claims = JSON.parse(Base64.urlsafe_decode64(payload.ljust((payload.length + 3) / 4 * 4, "=")))
    [claims.dig("https://api.openai.com/auth", "chatgpt_plan_type"), data["priority"]]
  end

  pro = accounts.find { |plan, _| plan == "pro" }
  team = accounts.find { |plan, _| plan == "team" }
  abort("missing Codex Pro OAuth account") unless pro
  abort("missing Codex Team OAuth account") unless team
  abort("Codex Pro priority must be 10") unless pro.fetch(1) == 10
  abort("Codex Team priority must be 0") unless team.fetch(1) == 0

  puts("ok - Codex session affinity enabled")
  puts("ok - Codex Pro is primary and Team is fallback")
' "$config_path" "$auth_dir"
