# D2R run notifications

The run archive and live overlay consume the existing D2R detection events on `main`. Inferred run categories and splits come from observed area transitions; they are not manually selected or fabricated from screenshots.

## Stream contracts

The existing `orinoco.d2r.events` topic feeds `D2rRunProjectionWorker` through `orinoco.d2r.events.queue`. Its Redis read model is exposed at `GET /d2r/run` and rendered inside the canonical `/overlay` browser source.

Event envelope timestamps (`occurred_at`) determine event order/durations, not projection processing time.

- `d2r.game.started`: `{ "game_id": "unique-id" }`. The visual tracker emits this only after a confirmed character-selection → loading → gameplay sequence; an in-game loading screen alone is not sufficient.
- `d2r.game.ended`: `{}`. Closes the active run step.
- `d2r.level.changed`: `{ "level": 85 }`. Sticky character level until replaced.
- `d2r.area.changed`: `{ "area": "Tower Cellar Level 1" }`. Sticky current area until replaced or new game starts.
- `d2r.difficulty.changed`: `{ "difficulty": "Hell" }`. Sticky game difficulty read from the automap information HUD.
- `d2r.terror_zones.changed`: `{ "terror_zones": ["Dry Hills", "Halls of the Dead"] }`. Sticky terror-zone list; the purple strength/element modifier is excluded.
- `d2r.run.selected`: `{ "kind": "countess" }`. Optional legacy override. Ordinary unattended tracking infers run categories from detected areas, with confidence and evidence.
- `d2r.run.step`: `{ "name": "tower" }`. Ends the previous step and begins this one.

Detected lifecycle and domain events (game boundaries, named area changes, bosses, player death, and area banners) populate the five-event visible feed. Loading transitions remain available to the lifecycle FSM but do not consume a visible slot. Difficulty and terror-zone changes update their sticky info rows without consuming an event slot. Bare classifier state changes also stay out of the feed. Like the chat browser source, the event feed is server-rendered and updated over Turbo Streams; each update replaces the feed with the projection's newest five messages so a long-running overlay cannot accumulate stale DOM nodes. The initial overlay embeds the Redis snapshot. A single Turbo Stream replacement carries the event feed and sticky run/timer fields whenever the displayed projection changes. The Stimulus controller updates the local timer without network traffic; it requests a fresh Turbo Stream snapshot from `/d2r/run` only when the stream connects or reconnects. There is no periodic HTTP polling. The history panel remains outside the replaced fragment. The JSON endpoint is retained for external consumers. The overlay displays recent events newest-first with timestamps, character level, area, difficulty, terror zones, game elapsed time, current run/step, completed splits, and deltas against the immediately preceding game if the run kind matches. Run step names should remain stable across attempts.

The archive stores per-game run kind, confidence, evidence, ordered area splits, rune sightings and possible unique-item names in PostgreSQL. The overlay's **Browse runs** panel paginates the archive and loads complete details on demand. An item seen on the ground is a **sighting**, not evidence it was picked up. The observer emits a unique sighting once per item label and area in each game. A label can disappear and reappear without creating another event. Rune sightings are collapsed while the label stays visible.

The Countess recognizer uses the Black Marsh → Forgotten Tower → Tower Cellar progression. Entering Black Marsh alone is insufficient; reaching deeper tower levels increases confidence. A rune label observed in Tower Cellar Level 5 adds supporting evidence. The same stream recognizes other distinctive target areas, including the Catacombs, Durance of Hate, Chaos Sanctuary, Throne, Travincal and Moo Moo Farm.

The screenshot processor uses a general HUD OCR fallback when its reference matcher lacks an area, and a ground-label reader for rune names and possible gold-text unique-item names. Candidate labels require repeated observations. These recognizers are **not fixture-validated for all routes and labels**; add confirmed screenshots and negative examples before treating observations as reliable loot accounting. Extraction is bounded to selected screen regions, but OCR throughput still needs live benchmarking.

The decorative D2R HUD font is not reliably recognized by stock Tesseract. `D2r::HudReader` instead segments right-aligned gold and purple rows by color and compares normalized line geometry with confirmed reference crops under `spec/fixtures/files/d2r/hud`. When a previously unseen label appears, add a confirmed reference capture and a holdout example before claiming support for it.

Only the five displayed events are retained in the Redis projection; PostgreSQL holds the per-game history. Prior game splits are retained for the comparison, not an unlimited history. A genuine elapsed timer requires a verified `d2r.game.started` event. The visual tracker creates one from a confirmed character-selection → loading → gameplay sequence; startup while already in a game remains a limitation.

## Run locally

Start the usual development environment (the `d2rprojection` Procfile entry runs the consumer), or start `d2r-run-projection-worker` through Compose. OBS browser source uses `/overlay`. A non-OBS consumer may query `/d2r/run` for the JSON projection.

## Checks

`bundle exec rspec spec/services/d2r/run_projection_spec.rb`

The specs exercise timestamp ordering, capped history, sticky state, repeated-run comparisons, and per-step durations using an in-memory Redis fake.

## Character-menu recognizer fixtures

The fast classifier uses trained screen fingerprints from confirmed captures. The guided capture vocabulary now includes two distinct screens:

- `character_select`: the character roster.
- `character_creation`: the new-character creation interface, not the in-game character sheet.

Collect confirmed examples using the existing wrapper:

```sh
./d2r_capture guide --source "[Game] Game Capture" --states character_select,character_creation,gameplay_idle,loading_screen
./d2r_capture validate
```

Review the captured frames, add train and holdout examples with explicit `screen` labels to `railsapp/spec/fixtures/files/d2r/truth.yml`, then regenerate the fingerprints via `railsapp/script/build_d2r_fast_classifier.rb`. Run held-out classifier specs and the state-tracker specs. Do **not** add dummy fingerprints or claim these menus are recognized until the real labeled images have been collected and verified.

Once the model recognizes them, the tracker publishes `d2r.character.selection.visible` or `d2r.character.creation.visible` on confirmed transitions. These are lifecycle observations, not authoritative `d2r.game.started` events.
