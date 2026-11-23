# orinoco

Streamer tech that doesn't make you hate your life.

---

## What this is

Right now, most streamer setups look like this:

* random scripts
* direct API calls
* copy-pasted glue
* "why did that fire twice" energy

Orinoco is an attempt to replace that with something that actually has a shape.

At the core: **everything is events**.

Stuff happens → events get emitted → something reacts → more events happen.

No spooky action. No hidden wires.

---

## Where we are

* OBS bridge exists (works, but… yeah)
* event pipeline exists (SNS/SQS via GoAWS)
* ClipShow works (trigger clips, disable on finish)
* a lot of things are still duct-taped together

Also:

> the OBS bridge is like a million files and I regret my life choices

---

## Where we're going

A local-first system you run with docker-compose:

* Rails app (UI + config + projections)
* Postgres (real data)
* Redis (fast stuff / derived state)
* GoAWS (SNS/SQS event pipeline)
* bridges for external systems (OBS, Twitch, Discord, etc)

You run:

```
docker compose up
```

Open a browser.
Configure stuff.

The system builds itself around what you enable.

---

## The Shape (important)

This is the part that actually matters.

### Event Pipeline

SNS topics + SQS queues.

Everything moves through here.

If it's not in the pipeline, it doesn't exist.

---

### Bridges

Bridges talk to the outside world.

Examples:

* OBS bridge
* Twitch bridge
* (eventually) Discord bridge

They:

* receive external events → publish into pipeline
* consume pipeline events → call external APIs

They do **not** decide behavior.

They are translators, not brains.

---

### Affordances

This is where behavior lives.

Affordances:

* listen to events
* run logic
* emit new events

They do not:

* call OBS directly
* talk to Twitch directly

Example: ClipShow

* sees "media finished playing"
* emits "disable that source"

That's it.

---

### Projections (Redis)

Redis holds "what we know right now".

Examples:

* last N chat messages
* OBS inventory
* recent events (for debugging)

Built from events.

UI reads from here.

---

### UI / Overlays (Hotwire)

Rails does two jobs:

1. control UI
2. OBS browser source rendering

Hotwire means:

* change data → UI updates automatically

So the same system:

* configures your stream
* renders your overlays

No separate frontend nonsense.

### Development OBS and D2R setup

OBS must have its WebSocket server enabled on port `4455`. On Linux, `./dc_dev`
automatically finds the native or Flatpak OBS WebSocket configuration, mounts it
read-only into the OBS bridge, and runs that bridge on the host network so it can
reach OBS at `localhost` without copying the password into an env file. The dev
override enables the bridge at worker startup; other environments retain the
shared default-off lifecycle unless they opt in.

Bootstrap the stack and its canonical OBS scene/source with:

```sh
./dc_dev up -d
./dc_dev exec -T railsapp bin/rails tailwindcss:build
./dc_dev exec -T railsapp bin/rails runner script/interaction_demo_setup.rb
```

The setup job is idempotent. It creates or updates the `Orinoco` scene and
`OrinocoWebView` browser source at `http://127.0.0.1:31050/overlay`. When the
`d2r_observer` affordance is enabled, its capture worker also runs this setup
automatically after the OBS bridge connects and ensures the canonical source is
placed in the `Game` scene (override with `D2R_OVERLAY_SCENE_NAME`). The overlay
base URL can be overridden with `ORINOCO_OVERLAY_BASE_URL`.

If the browser source is present but transparent, verify that
`railsapp/app/assets/builds/tailwind.css` exists. Re-run the Tailwind build and
refresh the browser source; the first minified build can take about a minute.

The D2R path uses three shared workers: capture, classify/process, and run
projection. They are defined in the shared Compose service layer; development
only supplies its environment, host OBS transport, and bind mounts. The D2R
affordance and its `[Game] Game Capture` source are configured on Basic Setup.
The observer requests a 1920x1200, quality-90 source image by default. That resolution keeps
the top-right automap information legible while the fast screen classifier
still fingerprints a small internal thumbnail. With the automap information
visible, confirmed HUD rows publish current area, difficulty, and terror-zone
events into the normal D2R event pipeline and `/overlay` projection.

---

## Design Rules (these will get broken if not written down)

* events over direct calls
* bridges translate, affordances decide
* UI reads projections, not raw events
* no hidden side effects
* if you can't observe it, it didn't happen

---

## Example flow (clip playback)

1. UI emits: "play clip"
2. pipeline routes it
3. OBS bridge enables scene item
4. OBS emits "playback ended"
5. ClipShow affordance sees it
6. emits "disable scene item"
7. OBS bridge applies it

Nothing talks to anything directly.

---

## Initial goals

* trigger clips
* disable clips on finish
* track who triggered what
* chained playback (A → B → C)
* random clip selection
* weighted / ordered randomness
* dumb/fun chat-driven games

---

## Things we know we need

* SQS bridge as the "clean" reference implementation
* refactor OBS bridge to match it
* event capture (store recent events in Redis for debugging)
* event type registry per domain (obs, twitch, etc)
* pipeline visualization (mermaid)
* UI for configuring affordances (ClipShow, etc)

---

## Longer term

* unified chat model (twitch + discord)
* pipeline editing UI
* overlay builder
* "chat event generifier" so one trigger works everywhere

---

## Why this is interesting

Because once this works, you stop writing scripts and start composing behavior.

Instead of:

> "when twitch says X, call OBS"

You get:

> "when event X happens, do Y"

And X can come from anywhere.

---

## Status

Active build.

Some parts are clean.
Some parts are cursed.

We're fixing it in public.
