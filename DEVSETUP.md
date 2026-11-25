## How do I run this?

The development Docker containers now use bind mounts, so changes made in `railsapp/` on your host should be visible inside the running containers.

From the project root:

```bash
./dc_dev css
./dc_dev build
./dc_dev up -d
./dc_dev ps
./dc_dev restart twitch-chat-worker
```

This builds the Rails image and starts the development containers.

The Rails app is available at:

[Docker Orinoco](http://localhost:31050/)

## Cached Tailwind CSS builds

Tailwind CSS is an explicitly maintained artifact, not an application build dependency.
The extensive utility safelist deliberately overcompiles CSS so ordinary Ruby,
ERB, component and JavaScript edits do not require a rebuild.

```bash
./dc_dev css          # reuse host CSS; export existing builder image if missing
./dc_dev css --force  # explicitly compile and atomically export a new stylesheet
```

On a fresh checkout with neither a stylesheet nor a builder image, the first
`./dc_dev css` bootstraps the artifact. Otherwise it never recompiles existing
CSS. The force option invalidates the compilation layer but keeps dependency
layers cached. No database or worker needs to start.

All application image builds (development, test and production) consume the
existing `railsapp/app/assets/builds/tailwind.css` from the build context.
They fail loudly if it is absent instead of silently compiling it. Generate
or transfer that artifact before building on another machine or in CI.
Rails asset precompilation still fingerprints the existing CSS.
Foreman no longer runs a Tailwind watcher.

Only force a rebuild when an actually missing utility or intentional CSS
change warrants it. Keep dynamically generated classes in the safelist.

## Running on Windows

From the project root:

```bash
./dc_dev up -d
cd railsapp
dev.sh server
```

In another terminal:

```bash
cd railsapp
dev.sh bridge
```

## Running Rails directly on the host

You can still run Rails directly if you prefer:

```bash
cd railsapp
bundle install
./bin/dev
```

`rbenv` can help manage Ruby versions.

Install rbenv using the official instructions:

[rbenv installation instructions](https://github.com/rbenv/rbenv?tab=readme-ov-file#basic-git-checkout)

After your shell is updated and reloaded:

```bash
rbenv install 4.0.1
rbenv global 4.0.1
ruby --version
```

Ruby libraries are called gems. `bundler` installs the gems listed in `Gemfile` / `Gemfile.lock`, similar to how npm installs packages from `package.json`.

```bash
bundle install
```

## Docker Desktop

Install Docker Desktop if needed:

[Docker Desktop install on Linux](https://docs.docker.com/desktop/setup/install/linux/debian/)

## Environment variables

Environment variables configure how the services talk to each other.

For Docker Compose, environment variables live in:

```text
test.env
development.env
production.env
```

For local Rails / Foreman-style execution, environment variables live in:

```text
railsapp/.env.dev.orinoco
railsapp/.env.test.orinoco
```

Inside `railsapp/`, `./r_dev` is a wrapper script similar to `dc_dev`. It runs Rails commands with the Orinoco development environment loaded from `.env.dev.orinoco`.

## Service URLs

Docker Rails app:

[Docker Orinoco](http://localhost:31050/)

Foreman/local Rails app:

[Foreman Orinoco](http://localhost:33230/)

## Useful service commands

Open a Redis CLI:

```bash
./dc_dev exec scoreboard-redis redis-cli
```

Open a Postgres CLI:

```bash
./dc_dev exec orinoco-db psql -U orinoco-db-development-user -d orinoco-db_development
```

## Quiet operational logs

GoAWS defaults to `warn` using its native `-loglevel` flag. Routine empty
polls and informational broker traffic should not flood Compose logs.
Warnings and errors remain enabled. To temporarily investigate broker traffic:

```bash
GOAWS_LOG_LEVEL=debug ./dc_dev up -d --no-deps --force-recreate goaws
# Restore normal logging:
./dc_dev up -d --no-deps --force-recreate goaws
```

Recreating GoAWS can discard its in-memory queues and messages. Do this
when the event pipeline is idle, not during a run you want to preserve.
OBS command receipt logging is also disabled by default; set
`ORINOCO_LOG_LEVEL=debug` in the OBS worker container environment to enable it.
Failures and retry warnings remain visible. Follow the stack with
`./dc_dev logs -f --tail=100`.
