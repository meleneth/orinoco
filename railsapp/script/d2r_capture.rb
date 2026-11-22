# frozen_string_literal: true

require "json"

config_path = ENV.fetch("OBS_WEBSOCKET_CONFIG_PATH", "/run/secrets/obs-websocket.json")
config = File.file?(config_path) ? JSON.parse(File.read(config_path)) : {}
host = ENV.fetch("OBS_HOST", "localhost")
port = Integer(ENV.fetch("OBS_PORT", config.fetch("server_port", 4455).to_s))
password = ENV["OBS_PASSWORD"] || config["server_password"]

runner = ObsBridge::ObswsSessionRunner.new(host:, port:, password:)
exit VisualObserver::D2r::Cli.new(
  session_runner: runner,
  output_root: Rails.root.join("tmp/d2r-captures")
).run(ARGV)
