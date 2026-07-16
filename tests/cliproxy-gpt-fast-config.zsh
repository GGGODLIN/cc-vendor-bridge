#!/usr/bin/env zsh

set -u

config_path="${CLIPROXY_CONFIG_PATH:-$HOME/.cli-proxy-api/config.yaml}"

ruby -ryaml -e '
  config = YAML.load_file(ARGV.fetch(0))
  rules = config.dig("payload", "override") || []
  header_rule = rules.any? do |rule|
    params = rule["params"] || {}
    models = rule["models"] || []
    params["service_tier"] == "priority" && models.any? do |model|
      model["name"] == "gpt-5.6-*" &&
        model["protocol"] == "codex" &&
      (model["headers"] || {})["X-CCP-Fast"] == "1"
    end
  end
  alias_rule = rules.any? do |rule|
    params = rule["params"] || {}
    models = rule["models"] || []
    params["service_tier"] == "priority" && models.any? do |model|
      model["name"] == "gpt-5.6-*-fast" && model["protocol"] == "codex"
    end
  end
  aliases = config.dig("oauth-model-alias", "codex") || []
  expected_aliases = {
    "gpt-5.6-sol-fast" => "gpt-5.6-sol",
    "gpt-5.6-terra-fast" => "gpt-5.6-terra",
    "gpt-5.6-luna-fast" => "gpt-5.6-luna"
  }
  aliases_ok = expected_aliases.all? do |alias_name, upstream_name|
    aliases.any? do |entry|
      entry["alias"] == alias_name &&
        entry["name"] == upstream_name &&
        entry["fork"] == true
    end
  end
  abort("missing header-scoped GPT-5.6 priority payload rule") unless header_rule
  abort("missing Fast model-alias priority payload rule") unless alias_rule
  abort("missing GPT-5.6 Fast OAuth model aliases") unless aliases_ok
  puts("ok - header-scoped GPT-5.6 priority payload rule")
  puts("ok - Fast model-alias priority payload rule")
  puts("ok - GPT-5.6 Fast OAuth model aliases")
' "$config_path"
