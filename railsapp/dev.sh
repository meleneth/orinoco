#!/usr/bin/env bash

set -euo pipefail

CMD="${1:-}"
shift || true

run_with_env() {
  local dotenv_file="$1"
  shift

  bundle exec ruby -e '
    require "dotenv"
    require "rubygems"

    dotenv_file = ARGV.shift
    Dotenv.load(dotenv_file)

    ruby_bin =
      ENV["ORINOCO_RUBY_BIN"] ||
      begin
        windows_ruby = "c:\\Ruby40-x64\\bin\\ruby.exe"
        if Gem.win_platform? && File.exist?(windows_ruby)
          windows_ruby
        else
          Gem.ruby
        end
      end

    exec ruby_bin, *ARGV
  ' -- "$dotenv_file" "$@"
}

run_rails() {
  run_with_env ".env.dev.orinoco" "./bin/rails" "$@"
}

run_rspec() {
  local rspec_bin
  rspec_bin="$(bundle exec ruby -e 'require "rubygems"; puts Gem.bin_path("rspec-core", "rspec")')"
  run_with_env ".env.test.orinoco" "$rspec_bin" "$@"
}

run_test_migrate() {
  run_with_env ".env.test.orinoco" "./bin/rails" db:migrate "$@"
}

case "$CMD" in
"" | help | -h | --help)
  cat <<EOF
Usage: $0 <rails-command-or-shortcut> [args...]

Shortcuts:
  migrate
  tmigrate
  routes | r
  spec | sp
  bridge | obs
  woscapture | wosc
  wosbrain | wos
  wosprojection | wosp
  tailwind | tw
  server | s
  generate | g
  console | c

Examples:
  $0 migrate
  $0 tmigrate
  $0 routes
  $0 g model EnabledAffordance name:string config:jsonb scene_name:string
  $0 spec
  $0 spec spec/models/enabled_affordance_spec.rb
  $0 spec spec/models/enabled_affordance_spec.rb:17
  $0 db:migrate:status
  $0 runner "puts Rails.env"
  $0 destroy model EnabledAffordance
EOF
  ;;
tmigrate)
  run_test_migrate "$@"
  ;;
migrate)
  run_rails db:migrate "$@"
  ;;
routes | r)
  run_rails routes "$@"
  ;;
spec | sp)
  run_rspec "$@"
  ;;
bridge | obs)
  run_rails runner "ObsBridgeWorker.new.run" "$@"
  ;;
woscapture | wosc)
  run_rails runner "WosBrainCaptureWorker.new.run" "$@"
  ;;
wosbrain | wos)
  run_rails runner "WosBrainProcessorWorker.new.run" "$@"
  ;;
wosprojection | wosp)
  run_rails runner "WosBrainProjectionWorker.new.run" "$@"
  ;;
tailwind | tw)
  run_rails tailwindcss:build "$@"
  ;;
server | s)
  run_rails server -p 33230 -b 0.0.0.0 -P tmp/pids/server.foreman.development.pid "$@"
  ;;
generate | g)
  run_rails generate "$@"
  ;;
console | c)
  run_rails console "$@"
  ;;
*)
  run_rails "$CMD" "$@"
  ;;
esac
