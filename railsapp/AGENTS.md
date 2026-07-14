# AGENTS.md

Guidance for AI coding agents working in this repository.

## Project Overview

This is a Ruby on Rails 8 application using PostgreSQL, Hotwire, import maps, Tailwind CSS, ViewComponent, RSpec, and a local `obsws` gem under `vendor/gems/obsws`.

The app centers on OBS/Twitch-style live production workflows:

- `app/services/obs_bridge/` contains bridge runtime, control, status, inventory, and OBS websocket integration code.
- `app/workers/obs_bridge_worker.rb` runs the OBS bridge worker.
- `app/affordances/` and `app/services/affordance*` contain affordance orchestration.
- `app/controllers/clip_show_controller.rb` and `app/views/clip_show/` provide the clip show surface.
- `app/controllers/admin/obs_bridges_controller.rb` and `app/views/admin/obs_bridges/` provide bridge admin views.

Bridges hold external context, including live OBS connections. The Rails web server should not hold live OBS connection state; it reads state from Redis or the database and sends control/events through SNS/SQS.

The SQS bit is important, because it means that we can re-target the SQS processors to arbitrary queues, which means we can put arbitrary functionality anywhere along the input path to any desired shape of output path we want.

Some of the event pipeline is currently defined in Ruby. Longer-term, dynamic pipeline configuration should live in the database.

## Event Pipeline And Bridge Conventions

The SNS/SQS topology is defined in `config/initializers/event_pipeline_config.rb`, with topic and queue names in `app/services/orinoco/messaging/names.rb`.

Current important paths:

- `orinoco.bridge.control` fans out lifecycle/control messages to bridge control queues.
- `orinoco.obs.command` delivers OBS domain commands to `orinoco.obs.command.bridge`.
- `orinoco.twitch.message.topic` delivers Twitch chat events to the Twitch message queue.

Keep this distinction intact:

- Bridge control is for lifecycle and bridge-local state, such as start, stop, refresh inventory, and capture/debug windows.
- OBS command messages are for OBS websocket work, including scene/source mutation and request/response-style calls such as screenshots.
- Pure event affordances should consume from queues and publish zero or more new events to SNS topics.

Do not add direct Rails-web-to-OBS calls. The Rails web process should publish a command or control message and let the bridge worker perform live OBS websocket work.

For request/response-style OBS commands, include metadata such as `request_id`, `reply_topic`, and domain-specific context in the command payload. The OBS bridge should publish a result event to SNS with that metadata copied through. Screenshot results should carry the base64 image data, image format, source or scene name, and capture timing metadata.

## Current Implementation Priorities

The planning notes in `TODO.md` are the best guide to current work:

- SQS bridge shape and parity with the OBS bridge
- Twitch chat bridge publishing and consuming events
- Redis-backed event capture for debugging
- pipeline visualization with Mermaid
- ClipShow configuration UI
- overlay and chat rendering work
- known event-type registry per bridge domain

The app already has the main moving parts for this shape:

- OBS bridge runtime, control, status, inventory, and websocket integration live under `app/services/obs_bridge/`
- `app/workers/obs_bridge_worker.rb` runs the long-lived bridge worker
- `app/affordances/` and `app/services/affordance*` hold affordance orchestration
- `app/controllers/admin/obs_bridges_controller.rb` and `app/views/admin/obs_bridges/` drive bridge status/configuration UI
- `app/controllers/clip_show_controller.rb` and `app/views/clip_show/` provide the clip-show surface

## Setup

Use the project scripts rather than hand-rolling setup steps:

```sh
bin/setup --skip-server
```

To reset the database during setup:

```sh
bin/setup --reset --skip-server
```

## Local Development

Start the development processes with:

```sh
bin/dev
```

`Procfile.dev` runs:

- Rails server on port `33230`
- Tailwind watcher
- OBS bridge worker

The development Procfile expects `.env.dev.orinoco` for environment-specific configuration.

The repo also includes `railsapp/dev.sh`, which is the command wrapper for running Rails commands with the right dotenv file:

- `dev.sh server` starts the Rails server on port `33230`
- `dev.sh bridge` starts the OBS bridge worker
- `dev.sh spec` runs RSpec with `.env.test.orinoco`
- `dev.sh` without arguments prints the shortcut list

On Windows, use the `dev.sh` shortcuts instead of relying on the shell wrappers that assume a Unix-like environment.

## Validation

Run the full project CI with:

```sh
bin/ci
```

CI currently runs setup, RuboCop, bundler-audit, importmap audit, and Brakeman.

For focused checks:

```sh
bundle exec rspec
bundle exec rspec spec/path/to/file_spec.rb
bin/rubocop
bin/brakeman --quiet --no-pager --exit-on-warn --exit-on-error
bin/bundler-audit
bin/importmap audit
```

## Coding Conventions

- Follow standard Rails conventions and the existing file layout.
- Prefer existing service objects and bridge abstractions over adding parallel control paths.
- Keep OBS bridge changes covered by focused specs in `spec/services/obs_bridge/`.
- Keep request/controller behavior covered by request specs in `spec/requests/`.
- Keep model behavior covered by model specs in `spec/models/`.
- Use ViewComponent patterns already present in `app/components/` when adding reusable UI.
- Avoid committing generated files from `log/`, `tmp/`, `storage/`, or `coverage/`.

## Frontend Notes

- This app uses Tailwind via `tailwindcss-rails`.
- Main Tailwind source: `app/assets/tailwind/application.css`.
- Built Tailwind output lives in `app/assets/builds/tailwind.css`.
- JavaScript is managed through import maps and Stimulus controllers in `app/javascript/controllers/`.

## Test Data And External Services

- Specs should use fakes and local helpers where available, such as `spec/support/fake_sqs_client.rb`.
- Do not require live AWS, OBS, Redis, or Twitch services for unit-level specs.
- Keep network-dependent behavior behind adapters or clients that can be stubbed in tests.

## Repository Hygiene

- Before editing, check for existing user changes and preserve them.
- Do not rewrite unrelated files or perform broad refactors unless the task calls for it.
- Prefer small, focused changes with matching tests.
- If a command needs secrets or live external services, document the limitation instead of guessing.
