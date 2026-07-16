#!/usr/bin/env zsh

set -u

config_path="${CLIPROXY_CONFIG_PATH:-$HOME/.cli-proxy-api/config.yaml}"

ruby -ryaml -e '
  config = YAML.load_file(ARGV.fetch(0))
  rules = config.dig("payload", "override") || []
  found = rules.any? do |rule|
    params = rule["params"] || {}
    models = rule["models"] || []
    params["service_tier"] == "priority" && models.any? do |model|
      model["name"] == "gpt-5.6-*" &&
        model["protocol"] == "codex" &&
        (model["headers"] || {})["X-CCP-Fast"] == "1"
    end
  end
  abort("missing header-scoped GPT-5.6 priority payload rule") unless found
  puts("ok - header-scoped GPT-5.6 priority payload rule")
' "$config_path"
