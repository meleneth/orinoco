# Stardew Valley Year-One Coach (design and implementation contract)

Status: design baseline; runtime integration not yet implemented.
Target: Stardew Valley 1.6.x on Linux, SMAPI, default Community Center bundles, Year 1. Existing Orinoco event-pipeline conventions apply.

## Goal

Answer "what should I do today?" using *observed game state*, not a rigid calendar. Prioritize Community Center completion by Winter 28 of Year 1 while optimizing a configurable secondary score (money, relationships, farming/fishing/mining progression, Grandpa evaluation, or weighted combination). Never claim completion is guaranteed where settings/randomness make it uncertain.

## Shape

1. **In-game SMAPI mod** (`stardew_mod/` suggested): C# read-only game-state adapter; publishes versioned local observations to a loopback bridge, exposes a small optional in-game to-do panel. No planning or save manipulation. Use GameLoop.SaveLoaded, DayStarted, DayEnding/Saved, ReturnedToTitle, update ticks with debouncing; inspect progression and inventory at meaningful transitions. Initial state always includes a full snapshot. Game code and APIs should be inspected against installed SMAPI and the pinned game's version.
2. **Local host bridge**: forwards SMAPI observations to `orinoco.stardew.events` using established SNS/SQS semantics. Bind ingestion to loopback, authenticate requests and reject foreign origins. If Orinoco is offline, spool a bounded journal locally with stable event IDs and replay on reconnection. Preserve sequence, save ID, player ID, game tick, game-day and event occurrence time. Surface running/disconnected/stale state and manual force refresh in bridge control.
3. **Rails projection**: event consumer persists daily/game history to PostgreSQL and serves compact Redis "current day" projection. Idempotent event processing keyed by save/player/event ID; reconcile from authoritative full snapshots after reconnection. Separate observations from planner recommendations.
4. **Planner affordance**: pure deterministic Ruby domain service consuming a canonical immutable state and a versioned ruleset. Emits plan.updated, task.completed, deadline.at_risk and score.updated to the event pipeline. Run once at day start, on material state changes and upon explicit replan; never at frame rate.
5. **UI**: Rails Hotwire `/stardew` and OBS browser overlay, showing ranked tasks, next deadline, daily progress, missing ingredients, required seeds and completion confidence. Optional in-game SMAPI HUD reads a lightweight current-plan projection. No periodic GET polling when a Turbo stream can update it; client-side clocks stay local. Status times use human "ago" formatting.

## Snapshot schema v1

- Identity: save ID (privacy-preserving), farm ID, player ID, multiplayer role, game build, SMAPI build, ruleset revision, save settings (including Year 1 completion guarantee and bundle remix status when introspectable).
- Clock/conditions: year, season, day, time, weather today/tomorrow when known, luck *only* when known in-game (no hidden prediction in honest mode), festival, map/location and coordinates.
- Resources: gold, inventory item IDs/quantities/qualities, chests and contents if reliably observable, shipping and mailbox state, tools/upgrades, crafting recipes, building and animal state.
- Farming: each soil/crop plot, seed ID, growth phase, planted date, fertilizer, watered status, regrowth, scarecrow coverage as available, greenhouse unlock; enough to compute harvest ETA and future harvest counts.
- Progression: bundle definitions and filled slots from live save data (standard and remixed), museum progress, fishing catches, skill levels, mine floors, quest flags, access unlocks.
- Social: quest introduction targets, actual conversation flags, friendship and birthday calendar; never infer that talking occurred merely from proximity.
- Proof: each fact records observation type/version; unavailable fields remain unknown rather than false.

## Planning model

Each task has stable ID, prerequisites, required inputs, expected yields, season/clock/weather/stock constraints, travel and energy/time estimates, risk, reward, explanation and completion predicate. Enforce hard deadlines before ranking soft gains. Score candidate schedules with a bounded multi-objective search, choosing from feasible options; allow deterministic heuristics first, then a more expensive search. Model travel time, shop hours, watering, energy recovery, tool requirements, days-to-grow, last planting day, fishing windows, seasonal and weather-constrained bundles, inventory capacity, and finance opportunity cost.

The initial priorities are:
- Don't miss a seasonal/unique Community Center requirement or Traveling Cart red cabbage opportunity.
- Reserve exact quantities and qualities needed for bundles, seeds and recipes; do not recommend selling reserved items.
- Ensure minimum crop harvests and quality-crop counts *actually required* by the active bundles.
- Schedule rain-only fish and special-access fish before their windows close.
- Aim for year-one completion; if not feasible, show blockers and best available recovery plan.
- Maximize net value of optional activity under the player's chosen scoring function.

Always treat an asset as observed/owned, available in shop, planned, or speculative. No impossible schedules. Allow preference toggles: `balanced`, `aggressive-economy`, `community-center-first`, `friendship`, `grandpa`; secondary objective should not silently override Year 1 completion.

## Spring 1 seed plan

Starting state: 15 parsnip seeds, 500g on standard fresh-farm settings; must verify from snapshot. Plant and water starting parsnips (unless model determines a different feasible tradeoff); introduce as many reachable villagers as possible and mark actual unique conversations. Willy normally becomes available to the introduction route on Spring 2, so do not promise 28/28 on Spring 1. Cluster the day's NPC route by real schedule/time windows and location; optionally collect forage along route and buy seeds while Pierre's is open. Calculate purchases from *real* wallet, season, available shop inventory and planted plots. No fixed claim that a particular route is always optimal.

Spring 2: Willy fishing rod if available; use fishing as candidate early capital. Spring 5+: Community Center access quest only under its actual trigger conditions; route to Wizard on subsequent unlock. Critical seasonal routes recalculated on rain, calendar and access changes.

## Year 1 pitfalls

- Read actual bundle definitions rather than assuming default bundles (remixed and multiplayer).
- Detect `Guarantee Year 1 Completable` advanced setting when accessible; the Traveling Cart can provide red cabbage seeds at least once under this setting, but timing may force greenhouse planting. Without guarantee, show uncertain completion and recovery options. Check Friday and Sunday cart visits (and special Night Market appearances as applicable); never mark red cabbage assured from ordinary randomized stock.
- Seasonal crop/fish and quality crop deadlines, especially when crop growth or tool availability makes the last feasible planting day earlier than season end.
- Animal products, truffle, rabbit's foot, greenhouse and artisan dependencies can create long lead times. Infer dependencies backward from remaining bundles.
- Do not leak future RNG or hidden inventories in "fair-play" mode. Explicit optional spoiler/predictor mode is a separate opt-in policy.

## Candidate events

`stardew.save.loaded`, `stardew.day.started`, `stardew.day.ended`, `stardew.snapshot`, `stardew.inventory.changed`, `stardew.crop.changed`, `stardew.bundle.changed`, `stardew.npc.talked`, `stardew.skill.changed`, `stardew.location.changed`, `stardew.bridge.status.changed`.

All envelopes: `event_id`, `schema_version`, `save_id`, `player_id`, `sequence`, `occurred_at`, `game_time`, `payload`. Consumer dedupes; snapshots reconcile missing deltas. Do not emit sensitive full local paths or player-real-world IDs.

## Acceptance criteria

1. Starting a new standard save generates the Spring 1 plan, 15 starting seeds and introduction checklist from game state.
2. Actual first-time NPC dialogue completes tasks, repeat dialogue does not; inaccessible introductions roll to later day.
3. Plant/harvest/sell/ship changes update crop inventory, protected bundle stock, harvest goals and plan without manually checking boxes.
4. Waiting through late Spring and reaching last planting dates causes explicit at-risk alerts with correct calculations.
5. Day-start rain and upcoming forecast change the fishing schedule without polling every frame.
6. A cart observation and red cabbage acquisition update the completion feasibility indicator; no invented inventory.
7. Disconnect/restart/reconnect replays events once and reconciles a fresh snapshot without duplicating NPC talks or harvests.
8. Two saves/multiplayer characters cannot cross-pollute their goals; remixed bundles have dynamic requirements.
9. The plan is deterministic for a recorded snapshot and ruleset; fixture-based regression tests cover Spring 1, Spring 2, Spring 5, late Spring, rainy Fall, and red cabbage purchased too late for outdoor planting.
10. Overlay updates use Turbo Streams; browser does not continuously poll Rails; local UI timers never cause a CSS rebuild.
11. Status shows connected/stale/offline and last observation in relative "ago" format, plus explicit force-refresh and override controls.
12. Build SMAPI mod against Linux game references using a pinned .NET SDK. Any container build uses Debian Trixie, not Alpine. Tests don't require launching the game; real-game smoke validation is documented separately.

## Phased delivery

- M1: versioned SMAPI adapter, localhost transport, snapshot storage, bridge status and fixture replay; prove crop/NPC/inventory observation against a real save.
- M2: default Community Center dependency DAG, first-week daily agenda, real NPC route and crop/harvest reserve planning, RSpec golden fixtures.
- M3: seasonal fishing, tool/mining/animal/greenhouse dependencies; Year 1 risk alerts and Traveling Cart rules; feasible score search.
- M4: Hotwire dashboard and streaming overlay; optional SMAPI in-game panel, configurable priorities and campaign score.
- M5: replay-based score and benchmark harness comparing proposed daily plans to a known baseline; optimize only on validated data.

Reference: SMAPI event guide https://stardewvalleywiki.com/Modding:Modder_Guide/APIs/Events and Traveling Cart year-one guarantee https://stardewvalleywiki.com/Traveling_Cart.
