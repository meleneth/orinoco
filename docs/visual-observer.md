# Visual observer: OBS calibration and D2R direction

The OBS command bridge now supports `GetSceneItemTransform` and `GetVideoSettings`
through the existing `obs.command.requested` -> `obs.command.completed` flow.
Use the `OBS_COMMAND_RESULT_TOPIC` as `reply_topic` for command responses that
need downstream processing; the screenshot result topic is reserved for images.

## Calibrating a region

1. Open the target UI panel in the game.
2. In OBS, create a *separate calibration scene* with a reference to the actual game source.
   Do not modify the live game capture item.
3. Crop and resize the scene item in OBS. The item's visible crop marks the recognition region.
4. Issue a `GetSceneItemTransform` command with the scene name and item ID.
5. Feed `response.sceneItemTransform` into `VisualObserver::Calibration.import` along
   with the scene, source name, and base reference dimensions obtained from
   `GetVideoSettings`. Persist the resulting geometry as a named region.

The importer's `rect` is normalized to **uncropped source dimensions**, not to
OBS scene placement or the resized output. Preserve both transform and reference
dimensions for diagnostics and regression fixture replay.

Important: OBS `GetSourceScreenshot` can resize an image but does not accept
arbitrary source crop coordinates. Capturing a separate cropped OBS source or
cropping after capture is still required. Do not claim this work implements
automatic game detection, scene setup, polling, OCR, or persistent storage.

## Next vertical slices

- A request/result consumer that correlates transform replies with calibration imports
  and persists named profiles in Postgres.
- An OBS setup and calibration UI that creates temporary reference scene items,
  enumerates item IDs, and initiates import.
- Source-region capture benchmarking using screenshot results.
- A D2R screenshot classifier and deterministic fixture-based tests, followed by
  run-state tracking, inventory reconciliation, and commentary projections.

## Collecting D2R fixtures on Linux

The root `d2r_capture` wrapper connects to the host OBS WebSocket through a
temporary host-networked Rails container. It mounts OBS's WebSocket config
read-only so the password is never copied into the repository, command line,
capture manifest, or process environment. It does not switch scenes or mutate
source transforms.

OBS and D2R must already be running. To collect a confirmed three-frame burst:

```sh
./d2r_capture capture gameplay_idle \
  --source "[Game] Game Capture" \
  --confirmed \
  --frames 3 \
  --interval 1 \
  --label location=town \
  --label minimap=open
```

For an interactive checklist that waits before every state:

```sh
./d2r_capture guide \
  --source "[Game] Game Capture" \
  --states gameplay_idle,inventory_open,item_tooltip_rune,stash_runes,stash_other
```

Raw captures are stored in the gitignored directory
`railsapp/tmp/d2r-captures/<session-id>/`. Each session contains the original
source frames and `manifest.json`, including frame hashes and dimensions, OBS
base/output/source dimensions, the raw scene-item transform, expected state,
and manually confirmed labels. Unknown metadata remains `null`.

Validate all local sessions with:

```sh
./d2r_capture validate
./d2r_capture validate --require-pairs
```

The strict form fails until every detector listed by the validator has at least
one positive and one useful negative state. Missing states are expected during
an incomplete guided session; never invent them.

After reviewing a frame for private or unrelated content, promote only a small,
representative labeled selection:

```sh
mkdir -p railsapp/spec/fixtures/files/d2r
cp railsapp/tmp/d2r-captures/<session-id>/frame-01.png \
  railsapp/spec/fixtures/files/d2r/<descriptive-state-name>.png
```

Do not promote a large raw corpus or overwrite an existing fixture. Add the
fixture and its explicit truth to a focused detector spec in the same commit.

## Fast D2R state observation

The development stack includes separate `d2r-observer-capture-worker` and
`d2r-observer-processor-worker` services. Both use the persisted
`d2r_observer` `AffordanceConfig`; disabling the affordance stops new capture
requests and causes the processor to ignore queued frames. The default config
requests a 640x400 JPEG at quality 70 every 0.5 seconds, with only one request
in flight. It also waits for a current OBS bridge heartbeat, so a disconnected
bridge cannot create an ever-growing command queue.

The processor classifies four independent signal groups—screen, left panel,
right panel, and tooltip—then requires two matching observations out of three
for ordinary changes. High-confidence loading and death states can enter
immediately. It publishes changes to `orinoco.d2r.events`; unchanged frames do
not produce events. OCR is intentionally excluded from this fast path.

Enable it from Basic Setup by selecting the game source and checking **Enable
D2R Observer affordance**. The current deterministic model is generated from
the sanitized training fixtures with:

```sh
cd railsapp
bin/rails runner script/build_d2r_fast_classifier.rb
bin/rails runner script/benchmark_d2r_fast_classifier.rb
```

Keep the native fixture corpus local. The committed 480x300 JPEGs are split
into training and held-out images in `spec/fixtures/files/d2r/truth.yml`.
