# AGENTS.md

Guidance for AI coding agents working in the root of this repository.

## Repository Shape

This repo is a split workspace:

- The root owns Docker Compose orchestration, environment files, and helper scripts.
- `railsapp/` owns the Rails application code and app-local agent guidance.

When working on boot, dev, test, or deployment flows, start from the root-level wrappers and compose files before changing anything inside `railsapp/`.

## Product Direction

The top-level docs describe the intended shape of the system:

- `README.md` is the high-level architecture and workflow overview.
- `DESIGN.md` explains the event-driven stack: OBS websocket, Twitch API, SNS/SQS, GoAWS, and Rails/Hotwire.
- `TODO.md` tracks the actual near-term priorities and completed work.

The core model is:

- events over direct calls
- bridges translate external systems into the pipeline
- affordances decide behavior
- Redis projections feed the UI
- Rails renders both the control UI and browser-source style overlays

## Event Pipeline Conventions

The SNS/SQS event pipeline is the integration boundary between services. Prefer publishing events and commands through the pipeline over direct in-process calls between long-lived services.

Use the existing distinction consistently:

- Control messages manage bridge lifecycle and bridge-local state, such as enable, disable, refresh, and debug/event capture windows.
- Command messages ask a bridge to do domain work, such as forwarding an OBS websocket request or asking OBS for a screenshot.
- Result events should be published back onto SNS rather than returned synchronously through the original request path.

For request/response-style bridge work, include correlation metadata in the command payload. At minimum, use a request id and an explicit reply topic or named result topic. The bridge should publish the result event with the same correlation metadata so downstream services can route or store it without holding a live bridge connection.

OBS scene screenshots belong on the OBS command path, not the bridge control path. A screenshot command should ask the OBS bridge to capture the active scene or named source, then publish a base64 image result event to the requested SNS topic or configured result topic.

## Compose System

The root contains the compose wrappers and environment files. Treat those as the source of truth for how the stack boots:

- `dc_dev`, `dc_prod`, and `dc_test` are thin wrappers around `docker compose`.
- Each wrapper selects a different compose stack and env file:
  - `dc_dev` -> `development-compose.yml` + `development-overrides.yml` + `development.env`
  - `dc_prod` -> `production-compose.yml` + `production-overrides.yml` + `production.env`
  - `dc_test` -> `test-compose.yml` + `test-overrides.yml` + `test.env`
- The wrappers inject `HOST_UID` and `HOST_GID` on non-Windows shells so bind-mounted files stay writable by the host user.
- `create_dirs.sh` builds the `data/` directory tree used by the compose volumes.

The service layout is layered:

- Development composes `orinoco-db`, `railsapp`, `goaws`, and `redis`.
- Development overrides publish the service ports and wire `railsapp` and `obs-bridge-worker` to the DB healthcheck.
- Production adds `orinoco-db-cache`, `orinoco-db-cable`, and `orinoco-db-queue`, then points `railsapp` at the extra database URLs.
- Test keeps a smaller stack, mounts `ORINOCO_TEST_SOURCE_PATH:/rails`, and uses `railsapp.yml` plus `test-overrides.yml` for its runtime settings.
- The test stack still re-includes `railsapp.yml` in the base/override split, and `redis.yml` now uses `test.env` so the Redis publish port stays aligned with the rest of the test config. Do not assume the filenames imply a perfectly symmetric setup.

For compose inspection, prefer the wrapper scripts or the equivalent `docker compose --env-file ... -f ...` invocation over reconstructing the stack manually.

## Root Development Flow

`DEVSETUP.md` reflects the current docker-first bootstrap path:

```sh
./dc_dev up -d
cd railsapp
./bin/dev
```

On Windows, prefer the Rails-side `dev.sh` shortcuts rather than the shell wrappers that assume a Unix-like environment.

For this repo's Windows/MSYS agent environment, also read `MSYS_AGENTS.md` before running tools. It captures the PowerShell-vs-bash command split, Docker/test-stack expectations, and the sandbox ACL failure mode that can affect reads and patches.

## Commit Cadence

Commit working changes as you go instead of letting broad work accumulate uncommitted. After each coherent implementation slice passes its focused validation, make an intentional commit with the relevant code, tests, and documentation. If the worktree contains unrelated user changes, leave them unstaged unless the user explicitly asks to include them.

## Live UI And WOS Debugging

When the development site is already running, inspect the live Rails URLs before inferring behavior from files or stale state. In the dev stack the Rails app is commonly available at `http://localhost:31050`; check `/overlay` for browser-source overlay output, `/wos_brain` for affordance status, and `/admin/event_pipeline` for queue depth/spy/clear actions before digging deeper.

For WOSBrain recognition, keep the implementation geometry-driven:

- Detect the number of letter tiles from the dark tile boxes in the board scan region; do not hard-code a fixed tile count.
- Detect remaining word slots from repeated blank-slot rectangles/components; do not hard-code a fixed answer count.
- Use Tesseract for small text such as solved words/player labels, and as a fallback/debug signal for tile letters. The primary tile-letter path should use deterministic image features/templates from real WOS glyph crops because the letters are large, regular, and poorly served by raw OCR.

If WOS recognition appears stale, compare the `/wos_brain` timestamps with `/admin/event_pipeline` queue depth first. Captures may be current while projection is stale; a growing `orinoco.wos.board.recognized.queue` with an old `last_projected_at` points at the projection worker path rather than OBS capture. Use direct Redis/SQS inspection only when the HTTP pages lack the needed detail or when performing an explicit destructive operation such as purging a queue.
## Root Files To Be Careful With

- `development.env`, `production.env`, and `test.env` control service wiring.
- `development-compose.yml`, `production-compose.yml`, and `test-compose.yml` define the top-level stack shape.
- The corresponding `*-overrides.yml` files carry ports, env overrides, and dependency wiring.
- `commands.txt` and `README.md` are human-facing references for the root workflow.
