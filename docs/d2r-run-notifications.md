# D2R run notifications

This slice lives on top of the visual observer branch. It does not make up character levels, session boundaries, or named steps from the fast screen classifier.

## Stream contracts

The existing `orinoco.d2r.events` topic feeds `D2rRunProjectionWorker` through `orinoco.d2r.events.queue`. Its Redis read model is exposed at `GET /d2r/run` and rendered inside the canonical `/overlay` browser source.

Event envelope timestamps (`occurred_at`) determine event order/durations, not projection processing time.

- `d2r.game.started`: `{ "game_id": "unique-id" }`. Must fire on an actual new-game boundary; a loading screen alone is not sufficient.
- `d2r.game.ended`: `{}`. Closes the active run step.
- `d2r.level.changed`: `{ "level": 85 }`. Sticky character level until replaced.
- `d2r.area.changed`: `{ "area": "Tower Cellar Level 1" }`. Sticky current area until replaced or new game starts.
- `d2r.run.selected`: `{ "kind": "countess" }`. Defines the run category for the active game.
- `d2r.run.step`: `{ "name": "tower" }`. Ends the previous step and begins this one.

Detected screen events (boss, loading, player death, area banner) populate the five-event visible feed. Bare state changes update sticky screen state without spamming the feed. The overlay displays recent events newest-first with timestamps, character level, area, game elapsed time, current run/step, completed splits, and deltas against the immediately preceding game if the run kind matches. Run step names should remain stable across attempts.

Only the five displayed events are retained in this projection; it is not a durable event-history store. Prior game splits are retained for the comparison, not an unlimited history. A genuine elapsed timer requires a `game.started` event from a future game-boundary recognizer or other trusted producer. At present, the classifier recognizes loading/screens, but not authoritative new-game boundaries, levels, or named steps.

## Run locally

Start the usual development environment (the `d2rprojection` Procfile entry runs the consumer), or start `d2r-run-projection-worker` through Compose. OBS browser source uses `/overlay`. A non-OBS consumer may query `/d2r/run` for the JSON projection.

## Checks

`bundle exec rspec spec/services/d2r/run_projection_spec.rb`

The specs exercise timestamp ordering, capped history, sticky state, repeated-run comparisons, and per-step durations using an in-memory Redis fake.
