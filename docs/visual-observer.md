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
