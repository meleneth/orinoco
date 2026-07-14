# MSYS_AGENTS.md

Guidance for AI coding agents working in this repository from the Windows/MSYS setup.

## Shell And Path Assumptions

- The active agent shell is usually PowerShell, even though the repository lives under `C:\msys64\home\melen\code\orinoco`.
- Use Windows paths for tool `workdir` values, for example `C:\msys64\home\melen\code\orinoco`.
- Prefer PowerShell-native read/list commands from the agent shell:
  - `Get-Content path\to\file`
  - `Get-ChildItem path\to\dir`
  - `Select-String -Path path\to\file -Pattern "text"`
- Use `rg` for repository searches when available.
- Do not assume `./script` executes directly from PowerShell. Invoke shell wrappers through `bash` when needed.

## Rails App Commands

From `railsapp/`, use the Rails-side `dev.sh` wrapper through `bash`:

```sh
bash ./dev.sh spec spec/components/chat_message_component_spec.rb
bash ./dev.sh tmigrate
bash ./dev.sh server
bash ./dev.sh bridge
```

`dev.sh` only defines the shortcuts listed in that file. Unknown commands are passed to Rails, so do not run tools such as RuboCop through `dev.sh`.

For RuboCop, use Bundler directly from `railsapp/`:

```sh
bundle exec rubocop app/components/chat_message_component.rb
```

For lightweight syntax checks that do not require the database:

```sh
ruby -c app/components/chat_message_component.rb
ruby -c spec/components/chat_message_component_spec.rb
```

## Docker And Test Services

RSpec loads Rails and expects the test Postgres service from the test compose stack. If specs fail with connection refused on port `31000`, Docker Desktop or the test stack is not running.

Start the test stack from the repository root:

```sh
bash ./dc_test up -d
```

Then run focused specs from `railsapp/`:

```sh
bash ./dev.sh spec spec/components/chat_message_component_spec.rb
```

Use the root compose wrappers for compose inspection and lifecycle work:

```sh
bash ./dc_dev ps
bash ./dc_test ps
bash ./dc_test logs orinoco-db
```

If Docker commands fail with `npipe:////./pipe/dockerDesktopLinuxEngine`, Docker Desktop is not running or the Linux engine is unavailable.

## Sandbox And Permissions

On this Windows/MSYS setup, file reads or `apply_patch` may fail with:

```text
windows sandbox: helper_unknown_error: apply deny-read ACLs
```

When that happens:

- Retry the same read command with escalation instead of changing strategy blindly.
- Keep escalated commands narrow and path-specific.
- If `apply_patch` cannot read a file because of the ACL issue, use a scoped PowerShell edit as a fallback and immediately verify the diff.
- Do not use destructive cleanup commands to work around ACL problems.

After permission repair scripts are run, re-check:

```sh
git status --short
```

Then re-read the relevant guidance files before continuing.

## Current Practical Verification Pattern

For narrow Rails component changes:

```sh
ruby -c app/components/the_component.rb
ruby -c spec/components/the_component_spec.rb
bundle exec rubocop app/components/the_component.rb spec/components/the_component_spec.rb
bash ./dev.sh spec spec/components/the_component_spec.rb
```

If the final spec command is blocked by Docker/Postgres, report the exact connection error and the compose command needed to unblock it.
