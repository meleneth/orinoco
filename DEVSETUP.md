## How do I run this?

The development Docker containers now use bind mounts, so changes made in `railsapp/` on your host should be visible inside the running containers.

From the project root:

```bash
./dc_dev build
./dc_dev css
./dc_dev up -d
./dc_dev ps
./dc_dev restart twitch-chat-worker
```

This builds the Rails image and starts the development containers.

The Rails app is available at:

[Docker Orinoco](http://localhost:31050/)

## Cached Tailwind CSS builds

The Dockerfile has an independent `tailwind-builder` target. Its output is
compiled once per change to the gem dependencies or frontend inputs
(`app/assets/tailwind`, `app/views`, `app/components`, `app/javascript`).
Docker reuses that layer on backend-only rebuilds. The final Rails image
copies the compiled stylesheet and fingerprints assets without compiling
Tailwind a second time.

Development bind-mounts the application tree, hiding assets baked into the
image. Export the cached stylesheet to the host with:

```bash
./dc_dev css
```

This builds the dedicated container (normally a cache hit) and atomically
copies the CSS to `railsapp/app/assets/builds/tailwind.css`. No database, web
server or worker needs to start for this command.

After changing templates, components, JS or Tailwind source, run the same
command. If the stylesheet is stale despite that, force a fresh build:

```bash
./dc_dev css --force
```

The force option bypasses Docker's build cache, including dependency layers,
so reserve it for troubleshooting. Do not delete the bundle volume or prune
Docker globally to refresh CSS. For production, rebuilding the Rails image
automatically consumes the cached Tailwind stage; no host export is needed.
If adding another source directory for utility classes, update both
`app/assets/tailwind/application.css` source directives and the Dockerfile
target's COPY inputs. Keep dynamically generated classes in the safelist.

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
